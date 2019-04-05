defmodule Membrane.Protocol.RTSP do
  @moduledoc """
  This module provides a functionality to open a session, execute a RTSP requests
  through that session and close the session.
  """
  alias __MODULE__.Supervisor, as: RTSPSupervisor
  alias Membrane.Protocol.RTSP.{Request, Response, SessionManager}
  alias Membrane.Protocol.RTSP.Transport.TCPSocket

  @enforce_keys [:session, :container]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          session: pid(),
          container: pid()
        }

  @type response :: {:ok, Response.t()} | {:error, atom()}
  @type headers :: [{binary(), binary()}]

  @spec start(binary(), module(), Keyword.t()) :: :ignore | {:error, atom()} | {:ok, t()}
  def start(url, transport \\ TCPSocket, options \\ []) do
    with {:ok, supervisor} <- RTSPSupervisor.start_child(transport, url, options) do
      {SessionManager, session_pid, _, _} =
        supervisor
        |> Supervisor.which_children()
        |> List.keyfind(SessionManager, 0)

      {:ok, %__MODULE__{session: session_pid, container: supervisor}}
    end
  end

  @spec close(t()) :: :ok | {:error, atom()}
  def close(%__MODULE__{container: container}) do
    RTSPSupervisor.terminate_child(container)
  end

  @spec describe(t(), headers()) :: response()
  def describe(session, headers \\ []), do: request(session, "DESCRIBE", headers, "")

  @spec announce(t(), headers(), binary()) :: response()
  def announce(session, headers \\ [], body \\ ""),
    do: request(session, "ANNOUNCE", headers, body)

  @spec get_parameter(t(), headers(), binary()) :: response()
  def get_parameter(session, headers \\ [], body \\ ""),
    do: request(session, "GET_PARAMETER", headers, body)

  @spec options(t(), headers()) :: response()
  def options(session, headers \\ []), do: request(session, "OPTIONS", headers)

  @spec pause(t(), headers()) :: response()
  def pause(session, headers \\ []), do: request(session, "PAUSE", headers)

  @spec play(t(), headers()) :: response()
  def play(session, headers \\ []) do
    request(session, "PLAY", headers, "")
  end

  @spec record(t(), headers()) :: response()
  def record(session, headers \\ []), do: request(session, "RECORD", headers)

  @spec setup(t(), binary(), headers()) :: response()
  def setup(session, path, headers \\ []) do
    request(session, "SETUP", headers, "", path)
  end

  @spec set_parameter(t(), headers(), binary()) :: response()
  def set_parameter(session, headers \\ [], body \\ ""),
    do: request(session, "SET_PARAMETER", headers, body)

  @spec teardown(t(), headers()) :: response
  def teardown(session, headers \\ []), do: request(session, "TEARDOWN", headers)

  @spec request(t(), binary(), headers(), binary(), nil | binary()) :: response
  def request(session, method, headers \\ [], body \\ "", path \\ nil) do
    %__MODULE__{session: session_pid} = session

    request = %Request{method: method, headers: headers, body: body, path: path}
    SessionManager.request(session_pid, request)
  end
end
