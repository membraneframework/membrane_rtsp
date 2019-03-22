defmodule Membrane.Protocol.RTSP.RequestTest do
  use ExUnit.Case

  alias Membrane.Protocol.RTSP.Request
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
        headers: [{"CSeq", 3}]
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
  end

  def assert_rendered_request(request, expected_result, uri_string) do
    uri = uri_string |> URI.parse()

    expected_result =
      expected_result
      |> String.replace("\n", "\r\n")

    assert expected_result <> "\r\n" ==
             request
             |> Request.stringify(uri)
  end
end
