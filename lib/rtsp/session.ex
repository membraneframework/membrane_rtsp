defmodule Membrane.Protocol.RTSP.Session do
  @moduledoc """

  """
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
  def start(url, transport \\ Transport.TCPSocket, options \\ []) do
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
end
