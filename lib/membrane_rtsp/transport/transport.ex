defmodule Membrane.RTSP.Transport do
  @callback init(url :: URI.t(), connection_timeout :: non_neg_integer()) ::
              {:ok, any()} | {:error, any()}

  @callback handle_info(msg :: any(), state :: any()) ::
              {action :: term(), state :: any()}
              | {action :: term(), reply :: any(), state :: any()}

  @callback execute(request :: any(), state :: any()) ::
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
end
