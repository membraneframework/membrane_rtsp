defmodule Membrane.RTSP.Server.Logic do
  @moduledoc """
  Logic for RTSP Server
  """

  import Mockery.Macro

  alias Membrane.RTSP.{Request, Response, Server}

  @server "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Server)"
  @allowed_methods ["GET_PARAMETER", "OPTIONS", "DESCRIBE", "SETUP", "PLAY", "PAUSE", "TEARDOWN"]

  defmodule State do
    @moduledoc "Struct representing the state of a server connection"
    @enforce_keys [:socket, :request_handler]
    defstruct @enforce_keys ++
                [
                  :rtp_socket,
                  :rtcp_socket,
                  :request_handler_state,
                  configured_media: %{},
                  session_id: UUID.uuid4(),
                  session_state: :init
                ]

    @type t :: %__MODULE__{
            socket: :inet.socket(),
            rtp_socket: :inet.socket() | nil,
            rtcp_socket: :inet.socket() | nil,
            request_handler: module(),
            request_handler_state: term(),
            configured_media: Server.Handler.configured_media_context(),
            session_id: binary(),
            session_state: :init | :ready | :playing | :paused
          }
  end

  @spec allowed_methods() :: [binary()]
  def allowed_methods(), do: @allowed_methods

  @spec process_request(binary(), State.t()) :: State.t()
  def process_request(raw_request, %State{} = state) do
    {response, state} =
      case Request.parse(raw_request) do
        {:ok, request} ->
          {response, state} = do_handle_request(request, state)
          {maybe_add_cseq_header(response, request), state}

        {:error, _reason} ->
          {Response.new(400), state}
      end

    response
    |> Response.with_header("Server", @server)
    |> Response.stringify()
    |> then(&mockable(:gen_tcp).send(state.socket, &1))

    state
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
       when state.session_state in [:init, :ready] do
    with {:ok, transport_opts} <- Request.parse_transport_header(request),
         :ok <- validate_transport_parameters(transport_opts, state) do
      {response, request_handler_state} =
        state.request_handler.handle_setup(request, state.request_handler_state)

      {response, state} = do_handle_setup_response(request, response, transport_opts, state)
      {response, %{state | request_handler_state: request_handler_state}}
    else
      _error ->
        {Response.new(400), %{state | request_handler_state: state.request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "PLAY"}, state)
       when state.session_state in [:ready, :paused] do
    {response, request_handler_state} =
      state.request_handler.handle_play(state.configured_media, state.request_handler_state)

    response = response |> Response.with_header("Session", state.session_id)

    if Response.ok?(response) do
      {response, %{state | request_handler_state: request_handler_state, session_state: :playing}}
    else
      {response, %{state | request_handler_state: request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "PAUSE"}, %{session_state: :playing} = state) do
    {response, request_handler_state} =
      state.request_handler.handle_pause(state.request_handler_state)

    response = response |> Response.with_header("Session", state.session_id)

    if Response.ok?(response) do
      {response, %{state | request_handler_state: request_handler_state, session_state: :paused}}
    else
      {response, %{state | request_handler_state: request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "TEARDOWN"}, state)
       when state.session_state in [:init, :ready] do
    Response.new(200)
    |> Response.with_header("Session", state.session_id)
    |> then(&{&1, %{state | configured_media: %{}, session_state: :init}})
  end

  defp do_handle_request(%Request{method: "TEARDOWN"}, state) do
    {response, _handler_state} =
      state.request_handler.handle_teardown(state.request_handler_state)

    response
    |> Response.with_header("Session", state.session_id)
    |> then(&{&1, %{state | session_state: :init, configured_media: %{}}})
  end

  defp do_handle_request(%Request{}, state) do
    {Response.new(455), state}
  end

  # TODO: Add more validation for transport parameters
  defp validate_transport_parameters(transport_opts, state) do
    cond do
      transport_opts[:mode] == :multicast ->
        {:error, :multicast_not_supported}

      transport_opts[:transport] == :UDP and is_nil(state.rtp_socket) ->
        {:error, :udp_not_supported}

      true ->
        :ok
    end
  end

  defp do_handle_setup_response(request, response, transport_opts, state) do
    response = response |> Response.with_header("Session", state.session_id)

    if Response.ok?(response) do
      track_config = build_track_config(transport_opts, state)
      resp_transport_header = build_resp_transport_header(request, track_config)

      configured_media = Map.put(state.configured_media, request.path, track_config)

      response = Response.with_header(response, "Transport", resp_transport_header)

      {response,
       %{
         state
         | configured_media: configured_media,
           session_state: :ready
       }}
    else
      {response, state}
    end
  end

  defp build_track_config(transport_opts, state) do
    <<ssrc::32>> = :crypto.strong_rand_bytes(4)

    case transport_opts[:transport] do
      :TCP ->
        %{
          ssrc: ssrc,
          transport: :TCP,
          tcp_socket: state.socket,
          channels: transport_opts[:parameters]["interleaved"]
        }

      :UDP ->
        {:ok, {address, _port}} = :inet.peername(state.socket)

        %{
          ssrc: ssrc,
          transport: :UDP,
          rtp_socket: state.rtp_socket,
          rtcp_socket: state.rtcp_socket,
          address: address,
          client_port: transport_opts[:parameters]["client_port"]
        }
    end
  end

  defp build_resp_transport_header(request, track_config) do
    {:ok, req_header} = Request.get_header(request, "Transport")
    resp_header = req_header <> ";ssrc=#{Integer.to_string(track_config.ssrc, 16)}"

    case track_config.transport do
      :TCP ->
        resp_header

      :UDP ->
        {:ok, rtp_port} = :inet.port(track_config.rtp_socket)
        {:ok, rtcp_port} = :inet.port(track_config.rtcp_socket)
        resp_header <> ";server_port=#{rtp_port}-#{rtcp_port}"
    end
  end

  defp maybe_add_cseq_header(response, request) do
    case Request.get_header(request, "CSeq") do
      {:ok, value} -> Response.with_header(response, "CSeq", value)
      {:error, _no_such_header} -> response
    end
  end
end
