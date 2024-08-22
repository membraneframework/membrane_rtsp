defmodule Membrane.RTSP.SessionLogicTest do
  use ExUnit.Case
  use Bunch
  import Mockery

  alias Membrane.RTSP
  alias Membrane.RTSP.State
  alias Membrane.RTSP.{Request, TCPSocket}

  @response_header "RTSP/1.0 200 OK\r\n"

  setup_all do
    uri = "rtsp://localhost:5554/vod/mp4:name.mov" |> URI.parse()
    mock(:gen_tcp, :connect, :gen_tcp.listen(0, []))
    {:ok, socket} = TCPSocket.connect(uri, 500)

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
         %{state: state, request: request} do
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

    test "preserves session_id", %{request: request, state: state} do
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

    test "add session_id header to request", %{request: request, state: state} do
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
      state: state,
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

    test "does not apply credentials to request if they were already present", %{state: state} do
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

    assert state.auth == {:digest, %{nonce: "nonce", realm: "realm"}}
  end

  test "digest auth", %{state: state, request: request} do
    credentials = "login:password"

    mock(:gen_tcp, [send: 2], fn _socket, serialized_request ->
      assert String.contains?(
               serialized_request,
               "\r\nAuthorization: Digest username=\"login\", realm=\"realm\", nonce=\"nonce\", uri=\"rtsp://localhost:5554/vod/mp4:name.mov\", response=\"0e19b16c4576c70fe6b4bf462f2a76b6\"\r\n"
             )

      mock_response(serialized_request)
    end)

    parsed_uri = URI.parse("rtsp://#{credentials}@localhost:5554/vod/mp4:name.mov")
    digest_auth_options = {:digest, %{nonce: "nonce", realm: "realm"}}

    state = %State{state | uri: parsed_uri, auth: digest_auth_options}

    assert {:reply, {:ok, _response}, _state} = RTSP.handle_call({:execute, request}, nil, state)
  end

  defp mock_response(request) do
    [_line, rest] = String.split(request, "\r\n", parts: 2)
    {:ok, @response_header <> rest}
  end
end
