defmodule Membrane.RTSP.Server do
  @moduledoc """
  Implementation of an RTSP server.

  ## Usage
  To use the RTSP server, you should start it and provide some configuration. Often in your supervision tree:
  ```
  children = [
    {Membrane.RTSP.Server, [port: 8554, handler: MyRequestHandler]}
  ]
  ```

  Or start it directly by calling `start_link/1` or `start/1`.

  ```
  {:ok, server} = Membrane.RTSP.Server.start_link(config)
  ```

  For the available configuration options refer to `start_link/1`
  """

  use GenServer

  alias __MODULE__

  @type server_config :: [
          name: term(),
          address: :inet.ip_address(),
          port: non_neg_integer(),
          handler: module(),
          udp_rtp_port: :inet.port_number(),
          udp_rtcp_port: :inet.port_number()
        ]

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

  ### Options
    - `port` - The port where the server will listen for connections. default to: `554`
    - `address` - Specify the address where the `tcp` and  `udp` sockets will be bind.
    - `handler` - An implementation of the behaviour `Membrane.RTSP.Server.Handler`. Refer to the module
    documentation for more details.
    - `udp_rtp_port` - The port number of the `UDP` socket that will be opened to send `RTP` packets.
    - `udp_rtcp_port` - The port number of the `UDP` socket that will be opened to send `RTCP` packets.

    Note that `udp_rtp_port` and `udp_rtcp_port` must be both provided, otherwise `UDP` transport is disabled
    for this server.
  """
  @spec start_link(server_config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config[:name])
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
      udp_rtp_socket: udp_rtp_socket,
      udp_rtcp_socket: udp_rtcp_socket,
      client_conns: []
    }

    parent_pid = self()
    Task.start_link(fn -> do_listen(socket, parent_pid) end)

    {:ok, state}
  end

  defp do_listen(socket, parent_pid) do
    case :gen_tcp.accept(socket) do
      {:ok, client_socket} ->
        send(parent_pid, {:new_connection, client_socket})
        do_listen(socket, parent_pid)

      {:error, reason} ->
        raise("error occurred when listening for client connections: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_info({:new_connection, client_socket}, state) do
    child_state =
      state
      |> Map.take([:handler, :udp_rtp_socket, :udp_rtcp_socket])
      |> Map.put(:socket, client_socket)

    case Server.Conn.start(child_state) do
      {:ok, conn_pid} ->
        Process.monitor(conn_pid)
        {:noreply, %{state | client_conns: [conn_pid | state.client_conns]}}

      _error ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, conn_pid, _reason}, state) do
    {:noreply, %{state | client_conns: List.delete(state.client_conns, conn_pid)}}
  end

  @impl true
  def handle_info(_unexpected_message, state) do
    {:noreply, state}
  end
end
