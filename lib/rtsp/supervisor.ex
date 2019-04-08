defmodule Membrane.Protocol.RTSP.Supervisor do
  @moduledoc false
  use DynamicSupervisor
  alias Membrane.Protocol.RTSP.Session

  @spec start_link() :: Supervisor.on_start()
  def start_link do
    DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @spec start_child(module(), binary(), Keyword.t()) :: DynamicSupervisor.on_start_child()
  def start_child(module, url, options \\ []) do
    spec = %{
      id: Session.Container,
      start: {Session.Container, :start_link, [module, url, options]}
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @spec terminate_child(any()) :: :ok | {:error, :not_found}
  def terminate_child(pid), do: DynamicSupervisor.terminate_child(__MODULE__, pid)

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
