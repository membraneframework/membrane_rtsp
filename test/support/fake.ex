defmodule Membrane.RTSP.Transport.Fake do
  @moduledoc false
  use Membrane.RTSP.Transport
  import Mockery.Macro
  @response "RTSP/1.0 200 OK\r\n"

  @impl true
  def execute(request, ref, options \\ []) do
    mockable(__MODULE__).proxy(request, ref)
    options = Keyword.merge(ref, options)
    resolver = Keyword.get(options, :resolver, &__MODULE__.default_resolver/1)
    resolver.(request)
  end

  @spec default_resolver(Membrane.RTSP.Request.t()) :: {:ok, binary()}
  def default_resolver(request) do
    [_line, rest] = String.split(request, "\r\n", parts: 2)
    {:ok, @response <> rest}
  end

  @impl true
  def init(_url, options \\ []) do
    {:ok, options}
  end

  @impl true
  def close(_ref) do
    :ok
  end

  @spec proxy(Membrane.RTSP.Request.t(), any()) :: nil
  def proxy(_request, _ref), do: nil
end
