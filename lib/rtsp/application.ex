defmodule Membrane.Protocol.RTSP.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      %{
        id: TransportRegistry,
        start: {Registry, :start_link, [:unique, TransportRegistry]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
