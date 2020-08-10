defmodule Membrane.RTSP.Transport do
  @moduledoc """
  This module represents the Transport contract.

  Struct contains module that will be used when executing request and reference
  used for resolving transport process.
  """
  use Bunch
  @enforce_keys [:module, :key]
  defstruct @enforce_keys

  @type transport_ref :: {:via, Registry, {TransportRegistry, reference()}}
  @type t :: %__MODULE__{
          module: module(),
          key: transport_ref
        }

  @spec new(module(), reference()) :: Membrane.RTSP.Transport.t()
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
  def start_link(transport, connection_info, options \\ []) do
    args = %{
      uri: connection_info,
      options: options
    }

    GenServer.start_link(transport.module, args, name: transport.key)
  end
end
