defmodule Membrane.RTSP.Server do
  @moduledoc """
  Implementation of an RTSP server.

  To start a new server
  ```
  {:ok, server} = Membrane.RTSP.Server.start_link(config)
  ```

  The `start_link/1` accepts a keyword list configuration:
    - `port` - The port where the server will listen for connections. default to: `554`
    - `handler` - An implementation of the behaviour `Membrane.RTSP.Server.Handler`. Refer to the module
    documentation for more details.
  """

  use GenServer

  require Logger

  alias __MODULE__

  @type server_config :: [
          name: term(),
          port: non_neg_integer(),
          handler: module()
        ]

  @spec start_link(server_config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config[:name])
  end

  @impl true
  def init(config) do
    port = Keyword.get(config, :port, 554)

    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    parent_pid = self()
    Task.start_link(fn -> do_listen(socket, parent_pid) end)

    {:ok, %{socket: socket, conns: [], handler: config[:handler]}}
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
