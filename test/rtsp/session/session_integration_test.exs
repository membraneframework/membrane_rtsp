defmodule Membrane.RTSP.Session.IntegrationTest do
  use ExUnit.Case
  alias Membrane.RTSP.Session
  alias Membrane.RTSP.Session.ConnectionInfo
  alias Membrane.RTSP.Transport.PipeableTCPSocket
  alias Membrane.RTSP.Request

  test "works" do
    uri =
      "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov"
      |> URI.parse()

    {:ok, pid} = Session.start_link(uri, PipeableTCPSocket)

    request = %Request{
      method: "DESCRIBE",
      url: "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov",
      headers: []
    }

    Session.execute(pid, request)
    |> IO.inspect()
  end
end
