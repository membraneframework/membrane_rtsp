defmodule Membrane.Protocol.RTSP do
  use Bunch
  alias Membrane.Protocol.RTSP.{Session, Request}

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
    %Request{method: method, headers: headers, body: body, path: path}
    ~> Session.execute(session, &1)
  end
end
