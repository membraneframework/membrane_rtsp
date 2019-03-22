defmodule Membrane.Protocol.RTSP.Application do
  @moduledoc false
  use Application

  alias Membrane.Protocol.RTSP.Session

  def start(_type, _args) do
    children = [
      %{
        id: TransportRegistry,
        start: {Registry, :start_link, [:unique, TransportRegistry]}
      },
      %{
        id: Session.Supervisor,
        start: {Session.Supervisor, :start_link, []}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
