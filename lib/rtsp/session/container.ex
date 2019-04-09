defmodule Membrane.Protocol.RTSP.Session.Container do
  @moduledoc """
  This module serves as a container for Session and Transport process combination.
  """
  use Supervisor

  alias Membrane.Protocol.RTSP.Session.Manager
  alias Membrane.Protocol.RTSP.Transport

  @doc """
  Starts and links process that Session Manager and companion Transport process.
  """
  @spec start_link(module(), binary(), Keyword.t()) ::
          Supervisor.on_start() | {:error, :invalid_url}
  def start_link(transport, raw_url, options) do
    case URI.parse(raw_url) do
      %URI{port: port, host: host, scheme: "rtsp"} = url
      when is_number(port) and is_binary(host) ->
        transport = Transport.new(transport, make_ref())
        Supervisor.start_link(__MODULE__, [transport, url, options])

      _ ->
        {:error, :invalid_url}
    end
  end

  @impl true
  def init([transport, url, options]) do
    children = [
      %{
        id: Manager,
        start: {Manager, :start_link, [transport, url, options]}
      },
      %{
        id: Transport,
        start: {Transport, :start_link, [transport, url, options]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
