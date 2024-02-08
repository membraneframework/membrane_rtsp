defmodule Membrane.RTSP.Server.Conn do
  @moduledoc """
  A module representing a client-server connection
  """

  use GenServer

  require Logger

  alias Membrane.RTSP.Server.Logic

  @max_request_size 1_000_000

  @spec start(map()) :: GenServer.on_start()
  def start(state) do
    GenServer.start(__MODULE__, state)
  end

  @impl true
  def init(config) do
    state = %Logic.State{
      socket: config.socket,
      request_handler: config.handler,
      request_handler_state: config.handler.handle_open_connection(config.socket),
      rtp_socket: config.udp_rtp_socket,
      rtcp_socket: config.udp_rtcp_socket,
      session_timeout: config.session_timeout
    }

    {:ok, state, {:continue, :process_client_requests}}
  end

  @impl true
  def handle_continue(:process_client_requests, state) do
    do_process_client_requests(state)
    state.request_handler.handle_closed_connection(state.request_handler_state)
    {:stop, :normal, state}
  end

  defp do_process_client_requests(state) do
    with {:ok, request} <- get_request(state.socket, state.session_timeout) do
      request
      |> Logic.process_request(state)
      |> do_process_client_requests()
    end
  end

  defp get_request(socket, timeout, request \\ "") do
    with {:ok, packet} <- :gen_tcp.recv(socket, 0, timeout),
         request <- request <> packet,
         false <- byte_size(request) > @max_request_size do
      if packet != "\r\n", do: get_request(socket, timeout, request), else: {:ok, request}
    else
      {:error, reason} -> {:error, reason}
      true -> {:error, :max_request_size_exceeded}
    end
  end
end
