defmodule Membrane.RTSP.WorkflowIntegrationTest do
  use ExUnit.Case

  alias Membrane.RTSP
  alias Membrane.RTSP.{Response, Session}
  alias Membrane.RTSP.Transport.TCPSocket

  describe "RTSP workflow executes" do
    @tag external: true
    @tag timeout: 80 * 1000
    test "over network" do
      workflow(
        "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov",
        TCPSocket
      )
    end
  end

  defp workflow(url, transport, options \\ []) do
    assert {:ok, session} = Session.start_link(url, transport, options)
    assert {:ok, %Response{status: 200}} = RTSP.describe(session)

    assert {:ok, %Response{status: 200}} =
             RTSP.setup(session, "/trackID=1", [
               {"Transport", "RTP/AVP;unicast;client_port=57614-57615"}
             ])

    assert {:ok, %Response{status: 200}} =
             RTSP.setup(session, "/trackID=2", [
               {"Transport", "RTP/AVP;unicast;client_port=52614-52615"}
             ])

    assert {:ok, %Response{status: 200}} = RTSP.play(session)
    assert {:ok, %Response{status: 200}} = RTSP.teardown(session)
  end
end
