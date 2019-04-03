defmodule Membrane.Protocol.RTSP.Transport do
  @moduledoc """
  This module represents the Transport contract.
  """
  use Bunch
  defstruct [:module, :key]

  @type transport_ref :: {:via, Registry, {TransportRegistry, binary()}}
  @type t :: %__MODULE__{
          module: module(),
          key: transport_ref
        }

  @spec new(module(), binary()) :: Membrane.Protocol.RTSP.Transport.t()
  def new(module, key) do
    %__MODULE__{
      module: module,
      key: {:via, Registry, {TransportRegistry, key}}
    }
  end

  @doc """
  Invoked by session process when executing requests.
  """
  @callback execute(request :: binary(), transport_ref, options :: [Keyword.t()]) ::
              {:ok, binary()} | {:error, atom()}

  @doc """
  Starts and links Transport process.

  The transport process is immediately registered in the TransportRegistry via
  `Registry`.
  """
  @spec start_link(t(), URI.t()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(transport, connection_info) do
    GenServer.start_link(transport.module, connection_info, name: transport.key)
  end
end
