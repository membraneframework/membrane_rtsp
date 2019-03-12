defmodule Membrane.Protocol.RTSP.Session.Supervisor do
  use DynamicSupervisor
  alias Membrane.Protocol.RTSP.Session.CoupleSupervisor

  def start_link(), do: DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)

  def start_child(module, url, options \\ []) do
    spec = %{
      id: CoupleSupervisor,
      start: {CoupleSupervisor, :start_link, [module, url, options]}
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def terminate_child(pid), do: Supervisor.terminate_child(__MODULE__, pid)

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
