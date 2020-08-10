defmodule Membrane.RTSP.Session.IntegrationTest do
  use ExUnit.Case, async: false
  use Bunch

  alias Membrane.RTSP.{Request, Response, Session}
  alias Membrane.RTSP.Session.Manager
  alias Membrane.RTSP.Transport.{Fake, TCPSocket}
  alias Membrane.Protocol.SDP

  @expected_query """
                  DESCRIBE rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov RTSP/1.0
                  User-Agent: MembraneRTSP/0.1.0 (Membrane Framework RTSP Client)
                  CSeq: 0\n
                  """
                  |> String.replace("\n", "\r\n")

  @uri "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov"

  describe "Session works in combination with" do
    @tag external: true
    test "real transport" do
      integration_test(@uri, TCPSocket)
    end

    test "fake transport" do
      integration_test(@uri, Fake, resolver: &resolver/1)
    end
  end

  def integration_test(uri, transport, options \\ []) do
    rtsp = Session.start_link(uri, transport, options)
    assert %Session{manager: pid} = rtsp

    request = %Request{
      method: "DESCRIBE",
      headers: [],
      body: ""
    }

    assert {:ok, response} = Manager.request(pid, request)

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

  def resolver(@expected_query) do
    response =
      """
      RTSP/1.0 200 OK
      CSeq: 0
      Server: Wowza Streaming Engine 4.7.5.01 build21752
      Cache-Control: no-cache
      Expires: Tue, 12 Mar 2019 12:21:06 UTC
      Content-Length: 587
      Content-Base: rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov/
      Date: Tue, 12 Mar 2019 12:21:06 UTC
      Content-Type: application/sdp
      Session: 443551157;timeout=60

      v=0
      o=- 443551157 443551157 IN IP4 184.72.239.149
      s=BigBuckBunny_115k.mov
      c=IN IP4 184.72.239.149
      t=0 0
      a=sdplang:en
      a=range:npt=0- 596.48
      a=control:*
      m=audio 0 RTP/AVP 96
      a=rtpmap:96 mpeg4-generic/12000/2
      a=fmtp:96 profile-level-id=1;mode=AAC-hbr;sizelength=13;indexlength=3;indexdeltalength=3;config=1490
      a=control:trackID=1
      m=video 0 RTP/AVP 97
      a=rtpmap:97 H264/90000
      a=fmtp:97 packetization-mode=1;profile-level-id=42C01E;sprop-parameter-sets=Z0LAHtkDxWhAAAADAEAAAAwDxYuS,aMuMsg==
      a=cliprect:0,0,160,240
      a=framesize:97 240-160
      a=framerate:24.0
      a=control:trackID=2
      """
      |> String.replace("\n", "\r\n")

    {:ok, response}
  end
end
