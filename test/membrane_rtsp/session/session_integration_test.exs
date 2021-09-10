defmodule Membrane.RTSP.Session.IntegrationTest do
  use ExUnit.Case, async: false
  use Bunch

  alias Membrane.RTSP.{Request, Response, Session}
  alias Membrane.RTSP.Transport.TCPSocket
  alias Membrane.Protocol.SDP

  @uri "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov"

  describe "Session works in combination with" do
    @tag external: true
    test "real transport" do
      integration_test(@uri, TCPSocket)
    end
  end

  defp integration_test(uri, transport, options \\ []) do
    {:ok, pid} = Session.start_link(uri, transport, options)

    request = %Request{
      method: "DESCRIBE",
      headers: [],
      body: ""
    }

    assert {:ok, response} = Session.request(pid, request)

    assert %Response{
             body: body,
             headers: headers,
             status: 200,
             version: "1.0"
           } = response

    assert [
             {"CSeq", "0"},
             {"Server", "Wowza Streaming Engine 4.7.5.01 build21752"},
             {"Cache-Control", "no-cache"},
             {"Expires", _},
             {"Content-Length", _},
             {"Content-Base",
              "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov/"},
             {"Date", _},
             {"Content-Type", "application/sdp"},
             {"Session", _}
           ] = headers

    assert %SDP.Session{} = body
  end
end
