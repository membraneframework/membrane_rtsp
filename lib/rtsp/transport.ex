defmodule Membrane.Protocol.RTSP.Transport do
  use Bunch
  alias Membrane.Protocol.RTSP.Session.ConnectionInfo

  @callback execute(binary(), {:via, Registry, {TransportRegistry, binary()}}, [tuple()]) ::
              binary()

  @spec start_link(module(), binary(), ConnectionInfo.t()) ::
          :ignore | {:error, any()} | {:ok, pid()}
  def start_link(module, ref, connection_info) do
    GenServer.start_link(module, connection_info, name: {:via, Registry, {TransportRegistry, ref}})
  end
end
