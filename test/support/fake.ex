defmodule Membrane.Protocol.RTSP.Transport.Fake do
  @moduledoc false
  use GenServer
  import Mockery.Macro

  @behaviour Membrane.Protocol.RTSP.Transport
  @response "RTSP/1.0 200 OK\r\n"

  @impl true
  def execute(request, ref, options) do
    mockable(__MODULE__).proxy(request, ref)
    resolver = Keyword.get(options, :resolver, &__MODULE__.default_resolver/1)
    resolver.(request)
  end

  def default_resolver(request) do
    [_, rest] = String.split(request, "\r\n", parts: 2)
    {:ok, @response <> rest}
  end

  @impl true
  def init(connection_info) do
    {:ok, connection_info}
  end

  def proxy(_request, _ref), do: nil
end
