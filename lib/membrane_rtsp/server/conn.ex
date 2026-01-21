defmodule Membrane.RTSP.Server.Conn do
  @moduledoc false
  use GenServer

  require Logger

  alias Membrane.RTSP.Request
  alias Membrane.RTSP.Server.Logic

  @spec start(map()) :: GenServer.on_start()
  def start(state) do
    GenServer.start(__MODULE__, state)
  end

  @impl true
  def init(config) do
    state = %Logic.State{
      socket: config.socket,
      request_handler: config.handler,
      request_handler_state:
        config.handler.handle_open_connection(config.socket, config.handler_state),
      rtp_socket: config.udp_rtp_socket,
      rtcp_socket: config.udp_rtcp_socket,
      session_timeout: config.session_timeout
    }

    {:ok, state, {:continue, :process_client_requests}}
  end

  @impl true
  def handle_continue(:process_client_requests, state) do
    case do_process_client_requests(state, state.session_timeout) do
      %Logic.State{recording_with_tcp?: true} = state ->
        {:noreply, state}

      {:error, _reason, state} ->
        state.request_handler.handle_closed_connection(state.request_handler_state)
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:rtsp, raw_rtsp_request}, state) do
    with {:ok, request} <- Request.parse(raw_rtsp_request) do
      case Logic.process_request(request, state) do
        %Logic.State{recording_with_tcp?: true} = state ->
          {:noreply, state}

        state ->
          handle_continue(:process_client_requests, state)
      end
    else
      {:error, error} ->
        raise "Failed to parse RTSP request: #{inspect(error)}.\nRequest: #{inspect(raw_rtsp_request)}"
    end
  end

  defp do_process_client_requests(state, timeout) do
    case get_request(state.socket, timeout) do
      {:ok, request} ->
        case Logic.process_request(request, state) do
          %Logic.State{recording_with_tcp?: true} = state ->
            state

          %Logic.State{session_state: :recording} = state ->
            do_process_client_requests(state, :infinity)

          state ->
            do_process_client_requests(state, state.session_timeout)
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp get_request(socket, timeout, acc \\ "") do
    with {:ok, acc} <- do_recv(socket, timeout, acc) do
      headers_and_body = String.split(acc, ~r/\r?\n\r?\n/, parts: 2)

      case do_parse_request(headers_and_body) do
        :more -> get_request(socket, timeout, acc)
        other -> other
      end
    end
  end

  defp do_recv(socket, timeout, acc) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} -> {:ok, acc <> data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_parse_request([raw_request, body]) do
    case Request.parse(raw_request <> "\r\n\r\n") do
      {:ok, %Request{} = request} ->
        content_length =
          case Request.get_header(request, "Content-Length") do
            {:ok, value} -> String.to_integer(value)
            _error -> 0
          end

        case byte_size(body) >= content_length do
          true -> {:ok, %Request{request | body: :binary.part(body, 0, content_length)}}
          false -> :more
        end

      _error ->
        {:error, :invalid_request}
    end
  end

  defp do_parse_request(_raw_request), do: :more
end
