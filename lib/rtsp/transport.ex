defmodule Membrane.Protocol.RTSP.Transport do
  use Bunch

  @type transport_ref :: {:via, Registry, {TransportRegistry, binary()}}

  @callback execute(binary(), transport_ref, [tuple()]) :: {:ok, binary()} | {:error, atom()}

  @spec start_link(module(), binary(), URI.t()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(module, ref, connection_info) do
    GenServer.start_link(module, connection_info, name: transport_name(ref))
  end

  @spec transport_name(binary()) :: transport_ref
  def transport_name(ref), do: {:via, Registry, {TransportRegistry, ref}}
end
