defmodule Membrane.RTSP.Server.Conn do
  @moduledoc """
  A module representing a client-server connection
  """

  use GenServer

  require Logger

  alias Membrane.RTSP.{Request, Response}

  @server "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Server)"
  @allowed_methods ["GET_PARAMETER", "OPTIONS", "DESCRIBE", "SETUP", "PLAY", "TEARDOWN"]

  @spec start(:inet.socket(), module()) :: GenServer.on_start()
  def start(socket, request_handler) do
    GenServer.start(__MODULE__, %{socket: socket, handler: request_handler})
  end

  @impl true
  def init(config) do
    state = %{
      socket: config.socket,
      handler: config.handler,
      handler_state: config.handler.init(),
      session_id: UUID.uuid4(),
      state: :preinit
    }

    {:ok, state, {:continue, :process_client_requests}}
  end

  @impl true
  def handle_continue(:process_client_requests, state) do
    do_process_client_requests(state)
    {:stop, :normal, state}
  end

  defp do_process_client_requests(state) do
    with request when is_binary(request) <- get_request(state.socket),
         {:ok, state} <- handle_request(request, state) do
      do_process_client_requests(state)
    else
      {:error, reason} ->
        Logger.error("error while reading client request: #{inspect(reason)}")

      {:halt, _state} ->
        Logger.info("The client halted the connection")
    end
  end

  defp get_request(socket, request \\ "") do
    case :gen_tcp.recv(socket, 0) do
      {:ok, packet} ->
        request = request <> packet
        if packet != "\r\n", do: get_request(socket, request), else: request

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_request(request, state) do
    {response, state, halt?} =
      case Request.parse(request) do
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

  defp do_handle_request(%Request{method: "OPTIONS"} = request, state) do
    state.handler.handle_options(state.handler_state, request)

    Response.new(200)
    |> Response.with_header("Public", Enum.join(@allowed_methods, ", "))
    |> then(&{&1, state})
  end

  defp do_handle_request(%Request{method: "GET_PARAMETER"}, state) do
    {Response.new(200), state}
  end

  defp do_handle_request(%Request{method: "DESCRIBE"} = request, state) do
    {response, handler_state} =
      case state.handler.handle_describe(state.handler_state, request) do
        {{:ok, description}, handler_state} ->
          response = Response.with_body(Response.new(200), to_string(description))

          if is_struct(description, ExSDP) do
            {Response.with_header(response, "Content-Type", "application/sdp"), handler_state}
          else
            {response, handler_state}
          end

        {error, handler_state} ->
          {map_error_to_response(error), handler_state}
      end

    {response, %{state | handler_state: handler_state}}
  end

  defp do_handle_request(%Request{method: "SETUP"} = request, state) do
    with {:ok, transport_opts} <- Request.parse_transport_header(request),
         :ok <- validate_transport_parameters(transport_opts),
         {{:ok, ssrc}, handler_state} <- state.handler.handle_setup(state.handler_state, request) do
      response =
        Response.new(200)
        |> Response.with_header("Session", state.session_id)
        |> Response.with_header("Transport", "RTP/AVP/TCP;unicast;interleaved=0-1;ssrc=#{ssrc}")

      {response, %{state | handler_state: handler_state}}
    else
      {:error, reason} ->
        Logger.error("error when handling SETUP request: #{inspect(reason)}")
        {Response.new(400), %{state | handler_state: state.handler_state}}

      {error, handler_state} ->
        Logger.error("error when handling SETUP request (handler module): #{inspect(error)}")
        {map_error_to_response(error), %{state | handler_state: handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "PLAY"}, state) do
    case state.handler.handle_play(state.handler_state, state.socket) do
      {:ok, handler_state} ->
        Response.new(200)
        |> Response.with_header("Session", state.session_id)
        |> then(&{&1, %{state | handler_state: handler_state}})

      {error, handler_state} ->
        Logger.error("error when handling PLAY request (handler module): #{inspect(error)}")
        {map_error_to_response(error), %{state | handler_state: handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "TEARDOWN"}, state) do
    state.handler.handle_teardown(state.handler_state)

    Response.new(200)
    |> Response.with_header("Session", state.session_id)
    |> then(&{&1, state})
  end

  defp do_handle_request(%Request{}, state) do
    {Response.new(405), state}
  end

  defp validate_transport_parameters(transport_opts) do
    cond do
      transport_opts[:transport] == :UDP -> {:error, :udp_not_supported}
      transport_opts[:mode] == :multicast -> {:error, :multicast_not_supported}
      true -> :ok
    end
  end

  defp maybe_add_cseq_header(response, request) do
    case Request.get_header(request, "CSeq") do
      {:ok, value} -> Response.with_header(response, "CSeq", value)
      {:error, _no_such_header} -> response
    end
  end

  defp map_error_to_response({:error, :unauthorizd}), do: Response.new(401)
  defp map_error_to_response({:error, :forbidden}), do: Response.new(403)
  defp map_error_to_response({:error, :not_found}), do: Response.new(404)
  defp map_error_to_response({:error, _other}), do: Response.new(400)
end
