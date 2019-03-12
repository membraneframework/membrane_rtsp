defmodule Membrane.Protocol.RTSP.Session.CoupleSupervisor do
  use Supervisor
  use Bunch

  alias Membrane.Protocol.RTSP.Session
  alias Membrane.Protocol.RTSP.Transport

  @spec start_link(module(), binary(), Keyword.t()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(transport, url, options) do
    Supervisor.start_link(__MODULE__, [transport, url, options])
  end

  @impl true
  def init([transport, raw_url, options]) do
    case URI.parse(raw_url) do
      %URI{port: port, host: host, scheme: "rtsp"} = url
      when is_number(port) and is_binary(host) ->
        ref = :os.system_time(:millisecond) |> to_string() ~> (&1 <> raw_url)

        children = [
          {Session, [transport, ref, url, options]},
          {Transport, [transport, ref, url]}
        ]

        Supervisor.init(children, strategy: :one_for_one)

      _ ->
        {:stop, :invalid_url}
    end
  end
end
