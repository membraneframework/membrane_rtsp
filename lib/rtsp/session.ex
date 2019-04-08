defmodule Membrane.Protocol.RTSP.Session do
  @moduledoc """
  This module serves as a container for Session and Transport process combination.
  """
  use Supervisor

  alias Membrane.Protocol.RTSP
  alias Membrane.Protocol.RTSP.Supervisor, as: RTSPSupervisor
  alias Membrane.Protocol.RTSP.{Request, Response, Transport}
  alias Membrane.Protocol.RTSP.Session.Manager

  defstruct [:manager, :supervisor]

  @type t :: %__MODULE__{
          manager: pid(),
          supervisor: pid()
        }

  @doc """
  Starts Supervised Session.
  """
  @spec start(binary(), module(), Keyword.t()) :: :ignore | {:error, atom()} | {:ok, t()}
  def start(url, transport \\ TCPSocket, options \\ []) do
    with {:ok, supervisor} <- RTSPSupervisor.start_child(transport, url, options) do
      {Manager, session_pid, _, _} =
        supervisor
        |> Supervisor.which_children()
        |> List.keyfind(Manager, 0)

      {:ok, %__MODULE__{manager: session_pid, supervisor: supervisor}}
    end
  end

  @spec close(t()) :: :ok | {:error, atom()}
  def close(%__MODULE__{supervisor: supervisor}) do
    RTSPSupervisor.terminate_child(supervisor)
  end

  @spec request(t(), binary(), RTSP.headers(), binary(), nil | binary()) :: Response.result()
  def request(session, method, headers \\ [], body \\ "", path \\ nil) do
    %__MODULE__{manager: manager} = session

    request = %Request{method: method, headers: headers, body: body, path: path}
    Manager.request(manager, request)
  end

  @doc """
  Starts and links process that Session Manager and companion Transport process.
  """
  @spec start_container(module(), binary(), Keyword.t()) ::
          Supervisor.on_start() | {:error, :invalid_url}
  def start_container(transport, raw_url, options) do
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
        start: {Transport, :start_link, [transport, url]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
