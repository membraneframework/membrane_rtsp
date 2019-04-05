defmodule Membrane.Protocol.RTSP.Session.Supervisor do
  @moduledoc """
  This module serves as a container for spawning Session and Transport combination.

  # TODO write some detailed documentation
  """
  use Supervisor

  alias Membrane.Protocol.RTSP.{SessionManager, Transport}

  @doc """
  Starts and links process that supervises Session and companion Transport process.
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
        id: SessionManager,
        start: {SessionManager, :start_link, [transport, url, options]}
      },
      %{
        id: Transport,
        start: {Transport, :start_link, [transport, url]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
