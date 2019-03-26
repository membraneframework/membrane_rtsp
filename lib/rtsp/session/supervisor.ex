defmodule Membrane.Protocol.RTSP.Session.Supervisor do
  @moduledoc false
  use DynamicSupervisor
  alias Membrane.Protocol.RTSP.Session.CoupleSupervisor

  @spec start_link() :: Supervisor.on_start()
  def start_link, do: DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @spec start_child(module(), binary(), Keyword.t()) :: DynamicSupervisor.on_start_child()
  def start_child(module, url, options \\ []) do
    spec = %{
      id: CoupleSupervisor,
      start: {CoupleSupervisor, :start_link, [module, url, options]}
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @spec terminate_child(any()) :: :ok | {:error, :not_found | :simple_one_for_one}
  def terminate_child(pid), do: Supervisor.terminate_child(__MODULE__, pid)

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
