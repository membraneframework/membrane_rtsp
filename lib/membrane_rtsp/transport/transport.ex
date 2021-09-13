defmodule Membrane.RTSP.Transport do
  @moduledoc """
  Behaviour describing Transport Layer for RealTime Streaming Protocol
  """

  @callback init(url :: URI.t(), options :: Keyword.t()) ::
              {:ok, any()} | {:error, any()}

  @callback handle_info(msg :: any(), state :: any()) ::
              {action :: term(), state :: any()}
              | {action :: term(), reply :: any(), state :: any()}

  @callback execute(request :: any(), state :: any(), options :: Keyword.t()) ::
              {:ok, reply :: any()} | {:error, reason :: any()}

  @callback close(state :: any()) :: :ok

  @optional_callbacks handle_info: 2, close: 1

  defmacro __using__(_block) do
    quote do
      @behaviour Membrane.RTSP.Transport

      @impl Membrane.RTSP.Transport
      def close(_state), do: :ok

      @impl Membrane.RTSP.Transport
      def handle_info(_msg, _state), do: raise("handle_info/2 has not been implemented")

      defoverridable close: 1, handle_info: 2
    end
  end

  @spec new(module(), binary() | URI.t(), Keyword.t()) :: {:ok, any()} | {:error, any()}
  @deprecated "Use init/3 instead. It is not recommended to manually initiate transport"
  def new(module, url, options \\ []), do: module.init(url, options)
end
