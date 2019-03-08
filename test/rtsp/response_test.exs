defmodule Membrane.Protocol.RTSP.ResponseTest do
  use ExUnit.Case

  alias Membrane.Protocol.RTSP.Response
  alias Membrane.Protocol.SDP.Session

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

      assert %Session{version: "0"} = body
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
  end

  describe "Response utility" do
    setup do
      base = %Response{status: 200, version: "1.0"}
      [base: base]
    end

    test "get_header returns header if it does exist", %{base: base} do
      assert {:ok, "value"} ==
               %Response{base | headers: [{"name", "value"}]}
               |> Response.get_header("name")
    end

    test "get_header returns error if header does not exist", %{base: base} do
      assert {:error, :no_such_header} == base |> Response.get_header("name")
    end
  end
end
