defmodule Membrane.RTSP.Server.Conn do
  @moduledoc """
  A module representing a client-server connection
  """

  use GenServer

  import Membrane.RTSP.Server.Logic

  require Logger

  alias Membrane.RTSP.Server.Logic.State

  @spec start(:inet.socket(), module()) :: GenServer.on_start()
  def start(socket, request_handler) do
    GenServer.start(__MODULE__, %{socket: socket, handler: request_handler})
  end

  @impl true
  def init(config) do
    state = %State{
      socket: config.socket,
      request_handler: config.handler,
      request_handler_state: config.handler.init()
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
         {:ok, state} <- process_request(request, state) do
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
end
