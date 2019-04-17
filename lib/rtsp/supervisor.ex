defmodule Membrane.Protocol.RTSP.Supervisor do
  @moduledoc """

  """
  use DynamicSupervisor
  alias Membrane.Protocol.RTSP.Session

  @spec start_link() :: Supervisor.on_start()
  def start_link do
    DynamicSupervisor.start_link(__MODULE__, nil)
  end

  @spec start_child(pid(), module(), binary(), Keyword.t()) :: DynamicSupervisor.on_start_child()
  def start_child(supervisor, module, url, options \\ []) do
    spec = %{
      id: Session.Container,
      start: {Session.Container, :start_link, [module, url, options]}
    }

    DynamicSupervisor.start_child(supervisor, spec)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
