defmodule Membrane.RTSP.Server do
  @moduledoc """
  Implementation of an RTSP server.

  ## Usage
  To use the RTSP server, you should start it and provide some configuration. To start a new server
  under a supervision tree:
  ```
  children = [
    {Membrane.RTSP.Server, [port: 8554, handler: MyRequestHandler]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
  ```

  Or start it directly by calling `start_link/1` or `start/1`.

  ```
  {:ok, server} = Membrane.RTSP.Server.start_link(config)
  ```

  For the available configuration options refer to `start_link/1`
  """

  use GenServer

  require Logger

  alias __MODULE__.Conn

  @type server_option ::
          {:handler, module()}
          | {:handler_config, term()}
          | {:name, term()}
          | {:port, :inet.port_number()}
          | {:address, :inet.ip_address()}
          | {:udp_rtp_port, :inet.port_number()}
          | {:udp_rtcp_port, :inet.port_number()}
          | {:session_timeout, non_neg_integer()}
  @type server_config :: [server_option()]

  @doc """
  Start an instance of the RTSP server.

  Refer to `start_link/1` for the available configuration.
  """
  @spec start(server_config()) :: GenServer.on_start()
  def start(config) do
    GenServer.start(__MODULE__, config, name: config[:name])
  end

  @doc """
  Start and link an instance of the RTSP server.

  ## Options
    - `handler` - An implementation of the behaviour `Membrane.RTSP.Server.Handler`. Refer to the module
    documentation for more details. This field is required.
    - `handler_config` - Term that will be passed as an argument to `init/1` callback of the handler. Defaults to `nil`.
    - `name` - Used for name registration of the server. Defaults to `nil`.
    - `port` - The port where the server will listen for client connections. Defaults to: `554`
    - `address` - Specify the address where the `tcp` and `udp` sockets will be bound. Defaults to `:any`.
    - `udp_rtp_port` - The port number of the `UDP` socket that will be opened to send `RTP` packets.
    - `udp_rtcp_port` - The port number of the `UDP` socket that will be opened to send `RTCP` packets.
    - `session_timeout` - if the server does not receive any request from the client within the specified
      timeframe (in seconds), the connection will be closed. Defaults to 60 seconds.

    > #### `Server UDP support` {: .warning}
    >
    > Both `udp_rtp_port` and `udp_rtcp_port` must be provided for the server
    > to support `UDP` transport.
  """
  @spec start_link(server_config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config[:name])
  end

  @doc """
  Stops the RTSP server.

  ## Options
    - `timeout` - timeout of the server termination, passed to `GenServer.stop/3`.
  """
  @spec stop(pid(), timeout: timeout()) :: :ok
  def stop(server, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    GenServer.stop(server, :normal, timeout)
  end

  @doc """
  Get the port number of the server.

  If the server started with port number 0, the os will choose an available port to
  assign to the server.
  """
  @spec port_number(pid() | GenServer.name()) :: {:ok, :inet.port_number()} | {:error, any()}
  def port_number(server) do
    GenServer.call(server, :port_number)
  end

  @doc """
  In interleaved TCP mode we want to pass control over the client connection socket to the pipeline (usually).

  This function allows to transfer the control over such socket to a specified process.
  """
  @spec transfer_client_socket_control(
          server_pid :: pid() | GenServer.name(),
          client_conn_pid :: pid(),
          new_controlling_process_pid :: pid()
        ) :: :ok | {:error, :unknown_conn | :closed | :not_owner | :badarg | :inet.posix()}
  def transfer_client_socket_control(server, conn_pid, new_controlling_process) do
    GenServer.call(server, {:transfer_client_socket_control, conn_pid, new_controlling_process})
  end

  @impl true
  def init(config) do
    address = config[:address] || :any

    {:ok, socket} =
      :gen_tcp.listen(config[:port] || 554, [
        :binary,
        packet: :line,
        ip: address,
        active: false,
        reuseaddr: true
      ])

    {:ok, port} = :inet.port(socket)
    Logger.info("RTSP server listening on port #{port}")

    udp_rtp_port = config[:udp_rtp_port]
    udp_rtcp_port = config[:udp_rtcp_port]

    {udp_rtp_socket, udp_rtcp_socket} =
      if udp_rtp_port && udp_rtcp_port do
        {:ok, udp_rtp_socket} =
          :gen_udp.open(udp_rtp_port, [:binary, ip: address, reuseaddr: true, active: false])

        {:ok, udp_rtcp_socket} =
          :gen_udp.open(udp_rtcp_port, [:binary, ip: address, reuseaddr: true, active: false])

        {udp_rtp_socket, udp_rtcp_socket}
      else
        {nil, nil}
      end

    state = %{
      socket: socket,
      handler: config[:handler],
      handler_state: config[:handler].init(config[:handler_config]),
      udp_rtp_socket: udp_rtp_socket,
      udp_rtcp_socket: udp_rtcp_socket,
      client_conns: %{},
      session_timeout: (config[:session_timeout] || 60) |> :timer.seconds()
    }

    server_pid = self()
    spawn_link(fn -> do_listen(socket, server_pid) end)

    {:ok, state}
  end

  @impl true
  def handle_call(:port_number, _from, state) do
    {:reply, :inet.port(state.socket), state}
  end

  @impl true
  def handle_call(
        {:transfer_client_socket_control, conn_pid, new_controlling_process},
        _from,
        state
      ) do
    case Map.fetch(state.client_conns, conn_pid) do
      {:ok, socket} ->
        {:reply, :gen_tcp.controlling_process(socket, new_controlling_process), state}

      :error ->
        {:reply, {:error, :unknown_conn}, state}
    end
  end

  @impl true
  def handle_info({:new_connection, client_socket}, state) do
    child_state =
      state
      |> Map.take([:handler, :handler_state, :session_timeout, :udp_rtp_socket, :udp_rtcp_socket])
      |> Map.put(:socket, client_socket)

    case Conn.start(child_state) do
      {:ok, conn_pid} ->
        Process.monitor(conn_pid)
        client_conns = Map.put(state.client_conns, conn_pid, client_socket)
        {:noreply, %{state | client_conns: client_conns}}

      {:error, reason} ->
        Logger.error("""
        Could not start client connection handling
        Reason: #{inspect(reason)}
        """)

        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, conn_pid, _reason}, state) do
    {socket, client_conns} = Map.pop(state.client_conns, conn_pid)
    if socket, do: :inet.close(socket)
    {:noreply, %{state | client_conns: client_conns}}
  end

  @impl true
  def handle_info(unexpected_message, state) do
    Logger.warning("received unexpected message: #{inspect(unexpected_message)}")
    {:noreply, state}
  end

  @spec do_listen(:gen_tcp.socket(), pid()) :: :ok
  defp do_listen(socket, parent_pid) do
    case :gen_tcp.accept(socket) do
      {:ok, client_socket} ->
        :ok = :gen_tcp.controlling_process(client_socket, parent_pid)
        send(parent_pid, {:new_connection, client_socket})
        do_listen(socket, parent_pid)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        raise("error occurred when accepting client connection: #{inspect(reason)}")
    end
  end
end
