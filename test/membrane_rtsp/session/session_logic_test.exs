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

  defp mock_response(request) do
    [_line, rest] = String.split(request, "\r\n", parts: 2)
    {:ok, @response_header <> rest}
  end
end
