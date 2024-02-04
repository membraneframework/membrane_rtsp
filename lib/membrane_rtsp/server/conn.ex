defmodule Membrane.RTSP.Server.Conn do
  @moduledoc """
  A module representing a client-server connection
  """

  use GenServer

  import Membrane.RTSP.Server.Logic

  require Logger

  alias Membrane.RTSP.Server.Logic.State

  @max_request_size 1_000_000

  @spec start(map()) :: GenServer.on_start()
  def start(state) do
    GenServer.start(__MODULE__, state)
  end

  @impl true
  def init(config) do
    state = %State{
      socket: config.socket,
      request_handler: config.handler,
      request_handler_state: config.handler.handle_open_connection(config.socket),
      rtp_socket: config.udp_rtp_socket,
      rtcp_socket: config.udp_rtcp_socket
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
    end
  end

  defp get_request(socket, request \\ "") do
    with {:ok, packet} <- :gen_tcp.recv(socket, 0),
         request <- request <> packet,
         false <- byte_size(request) > @max_request_size do
      if packet != "\r\n", do: get_request(socket, request), else: request
    else
      {:error, reason} -> {:error, reason}
      true -> {:error, :max_request_size_exceeded}
    end
  end
end
