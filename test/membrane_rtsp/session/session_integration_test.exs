defmodule Membrane.RTSP.IntegrationTest do
  use ExUnit.Case, async: false
  use Bunch

  alias Membrane.RTSP
  alias Membrane.RTSP.{Request, Response}
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
    {:ok, pid} = RTSP.start_link(uri, transport, options)

    request = %Request{
      method: "DESCRIBE",
      headers: [],
      body: ""
    }

    assert {:ok, response} = RTSP.request(pid, request.method, request.headers, request.body)

    assert %Response{
             body: body,
             headers: headers,
             status: 200,
             version: "1.0"
           } = response

    assert [
             {"CSeq", "0"},
             {"Server", _},
             {"Cache-Control", "no-cache"},
             {"Expires", _},
             {"Content-Length", _},
             {"Content-Base",
              "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov/"},
             {"Date", _},
             {"Content-Type", "application/sdp"},
             {"Session", _}
           ] = headers

    assert Enum.find_value(headers, nil, fn
             {"Server", server} -> server
             _otherwise -> false
           end)
           |> String.starts_with?("Wowza Streaming Engine")

    assert %SDP.Session{} = body
  end
end
