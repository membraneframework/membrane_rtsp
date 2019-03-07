defmodule Membrane.Protocol.RTSP.WorkflowIntegrationTest do
  use ExUnit.Case

  alias Membrane.Protocol.RTSP
  alias Membrane.Protocol.RTSP.{Response, Session}
  alias Membrane.Protocol.RTSP.Transport.PipeableTCPSocket

  @tag external: true
  @tag timeout: 80 * 1000
  test "Tests RTSP transmission workflow" do
    assert {:ok, session} =
             "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov"
             |> Session.start_link(PipeableTCPSocket)

    assert {:ok, %Response{status: 200}} = RTSP.describe(session) |> IO.inspect()

    assert {:ok, %Response{status: 200}} =
             RTSP.setup(session, "/trackID=1", [
               {"Transport", "RTP/AVP;unicast;client_port=57614-57615"}
             ])

    assert {:ok, %Response{status: 200}} =
             RTSP.setup(session, "/trackID=2", [
               {"Transport", "RTP/AVP;unicast;client_port=52614-52615"}
             ])

    assert {:ok, %Response{status: 200}} = RTSP.play(session) |> IO.inspect()

    :timer.sleep(65 * 1000)
    assert {:ok, %Response{status: 200}} = RTSP.teardown(session) |> IO.inspect()
  end
end
