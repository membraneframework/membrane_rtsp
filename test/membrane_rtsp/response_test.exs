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

  describe "Status line" do
    # RFC 2326 section 7.1: Reason-Phrase = *<TEXT, excluding CR, LF>, so it may be
    # empty and may hold any character.
    test "is parsed when the reason phrase is missing" do
      assert {:ok, %Response{status: 200, version: "1.0"}} =
               Response.parse("RTSP/1.0 200\r\nCSeq: 1\r\n\r\n")

      assert {:ok, %Response{status: 200}} = Response.parse("RTSP/1.0 200 \r\nCSeq: 1\r\n\r\n")
    end

    test "is parsed when the reason phrase holds digits and punctuation" do
      for reason <- ["Bad Request (invalid URL)", "RTSP Version-1 not supported", "OK."] do
        assert {:ok, %Response{status: 400}} =
                 Response.parse("RTSP/1.0 400 #{reason}\r\nCSeq: 1\r\n\r\n")
      end
    end

    test "is rejected when it does not start with an RTSP version and a status code" do
      for line <- [
            "HTTP/1.1 200 OK",
            "RTSP/1.0 OK",
            "RTSP/1.0 20 OK",
            "RTSP/1.0 2000 OK",
            "garbage"
          ] do
        assert {:error, :invalid_start_line} = Response.parse(line <> "\r\nCSeq: 1\r\n\r\n")
      end
    end
  end

  describe "Header lines" do
    # RFC 2326 takes its header syntax from RFC 2616 section 4.2: any amount of
    # whitespace may follow the colon and a value may be empty.
    test "are parsed with no whitespace after the colon" do
      assert {:ok, %Response{headers: headers}} =
               Response.parse("RTSP/1.0 200 OK\r\nCSeq:1\r\nSession:abc;timeout=60\r\n\r\n")

      assert headers == [{"CSeq", "1"}, {"Session", "abc;timeout=60"}]
    end

    test "are parsed with several spaces or tabs around the value" do
      assert {:ok, %Response{headers: headers}} =
               Response.parse("RTSP/1.0 200 OK\r\nCSeq:  1 \r\nSession:\tabc\t\r\n\r\n")

      assert headers == [{"CSeq", "1"}, {"Session", "abc"}]
    end

    test "are parsed when the value is empty" do
      assert {:ok, %Response{headers: headers}} =
               Response.parse("RTSP/1.0 200 OK\r\nCSeq: 1\r\nServer:\r\n\r\n")

      assert headers == [{"CSeq", "1"}, {"Server", ""}]
    end

    test "may be absent altogether" do
      assert {:ok, %Response{status: 200, headers: []}} =
               Response.parse("RTSP/1.0 200 OK\r\n\r\n")
    end

    test "are unfolded when a value continues on the next line" do
      assert {:ok, %Response{headers: headers}} =
               Response.parse(
                 "RTSP/1.0 200 OK\r\nCSeq: 1\r\nPublic: OPTIONS, DESCRIBE,\r\n SETUP,\r\n\tPLAY\r\n\r\n"
               )

      assert headers == [{"CSeq", "1"}, {"Public", "OPTIONS, DESCRIBE, SETUP, PLAY"}]
    end

    test "that have no colon are skipped instead of failing the whole response" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %Response{status: 200, headers: headers}} =
                   Response.parse(
                     "RTSP/1.0 200 OK\r\nCSeq: 1\r\nbroken line\r\nSession: abc\r\n\r\n"
                   )

          assert headers == [{"CSeq", "1"}, {"Session", "abc"}]
        end)

      assert log =~ "broken line"
    end

    test "verify_content_length/1 waits for the body when no space follows the colon" do
      assert Response.verify_content_length(
               "RTSP/1.0 200 OK\r\nCSeq:2\r\nContent-Length:296\r\n\r\n"
             ) ==
               {:error, 296, 0}
    end
  end

  describe "Truncated or garbled input" do
    test "parse/1 does not raise when the blank line after the headers is missing" do
      assert {:ok, %Response{status: 200, headers: [{"CSeq", "1"}], body: ""}} =
               Response.parse("RTSP/1.0 200 OK\r\nCSeq: 1\r\n")
    end

    test "verify_content_length/1 treats an unparsable Content-Length as absent" do
      assert Response.verify_content_length(
               "RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Length: abc\r\n\r\n"
             ) ==
               {:ok, 0, 0}

      assert Response.verify_content_length(
               "RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Length: -5\r\n\r\n"
             ) ==
               {:ok, 0, 0}
    end
  end

  describe "Content-Type" do
    @sdp "v=0\r\no=- 0 1 IN IP4 10.0.0.1\r\ns=Cam\r\n"

    # RFC 2616 section 3.7: the type and subtype are case-insensitive and may be
    # followed by parameters.
    test "selects the SDP parser regardless of case" do
      for content_type <- ["Application/SDP", "APPLICATION/SDP", "application/Sdp"] do
        assert {:ok, %Response{body: %ExSDP{session_name: "Cam"}}} =
                 Response.parse(
                   "RTSP/1.0 200 OK\r\nCSeq: 2\r\nContent-Type: #{content_type}\r\n\r\n" <> @sdp
                 )
      end
    end

    test "selects the SDP parser when it carries parameters" do
      for content_type <- [
            "application/sdp; charset=utf-8",
            "application/sdp;charset=UTF-8",
            "application/sdp ;q=1"
          ] do
        assert {:ok, %Response{body: %ExSDP{session_name: "Cam"}}} =
                 Response.parse(
                   "RTSP/1.0 200 OK\r\nCSeq: 2\r\nContent-Type: #{content_type}\r\n\r\n" <> @sdp
                 )
      end
    end

    test "leaves a body of another type unparsed" do
      assert {:ok, %Response{body: "v=0\r\n"}} =
               Response.parse(
                 "RTSP/1.0 200 OK\r\nCSeq: 2\r\nContent-Type: application/sdpx\r\n\r\nv=0\r\n"
               )
    end
  end

  describe "parse_session_header/1" do
    defp session(value), do: %Response{status: 200, version: "1.0", headers: [{"Session", value}]}

    test "returns the session id and the timeout" do
      assert Response.parse_session_header(session("12345678;timeout=60")) ==
               {:ok, %{session_id: "12345678", timeout: 60}}
    end

    test "returns no timeout when the server does not announce one" do
      assert Response.parse_session_header(session("12345678")) ==
               {:ok, %{session_id: "12345678", timeout: nil}}
    end

    test "tolerates whitespace and case in the parameters" do
      for value <- [
            "12345678; timeout=60",
            "12345678 ;Timeout = 60",
            " 12345678;foo=bar;TIMEOUT=60 "
          ] do
        assert Response.parse_session_header(session(value)) ==
                 {:ok, %{session_id: "12345678", timeout: 60}}
      end
    end

    test "ignores a timeout that is not a positive number" do
      for value <- ["12345678;timeout=0", "12345678;timeout=soon", "12345678;timeout="] do
        assert Response.parse_session_header(session(value)) ==
                 {:ok, %{session_id: "12345678", timeout: nil}}
      end
    end

    test "returns an error when there is no Session header" do
      assert Response.parse_session_header(Response.new(200)) == {:error, :no_such_header}
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
