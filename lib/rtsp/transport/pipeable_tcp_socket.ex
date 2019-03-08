defmodule Membrane.Protocol.RTSP.Transport.PipeableTCPSocket do
  use Bunch
  use GenServer
  import Mockery.Macro

  @behaviour Membrane.Protocol.RTSP.Transport

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
  def execute(raw_request, executor, opts \\ [timeout: 5000]) do
    timeout = Keyword.fetch!(opts, :timeout)
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
    # TODO check wether it is working
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
  def terminate(_reason, %State{connection: connection}) do
    :gen_tcp.close(connection)
  end

  @spec execute_request(binary(), State.t()) :: {:ok, State.t()} | {:error, atom()}
  defp execute_request(request, %State{connection: nil, connection_info: connection_info} = state) do
    case open(connection_info) do
      {:ok, pid} ->
        state = %State{state | connection: pid}
        execute_request(request, state)

      # TODO Handle this somewhere
      {:error, _cause} = error ->
        error
    end
  end

  defp execute_request(request, %State{connection: conn} = state) do
    mockable(:gen_tcp).send(conn, request)
    ~>> (:ok -> {:ok, state})
  end
end
