defmodule Membrane.Protocol.RTSP.Transport.Fake do
  use GenServer

  @impl true
  def init(connection_info) do
    {:ok, connection_info}
  end

  @impl true
  def handle_info(:crash_me, state) do
    raise "you asked for it"
  end
end
