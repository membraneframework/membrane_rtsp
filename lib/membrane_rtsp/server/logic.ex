defmodule Membrane.RTSP.Server.Logic do
  @moduledoc """
  Logic for RTSP Server
  """

  require Logger

  import Mockery.Macro

  alias Membrane.RTSP.{Request, Response, Server}

  @server "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Server)"
  @allowed_methods [
    "GET_PARAMETER",
    "OPTIONS",
    "ANNOUNCE",
    "DESCRIBE",
    "SETUP",
    "PLAY",
    "RECORD",
    "PAUSE",
    "TEARDOWN"
  ]

  @udp_port_range 1000..65_000//2

  defguardp can_play(state)
            when map_size(state.configured_media) != 0 and
                   state.session_state in [:ready, :paused]

  defguardp can_record(state)
            when map_size(state.incoming_media) != 0 and
                   state.session_state in [:ready, :paused]

  defmodule State do
    @moduledoc false
    @enforce_keys [:socket, :request_handler]
    defstruct @enforce_keys ++
                [
                  :rtp_socket,
                  :rtcp_socket,
                  :request_handler_state,
                  :session_timeout,
                  configured_media: %{},
                  incoming_media: %{},
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
            incoming_media: Server.Handler.configured_media_context(),
            session_id: binary(),
            session_state: :init | :ready | :playing | :recording | :paused,
            session_timeout: non_neg_integer()
          }
  end

  @spec allowed_methods() :: [binary()]
  def allowed_methods(), do: @allowed_methods

  @spec process_request(Request.t(), State.t()) :: State.t()
  def process_request(request, %State{} = state) do
    {response, state} = do_handle_request(request, state)
    response = maybe_add_cseq_header(response, request)

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
        state.request_handler.handle_setup(
          request,
          transport_opts[:mode],
          state.request_handler_state
        )

      {response, state} = do_handle_setup_response(request, response, transport_opts, state)
      {response, %{state | request_handler_state: request_handler_state}}
    else
      error ->
        Logger.error("SETUP request failed due to: #{inspect(error)}")
        {Response.new(400), %{state | request_handler_state: state.request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "PLAY"}, state) when can_play(state) do
    {response, request_handler_state} =
      state.request_handler.handle_play(state.configured_media, state.request_handler_state)

    response = inject_session_header(response, state)

    if Response.ok?(response) do
      {response, %{state | request_handler_state: request_handler_state, session_state: :playing}}
    else
      {response, %{state | request_handler_state: request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "PAUSE"}, %{session_state: :playing} = state) do
    {response, request_handler_state} =
      state.request_handler.handle_pause(state.request_handler_state)

    response = inject_session_header(response, state)

    if Response.ok?(response) do
      {response, %{state | request_handler_state: request_handler_state, session_state: :paused}}
    else
      {response, %{state | request_handler_state: request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "ANNOUNCE"} = req, state) do
    case ExSDP.parse(req.body) do
      {:ok, sdp} ->
        {response, request_handler_state} =
          state.request_handler.handle_announce(
            %Request{req | body: sdp},
            state.request_handler_state
          )

        {response, %{state | request_handler_state: request_handler_state}}

      error ->
        Logger.error("""
        ANNOUNCE request failed: could not parse the request body to a valid sdp
        error: #{inspect(error)}
        body: #{inspect(req.body, limit: :infinity)}
        """)

        {Response.new(400), state}
    end

    {Response.new(200), state}
  end

  defp do_handle_request(%Request{method: "RECORD"}, state) when can_record(state) do
    {response, handler_state} = state.request_handler.handle_record(state.incoming_media, state)
    {response, %{state | request_handler_state: handler_state, session_state: :recording}}
  end

  defp do_handle_request(%Request{method: "TEARDOWN"}, state)
       when state.session_state in [:init, :ready] do
    close_open_ports(state)

    Response.new(200)
    |> inject_session_header(state)
    |> then(&{&1, %{state | configured_media: %{}, incoming_media: %{}, session_state: :init}})
  end

  defp do_handle_request(%Request{method: "TEARDOWN"}, state) do
    {response, _handler_state} =
      state.request_handler.handle_teardown(state.request_handler_state)

    close_open_ports(state)

    response
    |> inject_session_header(state)
    |> then(&{&1, %{state | session_state: :init, configured_media: %{}, incoming_media: %{}}})
  end

  defp do_handle_request(%Request{}, state) do
    {Response.new(455), state}
  end

  # TODO: Add more validation for transport parameters
  defp validate_transport_parameters(transport_opts, state) do
    transport = transport_opts[:transport]

    cond do
      transport_opts[:network_mode] == :multicast ->
        {:error, :multicast_not_supported}

      transport_opts[:mode] == :record and transport != :UDP ->
        {:error, :unsupported_transport}

      transport_opts[:mode] == :play and transport == :UDP and is_nil(state.rtp_socket) ->
        {:error, :udp_not_supported}

      true ->
        :ok
    end
  end

  defp do_handle_setup_response(request, response, transport_opts, state) do
    response = inject_session_header(response, state)

    if Response.ok?(response) do
      track_config = build_track_config(transport_opts, state)

      state =
        case transport_opts[:mode] do
          :play ->
            %{
              state
              | configured_media: Map.put(state.configured_media, request.path, track_config)
            }

          :record ->
            %{state | incoming_media: Map.put(state.incoming_media, request.path, track_config)}
        end

      resp_transport_header = build_resp_transport_header(request, track_config)
      response = Response.with_header(response, "Transport", resp_transport_header)

      {response, %{state | session_state: :ready}}
    else
      {response, state}
    end
  end

  defp build_track_config(transport_opts, state) do
    case transport_opts[:mode] do
      :play -> build_play_track_config(transport_opts, state)
      :record -> build_record_track_config(transport_opts, state)
    end
  end

  defp build_play_track_config(transport_opts, state) do
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

  defp build_record_track_config(transport_opts, state) do
    case transport_opts[:transport] do
      :TCP ->
        %{
          transport: :TCP,
          tcp_socket: state.socket,
          channels: transport_opts[:parameters]["interleaved"]
        }

      :UDP ->
        case find_rtp_ports(0) do
          {rtp_socket, rtcp_socket} ->
            {:ok, {address, _port}} = :inet.peername(state.socket)

            %{
              transport: :UDP,
              rtp_socket: rtp_socket,
              rtcp_socket: rtcp_socket,
              address: address,
              client_port: transport_opts[:parameters]["client_port"]
            }

          :error ->
            {:error, :udp_port_failure}
        end
    end
  end

  defp find_rtp_ports(attempt) when attempt >= 100, do: :error

  defp find_rtp_ports(attempt) do
    rtp_port = Enum.random(@udp_port_range)

    case :gen_udp.open(rtp_port, [:binary, active: false]) do
      {:ok, rtp_socket} ->
        case :gen_udp.open(rtp_port + 1, [:binary, active: false]) do
          {:ok, rtcp_socket} ->
            {rtp_socket, rtcp_socket}

          _error ->
            :gen_udp.close(rtp_socket)
            find_rtp_ports(attempt + 1)
        end

      _error ->
        find_rtp_ports(attempt + 1)
    end
  end

  defp build_resp_transport_header(request, track_config) do
    {:ok, req_header} = Request.get_header(request, "Transport")

    resp_header =
      case track_config[:ssrc] do
        nil -> req_header
        ssrc -> req_header <> ";ssrc=#{Integer.to_string(ssrc, 16)}"
      end

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

  defp inject_session_header(response, state) do
    timeout_in_seconds = div(state.session_timeout, 1_000)

    Response.with_header(
      response,
      "Session",
      state.session_id <> ";timeout=#{timeout_in_seconds}"
    )
  end

  defp close_open_ports(%State{} = state) do
    state.incoming_media
    |> Map.values()
    |> Enum.filter(&(&1.transport == :UDP))
    |> Enum.each(fn in_media ->
      :ok = :inet.close(in_media.rtp_socket)
      :ok = :inet.close(in_media.rtcp_socket)
    end)
  end
end
