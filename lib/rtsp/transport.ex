defmodule Membrane.Protocol.RTSP.Transport do
  use Bunch

  @callback execute(binary(), {:via, Registry, {TransportRegistry, binary()}}, [tuple()]) ::
              binary()

  @spec start_link(module(), binary(), URI.t()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(module, ref, connection_info) do
    GenServer.start_link(module, connection_info, name: transport_name(ref))
  end

  def transport_name(ref), do: {:via, Registry, {TransportRegistry, ref}}
end
