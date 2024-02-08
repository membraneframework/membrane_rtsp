defmodule Membrane.RTSP.Server.FakeHandler do
  @moduledoc false

  @behaviour Membrane.RTSP.Server.Handler

  import Mockery.Macro

  @impl true
  def handle_open_connection(_conn), do: %{}

  @impl true
  def handle_closed_connection(_state), do: :ok

  @impl true
  def handle_describe(request, state) do
    mockable(__MODULE__).respond(request, state)
  end

  @impl true
  def handle_setup(request, state) do
    mockable(__MODULE__).respond(request, state)
  end

  @impl true
  def handle_play(configured_media, state) do
    mockable(__MODULE__).respond(configured_media, state)
  end

  @impl true
  def handle_pause(state) do
    mockable(__MODULE__).respond(nil, state)
  end

  @impl true
  def handle_teardown(state) do
    mockable(__MODULE__).respond(nil, state)
  end

  @spec respond(Membrane.RTSP.Request.t() | map(), any()) :: nil
  def respond(_request, _state), do: nil
end
