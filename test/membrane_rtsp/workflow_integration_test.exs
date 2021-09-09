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

  def resolver(request) do
    {_request, response} = List.keyfind(request_mappings(), request, 0)
    response
  end

  defp request_mappings do
    [
      {"""
       DESCRIBE rtsp://domain.net:554/vod/mp4:mobvie.mov RTSP/1.0
       User-Agent: MembraneRTSP/0.2.1 (Membrane Framework RTSP Client)
       CSeq: 0

       """
       |> format_rtsp_binary(),
       {:ok,
        """
        RTSP/1.0 200 OK
        CSeq: 0
        Server: Wowza Streaming Engine 4.7.5.01 build21752\r\nCache-Control: no-cache
        Expires: Tue, 12 Mar 2019 10:48:38 UTC
        Content-Length: 587
        Content-Base: rtsp://domain.net:554/vod/mp4:mobvie.mov/
        Date: Tue, 12 Mar 2019 10:48:38 UTC
        Content-Type: application/sdp
        Session: 369279037;timeout=60

        v=0
        o=- 369279037 369279037 IN IP4 184.72.239.149\r\ns=BigBuckBunny_115k.mov
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
        """}},
      {"SETUP rtsp://domain.net:554/vod/mp4:mobvie.mov/trackID=1 RTSP/1.0\r\nUser-Agent: MembraneRTSP/0.2.1 (Membrane Framework RTSP Client)\r\nCSeq: 1\r\nSession: 369279037\r\nTransport: RTP/AVP;unicast;client_port=57614-57615\r\n\r\n",
       {:ok,
        "RTSP/1.0 200 OK\r\nCSeq: 1\r\nServer: Wowza Streaming Engine 4.7.5.01 build21752\r\nCache-Control: no-cache\r\nExpires: Tue, 12 Mar 2019 10:48:38 UTC\r\nTransport: RTP/AVP;unicast;client_port=57614-57615;source=184.72.239.149;server_port=16552-16553;ssrc=63D581FB\r\nDate: Tue, 12 Mar 2019 10:48:38 UTC\r\nSession: 369279037;timeout=60\r\n\r\n"}},
      {"SETUP rtsp://domain.net:554/vod/mp4:mobvie.mov/trackID=2 RTSP/1.0\r\nUser-Agent: MembraneRTSP/0.2.1 (Membrane Framework RTSP Client)\r\nCSeq: 2\r\nSession: 369279037\r\nTransport: RTP/AVP;unicast;client_port=52614-52615\r\n\r\n",
       {:ok,
        "RTSP/1.0 200 OK\r\nCSeq: 2\r\nServer: Wowza Streaming Engine 4.7.5.01 build21752\r\nCache-Control: no-cache\r\nExpires: Tue, 12 Mar 2019 10:48:38 UTC\r\nTransport: RTP/AVP;unicast;client_port=52614-52615;source=184.72.239.149;server_port=16582-16583;ssrc=644708C0\r\nDate: Tue, 12 Mar 2019 10:48:38 UTC\r\nSession: 369279037;timeout=60\r\n\r\n"}},
      {"PLAY rtsp://domain.net:554/vod/mp4:mobvie.mov RTSP/1.0\r\nUser-Agent: MembraneRTSP/0.2.1 (Membrane Framework RTSP Client)\r\nCSeq: 3\r\nSession: 369279037\r\n\r\n",
       {:ok,
        "RTSP/1.0 200 OK\r\nRTP-Info: url=rtsp://domain.net:554/vod/mp4:mobvie.mov/trackID=1;seq=1;rtptime=0,url=rtsp://domain.net:554/vod/mp4:mobvie.mov/trackID=2;seq=1;rtptime=0\r\nCSeq: 3\r\nServer: Wowza Streaming Engine 4.7.5.01 build21752\r\nCache-Control: no-cache\r\nRange: npt=0.0-\r\nSession: 369279037;timeout=60\r\n\r\n"}},
      {"TEARDOWN rtsp://domain.net:554/vod/mp4:mobvie.mov RTSP/1.0\r\nUser-Agent: MembraneRTSP/0.2.1 (Membrane Framework RTSP Client)\r\nCSeq: 4\r\nSession: 369279037\r\n\r\n",
       {:ok,
        "RTSP/1.0 200 OK\r\nCSeq: 4\r\nServer: Wowza Streaming Engine 4.7.5.01 build21752\r\nCache-Control: no-cache\r\nSession: 369279037;timeout=60\r\n\r\n"}}
    ]
  end

  defp format_rtsp_binary(binary) do
    binary
    |> String.replace("\n", "\r\n")
  end
end
