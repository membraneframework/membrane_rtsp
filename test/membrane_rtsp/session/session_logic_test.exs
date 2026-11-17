defmodule Membrane.RTSP.SessionLogicTest do
  use ExUnit.Case
  use Bunch
  import Mockery

  alias Membrane.RTSP
  alias Membrane.RTSP.{Request, Transport}
  alias Membrane.RTSP.State

  @response_header "RTSP/1.0 200 OK\r\n"

  setup_all do
    uri = "rtsp://localhost:5554/vod/mp4:name.mov" |> URI.parse()
    mock(:gen_tcp, :connect, :gen_tcp.listen(0, []))
    {:ok, socket} = Transport.connect(uri, 500)

    state = %State{
      socket: socket,
      cseq: 0,
      uri: uri,
      response_timeout: 500,
      session_id: "fake_session"
    }

    request = %Request{method: "OPTIONS"}

    [state: state, request: request]
  end

  describe "Session Logic when executing a request" do
    test """
         adds default headers and increments cseq every time a request is \
         resolved successfully\
         """,
         %{state: %State{} = state, request: request} do
      mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
        assert String.contains?(serialized_request, "\r\nUser-Agent")
        mock_response(serialized_request)
      end)

      assert {:reply, {:ok, _response}, next_state} =
               RTSP.handle_call({:execute, request}, nil, state)

      assert next_state == %State{state | cseq: state.cseq + 1}
    end

    test "returns an error if response has different session", %{
      state: state
    } do
      mock(:gen_tcp, [send: 2], fn _socket, _request ->
        {:error, :timeout}
      end)

      {:reply, {:error, :timeout}, ^state} =
        RTSP.handle_call({:execute, %Request{method: "OPTIONS"}}, nil, state)
    end

    test "preserves session_id", %{request: request, state: %State{} = state} do
      state = %State{state | session_id: nil}
      session_id = "arbitrary_string"
      request = request |> Request.with_header("Session", session_id)

      mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
        assert String.contains?(serialized_request, "\r\nSession: " <> session_id <> "\r\n")
        mock_response(serialized_request)
      end)

      assert {:reply, {:ok, _response}, state} = RTSP.handle_call({:execute, request}, nil, state)

      assert state.session_id == session_id

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)
    end

    test "add session_id header to request", %{request: request, state: %State{} = state} do
      session_id = "arbitrary_string"
      state = %State{state | session_id: session_id}

      mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
        assert String.contains?(serialized_request, "\r\nSession: " <> session_id <> "\r\n")
        mock_response(serialized_request)
      end)

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)
    end

    test "applies credentials to request if they were provided in the uri", %{
      state: %State{} = state,
      request: request
    } do
      credentials = "login:password"
      encoded_credentials = credentials |> Base.encode64()

      mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
        assert String.contains?(
                 serialized_request,
                 "\r\nAuthorization: Basic #{encoded_credentials}\r\n"
               )

        mock_response(serialized_request)
      end)

      parsed_uri = URI.parse("rtsp://#{credentials}@localhost:5554/vod/mp4:name.mov")
      state = %State{state | uri: parsed_uri, auth: :basic}

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)
    end

    test "does not apply credentials to request if they were already present", %{
      state: %State{} = state
    } do
      request = %Request{method: "OPTIONS", headers: [{"Authorization", "Basic data"}]}

      mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
        assert String.contains?(
                 serialized_request,
                 "\r\nAuthorization: Basic data\r\n"
               )

        mock_response(serialized_request)
      end)

      parsed_uri = URI.parse("rtsp://login:password@localhost:5554/vod/mp4:name.mov")
      state = %State{state | uri: parsed_uri}

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)
    end
  end

  test "add digest information in the state", %{state: state, request: request} do
    mock(:gen_tcp, [send: 2], fn _socket, _request ->
      {:ok,
       "RTSP/1.0 200 OK\r\nWWW-Authenticate: Digest realm=\"realm\", nonce=\"nonce\"\r\n\r\n"}
    end)

    assert {:reply, {:ok, _response}, state} = RTSP.handle_call({:execute, request}, nil, state)

    assert state.auth == {:digest, %{nonce: "nonce", realm: "realm", qop: nil, nc: 2}}
  end

  test "add digest information with qop in the state (RFC 2617)", %{
    state: state,
    request: request
  } do
    mock(:gen_tcp, [send: 2], fn _socket, _request ->
      {:ok,
       "RTSP/1.0 200 OK\r\nWWW-Authenticate: Digest realm=\"VIVOTEK\", nonce=\"abc123\", qop=\"auth\"\r\n\r\n"}
    end)

    assert {:reply, {:ok, _response}, state} = RTSP.handle_call({:execute, request}, nil, state)

    assert state.auth == {:digest, %{nonce: "abc123", realm: "VIVOTEK", qop: "auth", nc: 2}}
  end

  test "add digest information with unquoted qop", %{state: state, request: request} do
    mock(:gen_tcp, [send: 2], fn _socket, _request ->
      {:ok,
       "RTSP/1.0 200 OK\r\nWWW-Authenticate: Digest realm=\"test\", nonce=\"xyz\", qop=auth\r\n\r\n"}
    end)

    assert {:reply, {:ok, _response}, state} = RTSP.handle_call({:execute, request}, nil, state)

    assert state.auth == {:digest, %{nonce: "xyz", realm: "test", qop: "auth", nc: 2}}
  end

  describe "Session header" do
    defp respond_with(headers) do
      mock(:gen_tcp, [send: 2], fn _socket, _request ->
        {:ok, "RTSP/1.0 200 OK\r\n" <> Enum.map_join(headers, &(&1 <> "\r\n")) <> "\r\n"}
      end)
    end

    test "is stripped of its parameters and of surrounding whitespace",
         %{state: %State{} = state, request: request} do
      respond_with(["Session:  12345678 ; timeout=60"])

      assert {:reply, {:ok, _response}, state} =
               RTSP.handle_call({:execute, request}, nil, %State{state | session_id: nil})

      assert state.session_id == "12345678"
    end

    # libavformat keeps the first session id it was given and GStreamer the last one;
    # neither fails the request, which a strict comparison did.
    test "carrying another session id does not fail the request", %{
      state: state,
      request: request
    } do
      respond_with(["Session: another_session"])

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:reply, {:ok, %RTSP.Response{status: 200}}, state} =
                   RTSP.handle_call({:execute, request}, nil, state)

          assert state.session_id == "fake_session"
        end)

      assert log =~ "another_session"
    end
  end

  describe "WWW-Authenticate challenge" do
    defp authenticate(state, request, www_authenticate_headers) do
      headers = Enum.map_join(www_authenticate_headers, &"WWW-Authenticate: #{&1}\r\n")

      mock(:gen_tcp, [send: 2], fn _socket, _request ->
        {:ok, "RTSP/1.0 200 OK\r\n#{headers}\r\n"}
      end)

      assert {:reply, {:ok, _response}, state} = RTSP.handle_call({:execute, request}, nil, state)
      state.auth
    end

    # RFC 2617 section 1.2: parameter values are either tokens or quoted strings.
    test "with unquoted parameter values is understood", %{state: state, request: request} do
      assert authenticate(state, request, ["Digest realm=cam, nonce=abc123"]) ==
               {:digest, %{nonce: "abc123", realm: "cam", qop: nil, nc: 2}}
    end

    test "is understood whatever the case of the scheme and of parameter names",
         %{state: state, request: request} do
      assert authenticate(state, request, [~s(digest Realm="cam", NONCE="abc123")]) ==
               {:digest, %{nonce: "abc123", realm: "cam", qop: nil, nc: 2}}

      assert authenticate(state, request, [~s(DIGEST realm = "cam" ,nonce = "abc123")]) ==
               {:digest, %{nonce: "abc123", realm: "cam", qop: nil, nc: 2}}
    end

    test "offering Basic before Digest selects Digest", %{state: state, request: request} do
      assert authenticate(state, request, [
               ~s(Basic realm="cam"),
               ~s(Digest realm="cam", nonce="abc123")
             ]) == {:digest, %{nonce: "abc123", realm: "cam", qop: nil, nc: 2}}
    end

    test "with an unsupported digest algorithm is skipped for one that is supported",
         %{state: state, request: request} do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert authenticate(state, request, [
                   ~s(Digest realm="cam", nonce="sha", algorithm=SHA-256),
                   ~s(Digest realm="cam", nonce="md5", algorithm=MD5)
                 ]) == {:digest, %{nonce: "md5", realm: "cam", qop: nil, nc: 2}}
        end)

      assert log =~ "SHA-256"
    end

    test "that cannot be used for Digest falls back to Basic without raising",
         %{state: state, request: request} do
      ExUnit.CaptureLog.capture_log(fn ->
        assert authenticate(state, request, [~s(Digest realm="cam")]) == :basic

        assert authenticate(state, request, [~s(Digest realm="cam", nonce="x", algorithm=SHA-256)]) ==
                 :basic

        assert authenticate(state, request, ["Digest"]) == :basic
      end)
    end

    test "listing several qop values selects auth", %{state: state, request: request} do
      assert {:digest, %{qop: "auth"}} =
               authenticate(state, request, [
                 ~s(Digest realm="cam", nonce="n", qop="auth-int,auth")
               ])

      assert {:digest, %{qop: "auth"}} =
               authenticate(state, request, [
                 ~s(Digest realm="cam", nonce="n", qop="auth, auth-int")
               ])
    end
  end

  test "digest auth without qop (RFC 2069)", %{state: %State{} = state, request: request} do
    credentials = "login:password"

    mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
      assert String.contains?(
               serialized_request,
               "\r\nAuthorization: Digest username=\"login\", realm=\"realm\", nonce=\"nonce\", uri=\"rtsp://localhost:5554/vod/mp4:name.mov\", response=\"0e19b16c4576c70fe6b4bf462f2a76b6\"\r\n"
             )

      mock_response(serialized_request)
    end)

    parsed_uri = URI.parse("rtsp://#{credentials}@localhost:5554/vod/mp4:name.mov")
    digest_auth_options = {:digest, %{nonce: "nonce", realm: "realm", qop: nil, nc: 1}}

    state = %State{state | uri: parsed_uri, auth: digest_auth_options}

    assert {:reply, {:ok, _response}, _state} = RTSP.handle_call({:execute, request}, nil, state)
  end

  test "digest auth with qop (RFC 2617)", %{state: %State{} = state, request: request} do
    credentials = "login:password"

    mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
      # QOP auth includes: algorithm, qop, nc (8-digit hex), cnonce
      assert String.contains?(serialized_request, "Authorization: Digest ")
      assert String.contains?(serialized_request, "username=\"login\"")
      assert String.contains?(serialized_request, "realm=\"realm\"")
      assert String.contains?(serialized_request, "nonce=\"nonce\"")
      assert String.contains?(serialized_request, "algorithm=MD5")
      assert String.contains?(serialized_request, "qop=auth")
      assert String.contains?(serialized_request, "nc=00000001")
      assert String.contains?(serialized_request, "cnonce=")

      mock_response(serialized_request)
    end)

    parsed_uri = URI.parse("rtsp://#{credentials}@localhost:5554/vod/mp4:name.mov")
    digest_auth_options = {:digest, %{nonce: "nonce", realm: "realm", qop: "auth", nc: 1}}

    state = %State{state | uri: parsed_uri, auth: digest_auth_options}

    assert {:reply, {:ok, _response}, new_state} =
             RTSP.handle_call({:execute, request}, nil, state)

    # nc should increment after successful request
    assert {:digest, %{nc: 2}} = new_state.auth
  end

  describe "Digest opaque" do
    # RFC 2617 section 3.2.1: the opaque value should be returned by the client unchanged.
    test "is stored when the challenge carries it", %{state: state, request: request} do
      mock(:gen_tcp, [send: 2], fn _socket, _request ->
        {:ok,
         "RTSP/1.0 200 OK\r\nWWW-Authenticate: Digest realm=\"cam\", nonce=\"n\", opaque=\"5ccc069c\"\r\n\r\n"}
      end)

      assert {:reply, {:ok, _response}, state} = RTSP.handle_call({:execute, request}, nil, state)

      assert state.auth ==
               {:digest, %{nonce: "n", realm: "cam", qop: nil, nc: 2, opaque: "5ccc069c"}}
    end

    test "is echoed in the Authorization header", %{state: %State{} = state, request: request} do
      parsed_uri = URI.parse("rtsp://login:password@localhost:5554/vod/mp4:name.mov")

      for qop <- [nil, "auth"] do
        mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
          assert serialized_request =~ ~s(opaque="5ccc069c")
          mock_response(serialized_request)
        end)

        auth = {:digest, %{nonce: "n", realm: "cam", qop: qop, nc: 1, opaque: "5ccc069c"}}
        state = %State{state | uri: parsed_uri, auth: auth}

        assert {:reply, {:ok, _response}, _state} =
                 RTSP.handle_call({:execute, request}, nil, state)
      end
    end
  end

  describe "Credentials in the URL" do
    # RFC 3986 section 3.2.1: reserved characters in the userinfo are percent-encoded.
    test "are percent-decoded before use", %{state: %State{} = state, request: request} do
      mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
        assert serialized_request =~
                 "\r\nAuthorization: Basic #{Base.encode64("ad:min:p@ss/w#rd")}\r\n"

        mock_response(serialized_request)
      end)

      parsed_uri = URI.parse("rtsp://ad%3Amin:p%40ss%2Fw%23rd@localhost:5554/vod/mp4:name.mov")
      state = %State{state | uri: parsed_uri, auth: :basic}

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)
    end

    test "are percent-decoded for Digest too", %{state: %State{} = state, request: request} do
      # MD5("login:realm:p@ss") combined with MD5("OPTIONS:<uri>") and the nonce
      ha1 = md5_hex("login:realm:p@ss")
      ha2 = md5_hex("OPTIONS:rtsp://localhost:5554/vod/mp4:name.mov")
      expected = md5_hex("#{ha1}:nonce:#{ha2}")

      mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
        assert serialized_request =~ ~s(username="login")
        assert serialized_request =~ ~s(response="#{expected}")
        mock_response(serialized_request)
      end)

      parsed_uri = URI.parse("rtsp://login:p%40ss@localhost:5554/vod/mp4:name.mov")
      auth = {:digest, %{nonce: "nonce", realm: "realm", qop: nil, nc: 1}}
      state = %State{state | uri: parsed_uri, auth: auth}

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)
    end

    test "may lack a password without crashing Digest", %{
      state: %State{} = state,
      request: request
    } do
      mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
        assert serialized_request =~ ~s(username="login")
        mock_response(serialized_request)
      end)

      parsed_uri = URI.parse("rtsp://login@localhost:5554/vod/mp4:name.mov")
      auth = {:digest, %{nonce: "nonce", realm: "realm", qop: nil, nc: 1}}
      state = %State{state | uri: parsed_uri, auth: auth}

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)
    end

    defp md5_hex(data), do: data |> :erlang.md5() |> Base.encode16(case: :lower)
  end

  defp mock_response(request) do
    [_line, rest] = String.split(request, "\r\n", parts: 2)
    {:ok, @response_header <> rest}
  end
end
