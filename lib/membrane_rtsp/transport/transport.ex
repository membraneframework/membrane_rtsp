defmodule Membrane.RTSP.Transport do
  @moduledoc """
  Behaviour describing Transport Layer for Real Time Streaming Protocol
  """

  @doc """
  Callback for initialization of transport layer implementation.

  Upon successful initialization, the callback should return {:ok, state}.
  Value of state can be anything, but it is recommended that it contains some information that identifies a transport layer instance.
  """
  @callback init(url :: URI.t(), options :: Keyword.t()) ::
              {:ok, any()} | {:error, any()}

  @doc """
  Callback for handling any transport-layer specific messages. Session will redirect any unknown messages to this callback.

  It is useful for eg. correctly handling :tcp_close message and similar.
  """
  @callback handle_info(msg :: any(), state :: any()) ::
              {action :: term(), state :: any()}
              | {action :: term(), reply :: any(), state :: any()}

  @doc """
  Callback for executing requests with a given transport layer.
  """
  @callback execute(request :: any(), state :: any(), options :: Keyword.t()) ::
              :ok | {:ok, reply :: any()} | {:error, reason :: any()}

  @doc """
  Callback used for cleaning up the transport layer when the session is closed.
  """
  @callback close(state :: any()) :: :ok

  @optional_callbacks handle_info: 2

  defmacro __using__(_block) do
    quote do
      @behaviour Membrane.RTSP.Transport

      @impl Membrane.RTSP.Transport
      def handle_info(_msg, _state), do: raise("handle_info/2 has not been implemented")

      defoverridable handle_info: 2
    end
  end

  @spec new(module(), binary() | URI.t(), Keyword.t()) :: {:ok, any()} | {:error, any()}
  @deprecated "Use Membrane.RTSP.init/3 instead. It is not recommended to manually initiate transport"
  def new(module, url, options \\ []), do: module.init(url, options)
end
