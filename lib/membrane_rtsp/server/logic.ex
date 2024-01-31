defmodule Membrane.RTSP.Server.Logic do
  @moduledoc """
  Logic for RTSP Server
  """

  require Logger

  alias Membrane.RTSP.{Request, Response}

  @server "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Server)"
  @allowed_methods ["GET_PARAMETER", "OPTIONS", "DESCRIBE", "SETUP", "PLAY", "TEARDOWN"]

  defmodule State do
    @moduledoc "Struct representing the state of a server connection"
    @enforce_keys [:socket, :request_handler]
    defstruct @enforce_keys ++ [:request_handler_state, session_id: UUID.uuid4(), phase: :init]

    @type t :: %__MODULE__{
            socket: :inet.socket(),
            request_handler: module(),
            request_handler_state: term(),
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

  defp do_handle_request(%Request{method: "OPTIONS"} = request, state) do
    state.request_handler.handle_options(state.request_handler_state, request)

    Response.new(200)
    |> Response.with_header("Public", Enum.join(@allowed_methods, ", "))
    |> then(&{&1, state})
  end

  defp do_handle_request(%Request{method: "GET_PARAMETER"}, state) do
    {Response.new(200), state}
  end

  defp do_handle_request(%Request{method: "DESCRIBE"} = request, state) do
    {response, request_handler_state} =
      case state.request_handler.handle_describe(state.request_handler_state, request) do
        {{:ok, description}, request_handler_state} ->
          response = Response.with_body(Response.new(200), to_string(description))

          if is_struct(description, ExSDP) do
            {Response.with_header(response, "Content-Type", "application/sdp"),
             request_handler_state}
          else
            {response, request_handler_state}
          end

        {error, request_handler_state} ->
          {map_error_to_response(error), request_handler_state}
      end

    {response, %{state | request_handler_state: request_handler_state}}
  end

  defp do_handle_request(%Request{method: "SETUP"} = request, state)
       when state.phase != :playing do
    with {:ok, transport_opts} <- Request.parse_transport_header(request),
         :ok <- validate_transport_parameters(transport_opts),
         {{:ok, ssrc}, request_handler_state} <-
           state.request_handler.handle_setup(state.request_handler_state, request) do
      response =
        Response.new(200)
        |> Response.with_header("Session", state.session_id)
        |> Response.with_header(
          "Transport",
          "RTP/AVP/TCP;unicast;interleaved=0-1;ssrc=#{Base.encode16(<<ssrc::32>>)}"
        )

      {response, %{state | request_handler_state: request_handler_state, phase: :setup}}
    else
      {:error, reason} ->
        Logger.error("error when handling SETUP request: #{inspect(reason)}")
        {Response.new(400), %{state | request_handler_state: state.request_handler_state}}

      {error, request_handler_state} ->
        Logger.error("error when handling SETUP request (handler module): #{inspect(error)}")
        {map_error_to_response(error), %{state | request_handler_state: request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "PLAY"}, %{phase: :setup} = state) do
    case state.request_handler.handle_play(state.request_handler_state, state.socket) do
      {:ok, request_handler_state} ->
        Response.new(200)
        |> Response.with_header("Session", state.session_id)
        |> then(&{&1, %{state | request_handler_state: request_handler_state, phase: :playing}})

      {error, request_handler_state} ->
        Logger.error("error when handling PLAY request (handler module): #{inspect(error)}")

        {map_error_to_response(error), %{state | request_handler_state: request_handler_state}}
    end
  end

  defp do_handle_request(%Request{method: "TEARDOWN"}, %{phase: :playing} = state) do
    state.request_handler.handle_teardown(state.request_handler_state)

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
