defmodule Membrane.RTSP.ResponseTest do
  use ExUnit.Case

  alias Membrane.RTSP.Response

  doctest Response

  describe "Response parser" do
    test "parses describe response with sdp spec" do
      assert {:ok, %Response{body: body, headers: headers}} =
               """
               RTSP/1.0 200 OK
               CSeq: 3
               Content-Type: application/sdp

               v=0
               o=- 1730695490 1730695490 IN IP4 184.72.239.149
               s=BigBuckBunny_115k.mov
               c=IN IP4 184.72.239.149
               t=0 0
               a=sdplang:en
               m=audio 0 RTP/AVP 96
               a=rtpmap:96 mpeg4-generic/12000/2
               a=fmtp:96 profile-level-id=1;mode=AAC-hbr;sizelength=13;indexlength=3;indexdeltalength=3;config=1490
               a=control:trackID=1
               """
               |> String.replace("\n", "\r\n")
               |> Response.parse()

      assert %ExSDP{version: 0} = body
      assert headers == [{"CSeq", "3"}, {"Content-Type", "application/sdp"}]
    end

    test "handles parsing response where status text is not capitalized" do
      response =
        "RTSP/1.0 400 Bad Request\r\nCSeq: 0\r\nDate: Thu, 07 Mar 2019 05:36:09 GMT\r\n\r\n"

      {:ok, parsed_response} = Response.parse(response)

      assert %Response{
               headers: headers,
               status: 400,
               version: "1.0"
             } = parsed_response

      assert headers == [{"CSeq", "0"}, {"Date", "Thu, 07 Mar 2019 05:36:09 GMT"}]
    end

    test "parses sdp body when header names are not in canonical case" do
      assert {:ok, %Response{body: %ExSDP{version: 0}}} =
               """
               RTSP/1.0 200 OK
               CSeq: 2
               Content-type: application/sdp
               Content-length: 37

               v=0
               o=- 0 1 IN IP4 10.0.0.1
               s=Cam
               """
               |> String.replace("\n", "\r\n")
               |> Response.parse()
    end
  end

  describe "Header lookup" do
    test "get_header/2 matches header names case-insensitively" do
      response = %Response{status: 200, version: "1.0", headers: [{"content-LENGTH", "0"}]}

      assert Response.get_header(response, "Content-Length") == {:ok, "0"}
    end

    test "verify_content_length/1 waits for the body when the header is not in canonical case" do
      assert Response.verify_content_length(
               "RTSP/1.0 200 OK\r\nCSeq: 2\r\nContent-length: 296\r\n\r\n"
             ) == {:error, 296, 0}
    end
  end

  describe "Supports endline symbol" do
    test "CRLF" do
      assert_example_parsed(&String.replace(&1, "\n", "\r\n"))
    end

    test "CR" do
      assert_example_parsed(&String.replace(&1, "\n", "\r"))
    end

    test "LF" do
      assert_example_parsed(& &1)
    end

    defp assert_example_parsed(transformer) do
      newline_spec = """
      RTSP/1.0 200 OK
      CSeq: 3
      Content-Type: application/text

      v=0
      """

      assert {:ok, %Response{body: body, headers: headers}} =
               newline_spec
               |> transformer.()
               |> Response.parse()

      assert headers == [{"CSeq", "3"}, {"Content-Type", "application/text"}]
      assert String.trim(body) == "v=0"
    end
  end
end
