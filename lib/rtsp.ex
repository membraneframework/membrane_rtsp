defmodule Membrane.Protocol.RTSP do
  @moduledoc """
  This module provides functionality to execute open and close session
  and execute RTSP requests.

  In order to execute a given request you have to start the session first
  by calling `start/3`.

  ```
  iex> {:ok, session} = RTSP.start("rtsp://domain.name:port/path")
  {:ok, %RTSP{}}
  ```

  then you can proceed with calling

  """
  alias Membrane.Protocol.RTSP.{Request, Response, Session}
  alias Membrane.Protocol.RTSP.Transport.PipeableTCPSocket
  alias Membrane.Protocol.RTSP.Session

  @enforce_keys [:session, :container]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          session: pid(),
          container: pid()
        }

  @type response :: {:ok, Response.t()} | {:error, atom()}
  @type header :: {binary(), binary()}
  @type headers :: [header]

  @spec start(binary(), module(), Keyword.t()) :: :ignore | {:error, any()} | {:ok, t()}
  def start(url, transport \\ PipeableTCPSocket, options \\ []) do
    with {:ok, supervisor} <- Session.Supervisor.start_child(transport, url, options) do
      {Session, session_pid, _, _} =
        supervisor
        |> Supervisor.which_children()
        |> List.keyfind(Session, 0)

      {:ok, %__MODULE__{session: session_pid, container: supervisor}}
    end
  end

  @spec close(Membrane.Protocol.RTSP.t()) :: :ok | {:error, atom()}
  def close(%__MODULE__{container: container}) do
    Session.Supervisor.terminate_child(container)
  end

  @spec describe(t(), headers) :: response()
  def describe(session, headers \\ []), do: do_request(session, "DESCRIBE", headers, "")

  @spec announce(t(), headers(), binary()) :: response()
  def announce(session, headers \\ [], body \\ ""),
    do: do_request(session, "ANNOUNCE", headers, body)

  @spec get_parameter(t(), headers, binary()) :: response()
  def get_parameter(session, headers \\ [], body \\ ""),
    do: do_request(session, "GET_PARAMETER", headers, body)

  @spec options(t(), headers) :: response()
  def options(session, headers \\ []), do: do_request(session, "OPTIONS", headers)

  @spec pause(t(), headers) :: response()
  def pause(session, headers \\ []), do: do_request(session, "PAUSE", headers)

  def play(session, headers \\ [], body \\ "") do
    do_request(session, "PLAY", headers, body)
  end

  @spec record(t(), headers) :: response()
  def record(session, headers \\ []), do: do_request(session, "RECORD", headers)

  @spec setup(t(), binary(), headers) :: response()
  def setup(session, path, headers \\ []) do
    do_request(session, "SETUP", headers, "", path)
  end

  def set_parameter(session, headers \\ [], body \\ ""),
    do: do_request(session, "SET_PARAMETER", headers, body)

  def teardown(session, headers \\ []), do: do_request(session, "TEARDOWN", headers)

  def do_request(session, method, headers \\ [], body \\ "", path \\ nil) do
    %__MODULE__{session: session} = session

    request = %Request{method: method, headers: headers, body: body, path: path}
    Session.execute(session, request)
  end
end
