defmodule Membrane.Protocol.RTSP.Transport do
  @moduledoc """
  s
  """
  use Bunch

  @type transport_ref :: {:via, Registry, {TransportRegistry, binary()}}

  @doc """
  Synchronously executes given serialized request via transport process and returns
  an `{:ok, result}` tuple with raw response or `{:error, reason}` tuple.
  """
  @callback execute(request :: binary(), transport_ref, options :: [tuple()]) ::
              {:ok, binary()} | {:error, atom()}

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, args}
    }
  end

  @spec start_link(module(), binary(), URI.t()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(module, ref, connection_info) do
    GenServer.start_link(module, connection_info, name: transport_name(ref))
  end

  @spec transport_name(binary()) :: transport_ref
  def transport_name(ref), do: {:via, Registry, {TransportRegistry, ref}}
end
