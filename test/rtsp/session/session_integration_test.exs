defmodule Membrane.Protocol.RTSP.Session.IntegrationTest do
  use ExUnit.Case, async: false
  alias Membrane.Protocol.RTSP.Session
  alias Membrane.Protocol.RTSP.Transport.PipeableTCPSocket
  alias Membrane.Protocol.RTSP.{Request, Response}
  alias Membrane.Protocol.SDP

  @tag external: true
  test "works" do
    uri = "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov"

    {:ok, pid} = Session.start_link(uri, PipeableTCPSocket)

    request = %Request{
      method: "DESCRIBE",
      headers: [],
      body: ""
    }

    assert {:ok, response} = Session.execute(pid, request)

    assert %Response{
             body: body,
             headers: headers,
             status: 200,
             version: "1.0"
           } = response

    assert %{
             "CSeq" => "0",
             "Cache-Control" => "no-cache",
             "Content-Base" =>
               "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov/",
             "Content-Length" => _,
             "Content-Type" => "application/sdp",
             "Server" => "Wowza Streaming Engine 4.7.5.01 build21752"
           } = headers

    assert %SDP.Session{
             attributes: [
               {"control", "*"},
               {"range", "npt=0- 596.48"},
               {"sdplang", "en"}
             ],
             bandwidth: [],
             connection_information: %SDP.ConnectionInformation{
               address: %SDP.ConnectionInformation.IP4{
                 ttl: nil,
                 value: {184, 72, 239, 149}
               },
               network_type: "IN"
             },
             email: nil,
             encryption: nil,
             media: [
               %SDP.Media{
                 attributes: [
                   "rtpmap:96 mpeg4-generic/12000/2",
                   "fmtp:96 profile-level-id=1;mode=AAC-hbr;sizelength=13;indexlength=3;indexdeltalength=3;config=1490",
                   "control:trackID=1"
                 ],
                 bandwidth: [],
                 connection_information: %SDP.ConnectionInformation{
                   address: %SDP.ConnectionInformation.IP4{
                     ttl: nil,
                     value: {184, 72, 239, 149}
                   },
                   network_type: "IN"
                 },
                 encryption: nil,
                 fmt: "96",
                 ports: [0],
                 protocol: "RTP/AVP",
                 title: nil,
                 type: "audio"
               },
               %SDP.Media{
                 attributes: [
                   "rtpmap:97 H264/90000",
                   "fmtp:97 packetization-mode=1;profile-level-id=42C01E;sprop-parameter-sets=Z0LAHtkDxWhAAAADAEAAAAwDxYuS,aMuMsg==",
                   "cliprect:0,0,160,240",
                   "framesize:97 240-160",
                   "framerate:24.0",
                   "control:trackID=2"
                 ],
                 bandwidth: [],
                 connection_information: %SDP.ConnectionInformation{
                   address: %SDP.ConnectionInformation.IP4{
                     ttl: nil,
                     value: {184, 72, 239, 149}
                   },
                   network_type: "IN"
                 },
                 encryption: nil,
                 fmt: "97",
                 ports: [0],
                 protocol: "RTP/AVP",
                 title: nil,
                 type: "video"
               }
             ],
             origin: %SDP.Origin{
               address_type: "IP4",
               network_type: "IN",
               session_id: _,
               session_version: _,
               unicast_address: {184, 72, 239, 149},
               username: "-"
             },
             phone_number: nil,
             session_information: nil,
             session_name: "BigBuckBunny_115k.mov",
             time_repeats: [],
             time_zones_adjustments: [],
             timing: %SDP.Timing{
               start_time: 0,
               stop_time: 0
             },
             uri: nil,
             version: "0"
           } = body
  end
end
