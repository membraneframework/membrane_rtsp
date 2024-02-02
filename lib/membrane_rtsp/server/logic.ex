defmodule Membrane.RTSP.Server.Logic do
  @moduledoc """
  Logic for RTSP Server
  """

  require Logger

  alias Membrane.RTSP.{Request, Response, Server}

  @server "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Server)"
  @allowed_methods ["GET_PARAMETER", "OPTIONS", "DESCRIBE", "SETUP", "PLAY", "TEARDOWN"]

  defmodule State do
    @moduledoc "Struct representing the state of a server connection"
    @enforce_keys [:socket, :request_handler]
    defstruct @enforce_keys ++
                [
                  :rtp_socket,
                  :rtcp_socket,
                  :request_handler_state,
                  setupped_tracks: %{},
                  session_id: UUID.uuid4(),
                  phase: :init
                ]

    @type t :: %__MODULE__{
            socket: :inet.socket(),
            rtp_socket: :inet.socket() | nil,
            rtcp_socket: :inet.socket() | nil,
            request_handler: module(),
            request_handler_state: term(),
            setupped_tracks: Server.Handler.setupped_tracks(),
            session_id: binary(),
            phase: :init | :setup | :playing
          }
  end

  @spec process_request(binary(), State.t()) :: {:ok, State.t()} | {:halt, State.t()}
  def process_request(raw_request, %State{} = state) do
    {response, state, halt?} =
      case Request.parse(raw_request) do
        {:ok, request} ->
          {response, state} = do_handle_request(request, state)
          {maybe_add_cseq_header(response, request), state, request.method == "TEARDOWN"}

        {:error, _reason} ->
          {Response.new(400), state, false}
      end

    response
    |> Response.with_header("Server", @server)
    |> Response.stringify()
    |> then(&:gen_tcp.send(state.socket, &1))

    if halt?, do: {:halt, state}, else: {:ok, state}
  end

  defp do_handle_request(%Request{method: method}, state) when method not in @allowed_methods do
    {Response.new(501), state}
  end

  defp do_handle_request(%Request{method: "OPTIONS"}, state) do
    Response.new(200)
    |> Response.with_header("Public", Enum.join(@allowed_methods, ", "))
    |> then(&{&1, state})
  end

  defp do_handle_request(%Request{method: "GET_PARAMETER"}, state) do
    {Response.new(200), state}
  end

  defp do_handle_request(%Request{method: "DESCRIBE"} = request, state) do
    {response, request_handler_state} =
      state.request_handler.handle_describe(request, state.request_handler_state)

    {response, %{state | request_handler_state: request_handler_state}}
  end

  defp do_handle_request(%Request{method: "SETUP"} = request, state)
       when state.phase != :playing do
    with {:ok, transport_opts} <- Request.parse_transport_header(request),
         :ok <- validate_transport_parameters(transport_opts, state),
         {response, request_handler_state} <-
           state.request_handler.handle_setup(request, state.request_handler_state) do
      if Response.ok?(response) do
        {:ok, transport_header} = Request.get_header(request, "Transport")
        <<ssrc::32>> = :crypto.strong_rand_bytes(4)

        transport_header =
          transport_header <> ";ssrc=#{:binary.encode_unsigned(ssrc) |> Base.encode16()}"

        {track_config, transport_header} =
          case transport_opts[:transport] do
            :TCP ->
              config =
                %{
                  socket: state.socket,
                  channels: transport_opts[:parameters]["interleaved"]
                }

              {config, transport_header}

            :UDP ->
              config =
                %{
                  socket: state.rtp_socket,
                  rtcp_socket: state.rtcp_socket,
                  client_port: transport_opts[:parameters]["client_port"]
                }

              {config,
               transport_header <>
                 ";server_port=#{:inet.port(state.rtp_socket)}-#{:inet.port(state.rtcp_port)}"}
          end

        track_config =
          Map.merge(track_config, %{ssrc: ssrc, transport: transport_opts[:transport]})

        setupped_tracks = Map.put(state.setupped_tracks, request.path, track_config)

        response
        |> Response.with_header("Session", state.session_id)
        |> Response.with_header("Transport", transport_header)
        |> then(&{&1, %{state | setupped_tracks: setupped_tracks, phase: :setup}})
      else
        response = Response.new(200) |> Response.with_header("Session", state.session_id)
        {response, %{state | request_handler_state: request_handler_state}}
      end
    else
      {:error, reason} ->
        Logger.error("error when handling SETUP request: #{inspect(reason)}")
        {Response.new(400), %{state | request_handler_state: state.request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "PLAY"}, %{phase: :setup} = state) do
    {response, request_handler_state} =
      state.request_handler.handle_play(state.setupped_tracks, state.request_handler_state)

    response = response |> Response.with_header("Session", state.session_id)

    if Response.ok?(response) do
      {response, %{state | request_handler_state: request_handler_state, phase: :playing}}
    else
      {response, %{state | request_handler_state: request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "TEARDOWN"}, %{phase: :playing} = state) do
    state.request_handler.handle_teardown(state.request_handler_state)
    |> Response.with_header("Session", state.session_id)
    |> then(&{&1, state})
  end

  defp do_handle_request(%Request{}, state) do
    {Response.new(405), state}
  end

  # TODO: Add more validation for transport parameters
  defp validate_transport_parameters(transport_opts, state) do
    cond do
      transport_opts[:mode] == :multicast ->
        {:error, :multicast_not_supported}

      transport_opts[:transport] == :UDP and is_nil(state.rtp_packet) ->
        {:error, :udp_not_supported}

      true ->
        :ok
    end
  end

  defp maybe_add_cseq_header(response, request) do
    case Request.get_header(request, "CSeq") do
      {:ok, value} -> Response.with_header(response, "CSeq", value)
      {:error, _no_such_header} -> response
    end
  end
end
