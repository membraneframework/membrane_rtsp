defmodule Membrane.Protocol.RTSP.Transport do
  @moduledoc """
  This module represents the Transport contract.
  """
  use Bunch

  @type transport_ref :: {:via, Registry, {TransportRegistry, binary()}}

  @doc """
  Invoked by session process when executing requests.
  """
  @callback execute(request :: binary(), transport_ref, options :: [tuple()]) ::
              {:ok, binary()} | {:error, atom()}

  @doc """
  Starts and links Transport process.

  The transport process is immediately registered in the TransportRegistry via
  `Registry`.
  """
  @spec start_link(module(), binary(), URI.t()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(module, ref, connection_info) do
    GenServer.start_link(module, connection_info, name: transport_name(ref))
  end

  @spec transport_name(binary()) :: transport_ref
  def transport_name(ref), do: {:via, Registry, {TransportRegistry, ref}}
end
