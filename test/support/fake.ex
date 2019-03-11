defmodule Membrane.Protocol.RTSP.Transport.Fake do
  @moduledoc false
  use GenServer
  import Mockery.Macro

  @behaviour Membrane.Protocol.RTSP.Transport
  @response "RTSP/1.0 200 OK\r\n"

  @impl true
  def execute(request, ref, _options \\ []) do
    mockable(__MODULE__).proxy(request, ref)

    [_, rest] = String.split(request, "\r\n", parts: 2)
    {:ok, @response <> rest}
  end

  @impl true
  def init(connection_info) do
    {:ok, connection_info}
  end

  @impl true
  def handle_info(:crash_me, state) do
    raise "you asked for it"
  end

  def proxy(_request, _ref), do: nil
end
