defmodule Membrane.Protocol.RTSP.Transport.Supervisor do
  use DynamicSupervisor
  alias Membrane.Protocol.RTSP.Transport

  def start_link(), do: DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)

  def start_child(module, ref, conn_info) do
    spec = %{
      id: TransportWorker,
      start: {Transport, :start_link, [module, ref, conn_info]}
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def terminate_child(pid), do: Supervisor.terminate_child(__MODULE__, pid)

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
