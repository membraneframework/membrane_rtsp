defmodule Membrane.Protocol.RTSP.RequestTest do
  use ExUnit.Case
  use Bunch

  alias Membrane.Support.Factory
  alias Membrane.Protocol.RTSP.Request

  describe "Renders request properly" do
    test "when path is not set" do
      uri = "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov"

      expected_result = """
      DESCRIBE rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov RTSP/1.0
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
               |> Request.to_string(Factory.SampleOptionsRequest.url())
    end
  end

  describe "Request utility" do
    test "with_header adds header" do
      assert %Request{method: "OPTIONS", headers: [{"name", "value"}]} ==
               %Request{method: "OPTIONS"} |> Request.with_header("name", "value")
    end
  end

  def assert_rendered_request(request, expected_result, uri_string) do
    uri = uri_string |> URI.parse()

    expected_result =
      expected_result
      |> String.replace("\n", "\r\n")
      ~> (&1 <> "\r\n")

    assert expected_result ==
             request
             |> Request.to_string(uri)
  end
end
