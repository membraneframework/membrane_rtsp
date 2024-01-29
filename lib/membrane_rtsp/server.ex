defmodule Membrane.RTSP.Server do
  @moduledoc """
  A module representing an RTSP server.
  """

  use GenServer

  require Logger

  alias __MODULE__

  @spec start_link(non_neg_integer(), module()) :: GenServer.on_start()
  def start_link(port, handler) do
    GenServer.start_link(__MODULE__, %{port: port, handler: handler}, name: __MODULE__)
  end

  @impl true
  def init(config) do
    {:ok, socket} =
      :gen_tcp.listen(config.port, [:binary, packet: :line, active: false, reuseaddr: true])

    parent_pid = self()
    Task.start_link(fn -> do_listen(socket, parent_pid) end)

    {:ok, %{socket: socket, conns: [], handler: config.handler}}
  end

  defp do_listen(socket, parent_pid) do
    case :gen_tcp.accept(socket) do
      {:ok, client_socket} ->
        Logger.info("New client connection")
        send(parent_pid, {:new_connection, client_socket})
        do_listen(socket, parent_pid)

      {:error, reason} ->
        raise("error occurred when listening for client connections: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_info({:new_connection, client_socket}, state) do
    {:ok, conn_pid} = Server.Conn.start(client_socket, state.handler)
    Process.monitor(conn_pid)

    {:noreply, %{state | conns: [conn_pid | state.conns]}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, conn_pid, _reason}, state) do
    Logger.info("Connection lost to client: #{inspect(conn_pid)}")
    {:noreply, %{state | conns: List.delete(state.conns, conn_pid)}}
  end

  @impl true
  def handle_info(_unexpected_message, state) do
    {:noreply, state}
  end
end
