defmodule Membrane.Protocol.RTSP.Transport.PipeableTCPSocketIntegrationTest do
  use ExUnit.Case
  use Bunch

  alias Membrane.Protocol.RTSP.Transport
  alias Membrane.Protocol.RTSP.Transport.PipeableTCPSocket

  describe "Pipeable TCP Socket" do
    @tag external: true
    test "executes request successfully" do
      {:ok, pid} =
        "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov"
        |> URI.parse()
        ~> Transport.start_link(PipeableTCPSocket, __MODULE__, &1)

      query =
        "DESCRIBE rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov RTSP/1.0\r\n\r\n"

      assert {:ok, result} = PipeableTCPSocket.execute(query, pid)

      result =~ "RTSP/1.0 200 OK\r\nCSeq: 0\r\nServer: Wowza Streaming Engine 4.7.5.01"

      result =~ "nv=0\r\n
      o=- 1771219918 1771219918 IN IP4 184.72.239.149\r\n
      s=BigBuckBunny_115k.mov\r\nc=IN IP4 184.72.239.149\r\n
      t=0 0\r\n
      a=sdplang:en\r\n
      a=range:npt=0- 596.48\r\n
      a=control:*\r\nm=audio 0 RTP/AVP 96\r\n
      a=rtpmap:96 mpeg4-generic/12000/2\r\na=fmtp:96 profile-level-id=1;mode=AAC-hbr;
      sizelength=13;indexlength=3;indexdeltalength=3;config=1490\r\n
      a=control:trackID=1\r\nm=video 0 RTP/AVP 97\r\n
      a=rtpmap:97 H264/90000\r\n
      a=fmtp:97 packetization-mode=1;
      profile-level-id=42C01E;sprop-parameter-sets=Z0LAHtkDxWhAAAADAEAAAAwDxYuS,aMuMsg==\r\n
      a=cliprect:0,0,160,240\r\na=framesize:97 240-160\r\na=framerate:24.0\r\na=control:trackID=2"
    end

    test "dies when it's session dies" do
      alias Membrane.Protocol.RTSP.Session

      assert {:ok, session} =
               Session.start_link(
                 "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov",
                 PipeableTCPSocket
               )

      %Session.State{transport_executor: transport_ref} = :sys.get_state(session)
      [{pid, _}] = Registry.lookup(TransportRegistry, transport_ref)
      assert Process.alive?(pid)
      GenServer.stop(session)
      refute Process.alive?(pid)
    end
  end
end
