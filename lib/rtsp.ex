defmodule Membrane.Protocol.RTSP do
  @moduledoc """
  This module provides a functionality to open a session, execute a RTSP requests
  through that session and close the session.
  """
  alias Membrane.Protocol.RTSP.{Response, Session}

  @type headers :: [{binary(), binary()}]

  @spec describe(Session.t(), headers()) :: Response.result()
  def describe(session, headers \\ []), do: Session.request(session, "DESCRIBE", headers, "")

  @spec announce(Session.t(), headers(), binary()) :: Response.result()
  def announce(session, headers \\ [], body \\ ""),
    do: Session.request(session, "ANNOUNCE", headers, body)

  @spec get_parameter(Session.t(), headers(), binary()) :: Response.result()
  def get_parameter(session, headers \\ [], body \\ ""),
    do: Session.request(session, "GET_PARAMETER", headers, body)

  @spec options(Session.t(), headers()) :: Response.result()
  def options(session, headers \\ []), do: Session.request(session, "OPTIONS", headers)

  @spec pause(Session.t(), headers()) :: Response.result()
  def pause(session, headers \\ []), do: Session.request(session, "PAUSE", headers)

  @spec play(Session.t(), headers()) :: Response.result()
  def play(session, headers \\ []) do
    Session.request(session, "PLAY", headers, "")
  end

  @spec record(Session.t(), headers()) :: Response.result()
  def record(session, headers \\ []), do: Session.request(session, "RECORD", headers)

  @spec setup(Session.t(), binary(), headers()) :: Response.result()
  def setup(session, path, headers \\ []) do
    Session.request(session, "SETUP", headers, "", path)
  end

  @spec set_parameter(Session.t(), headers(), binary()) :: Response.result()
  def set_parameter(session, headers \\ [], body \\ ""),
    do: Session.request(session, "SET_PARAMETER", headers, body)

  @spec teardown(Session.t(), headers()) :: Response.result()
  def teardown(session, headers \\ []), do: Session.request(session, "TEARDOWN", headers)
end
