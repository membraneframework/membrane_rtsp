defmodule Membrane.Protocol.RTSP.Transport.PipeableTCPSocket do
  @moduledoc """
  This module implements Transport behaviour and transmits requests
  over TCP Socket keeping connection until either session is closed
  or connection is closed by server.

  Supported options:
    * timeout - time after request will be deemed missing and error
    shall be returned.
  """
  use GenServer
  import Mockery.Macro

  @behaviour Membrane.Protocol.RTSP.Transport
  @default_timeout 5000

  defmodule State do
    @enforce_keys [:queue, :connection_info]
    defstruct @enforce_keys ++ [:connection]

    @type t :: %__MODULE__{
            connection_info: URI.t(),
            connection: :gen_tcp.socket() | nil,
            queue: Qex.t(pid())
          }
  end

  @impl true
  def execute(raw_request, executor, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(executor, {:execute, raw_request}, timeout)
  end

  @impl true
  def init(%URI{} = connection_info) do
    state = %State{
      connection_info: connection_info,
      connection: nil,
      queue: Qex.new()
    }

    {:ok, state}
  end

  @spec open(URI.t()) :: {:error, atom()} | {:ok, :gen_tcp.socket()}
  defp open(%URI{host: host, port: port}) do
    mockable(:gen_tcp).connect(to_charlist(host), port, [:binary, {:active, true}])
  end

  @impl true
  def handle_call({:execute, request}, caller, %State{queue: queue} = state) do
    case execute_request(request, state) do
      {:ok, state} ->
        state = %State{state | queue: Qex.push(queue, caller)}
        {:noreply, state}

      # TODO: Handle error properly
      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:tcp, _socket, data}, %State{queue: queue} = state) do
    {sender, queue} = Qex.pop_back!(queue)
    GenServer.reply(sender, {:ok, data})
    {:noreply, %State{state | queue: queue}}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:noreply, %State{state | connection: nil}}
  end

  @impl true
  def terminate(reason, state)
  def terminate(_, %State{connection: nil}), do: :ok
  def terminate(_, %State{connection: connection}), do: mockable(:gen_tcp).close(connection)

  @spec execute_request(binary(), State.t()) :: {:ok, State.t()} | {:error, atom()}
  defp execute_request(request, %State{connection: nil, connection_info: connection_info} = state) do
    with {:ok, pid} <- open(connection_info) do
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
