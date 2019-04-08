defmodule Membrane.Protocol.RTSP.Transport.TCPSocket do
  @moduledoc """
  This module implements the Transport behaviour and transmits requests over TCP
  Socket keeping connection until either session is closed or connection is
  closed by server.

  Supported options:
    * timeout - time after request will be deemed missing and error shall be
     returned.
  """
  use GenServer
  import Mockery.Macro

  @behaviour Membrane.Protocol.RTSP.Transport
  @default_timeout 5000
  @connection_timeout 1000

  defmodule State do
    @moduledoc false
    @enforce_keys [:connection_info, :connection_timeout]
    defstruct @enforce_keys ++ [:connection, :caller]

    @type t :: %__MODULE__{
            connection_info: URI.t(),
            connection: :gen_tcp.socket() | nil,
            caller: pid() | nil,
            connection_timeout: non_neg_integer()
          }
  end

  @impl true
  def execute(raw_request, executor, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(executor, {:execute, raw_request}, timeout)
  end

  @impl true
  def init(%{uri: %URI{} = connection_info, options: options}) do
    connection_timeout = Keyword.get(options, :connection_timeout, @connection_timeout)

    with {:ok, socket} <- open(connection_info, connection_timeout) do
      state = %State{
        connection_info: connection_info,
        connection: socket,
        connection_timeout: connection_timeout
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:execute, request}, caller, state) do
    case execute_request(request, state) do
      {:ok, state} ->
        {:noreply, %State{state | caller: caller}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:tcp, _socket, data}, %State{caller: caller} = state) do
    GenServer.reply(caller, {:ok, data})
    {:noreply, %State{state | caller: nil}}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:noreply, %State{state | connection: nil}}
  end

  defp open(%URI{host: host, port: port}, connection_timeout) do
    mockable(:gen_tcp).connect(
      to_charlist(host),
      port,
      [:binary, active: true],
      connection_timeout
    )
  end

  @spec execute_request(binary(), State.t()) :: {:ok, State.t()} | {:error, atom()}
  defp execute_request(request, %State{connection: nil} = state) do
    with {:ok, pid} <- open(state.connection_info, state.connection_timeout) do
      state = %State{state | connection: pid}
      execute_request(request, state)
    end
  end

  defp execute_request(request, %State{connection: conn} = state) do
    with :ok <- mockable(:gen_tcp).send(conn, request) do
      {:ok, state}
    end
  end
end
