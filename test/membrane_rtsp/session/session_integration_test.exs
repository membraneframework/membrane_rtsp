defmodule Membrane.RTSP.IntegrationTest do
  use ExUnit.Case, async: false
  use Bunch

  alias Membrane.Protocol.SDP
  alias Membrane.RTSP
  alias Membrane.RTSP.{Request, Response}
  alias Membrane.RTSP.Transport.TCPSocket

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
             {"Server", _server},
             {"Cache-Control", "no-cache"},
             {"Expires", _expires},
             {"Content-Length", _content_length},
             {"Content-Base",
              "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov/"},
             {"Date", _date},
             {"Content-Type", "application/sdp"},
             {"Session", _session}
           ] = headers

    assert Enum.find_value(headers, nil, fn
             {"Server", server} -> server
             _otherwise -> false
           end)
           |> String.starts_with?("Wowza Streaming Engine")

    assert %SDP.Session{} = body
  end
end
