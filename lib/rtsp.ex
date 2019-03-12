defmodule Membrane.Protocol.RTSP do
  use Bunch
  alias Membrane.Protocol.RTSP.{Request, Session}
  alias Membrane.Protocol.RTSP.Transport.PipeableTCPSocket
  alias Membrane.Protocol.RTSP.Session

  @enforce_keys [:session, :container]
  defstruct @enforce_keys

  def start(url, transport \\ PipeableTCPSocket, options \\ []) do
    with {:ok, supervisor} <- Session.Supervisor.start_child(transport, url, options) do
      {Session, session_pid, _, _} =
        Supervisor.which_children(supervisor) |> List.keyfind(Session, 0)

      {:ok, %__MODULE__{session: session_pid, container: supervisor}}
    end
  end

  def close(%__MODULE__{container: container}) do
    Session.Supervisor.terminate_child(container)
  end

  def describe(session, headers \\ []) do
    do_request(session, "DESCRIBE", headers, "")
  end

  def play(session, headers \\ [], body \\ "") do
    do_request(session, "PLAY", headers, body)
  end

  def setup(session, path, headers \\ [], body \\ "") do
    do_request(session, "SETUP", headers, body, path)
  end

  def teardown(session) do
    do_request(session, "TEARDOWN")
  end

  def do_request(session, method, headers \\ [], body \\ "", path \\ nil) do
    %__MODULE__{session: session} = session

    %Request{method: method, headers: headers, body: body, path: path}
    ~> Session.execute(session, &1)
  end
end
