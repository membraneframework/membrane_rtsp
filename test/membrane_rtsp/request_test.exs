defmodule Membrane.RTSP.RequestTest do
  use ExUnit.Case

  alias Membrane.RTSP.Request
  alias Membrane.Support.Factory
  doctest Request

  describe "Renders request properly" do
    test "when path is not set" do
      uri = "rtsp://domain.net:554/path:file.mov"

      expected_result = """
      DESCRIBE rtsp://domain.net:554/path:file.mov RTSP/1.0
      CSeq: 3
      """

      %Request{
        method: "DESCRIBE",
        headers: [{"CSeq", "3"}]
      }
      |> assert_rendered_request(expected_result, uri)
    end

    test "when path is set" do
      uri = "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov"

      expected_result = """
      SETUP rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov/trackID=1 RTSP/1.0
      CSeq: 4
      Transport: RTP/AVP;unicast;client_port=57614-57615
      """

      %Request{
        method: "SETUP",
        headers: [{"CSeq", "4"}, {"Transport", "RTP/AVP;unicast;client_port=57614-57615"}],
        path: "trackID=1"
      }
      |> assert_rendered_request(expected_result, uri)
    end

    test "for method OPTIONS" do
      assert Factory.SampleOptionsRequest.raw() ==
               Factory.SampleOptionsRequest.request()
               |> Request.stringify(Factory.SampleOptionsRequest.url())
    end

    test "strips query string from base URI when path is relative" do
      # VIVOTEK cameras include query params in stream URI that should not appear in SETUP
      uri = "rtsp://192.168.1.196:554/media2/stream.sdp?profile=Profile200"

      expected_result = """
      SETUP rtsp://192.168.1.196:554/media2/stream.sdp/trackID=2 RTSP/1.0
      CSeq: 4
      Transport: RTP/AVP;unicast;client_port=57614-57615
      """

      %Request{
        method: "SETUP",
        headers: [{"CSeq", "4"}, {"Transport", "RTP/AVP;unicast;client_port=57614-57615"}],
        path: "trackID=2"
      }
      |> assert_rendered_request(expected_result, uri)
    end

    test "uses absolute URL directly when path is absolute (RFC 2326)" do
      # Bosch cameras return absolute control URLs in SDP
      base_uri = "rtsp://192.168.1.44:554/rtsp_tunnel"

      absolute_control =
        "rtsp://192.168.1.44:554/rtsp_tunnel?p=0&line=1&inst=1&vcd=2&stream=video"

      expected_result = """
      SETUP rtsp://192.168.1.44:554/rtsp_tunnel?p=0&line=1&inst=1&vcd=2&stream=video RTSP/1.0
      CSeq: 4
      Transport: RTP/AVP;unicast;client_port=57614-57615
      """

      %Request{
        method: "SETUP",
        headers: [{"CSeq", "4"}, {"Transport", "RTP/AVP;unicast;client_port=57614-57615"}],
        path: absolute_control
      }
      |> assert_rendered_request(expected_result, base_uri)
    end

    test "strips userinfo from absolute control URL" do
      # Absolute URLs should not leak credentials
      base_uri = "rtsp://user:pass@192.168.1.44:554/rtsp_tunnel"
      absolute_control = "rtsp://user:pass@192.168.1.44:554/rtsp_tunnel?p=0&stream=video"

      request = %Request{
        method: "SETUP",
        headers: [],
        path: absolute_control
      }

      result = Request.stringify(request, URI.parse(base_uri))

      refute String.contains?(result, "user:pass")
      assert String.contains?(result, "rtsp://192.168.1.44:554/rtsp_tunnel?p=0&stream=video")
    end
  end

  defp assert_rendered_request(request, expected_result, uri_string) do
    uri = uri_string |> URI.parse()

    expected_result =
      expected_result
      |> String.replace("\n", "\r\n")

    assert expected_result <> "\r\n" ==
             request
             |> Request.stringify(uri)
  end
end
