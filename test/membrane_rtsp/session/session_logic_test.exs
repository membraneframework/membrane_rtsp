defmodule Membrane.RTSP.SessionLogicTest do
  use ExUnit.Case
  use Bunch
  import Mockery
  import Mockery.Assertions

  alias Membrane.RTSP
  alias Membrane.RTSP.Logic.State
  alias Membrane.RTSP.Request
  alias Membrane.RTSP.Transport.Fake

  setup_all do
    {:ok, transport} = Fake.init("fake_executor")

    state = %State{
      transport: transport,
      transport_module: Fake,
      cseq: 0,
      uri: "rtsp://domain.net:554/vod/mp4:name.mov" |> URI.parse(),
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
      mock(Fake, [proxy: 2], fn serialized_request, _options ->
        assert String.contains?(serialized_request, "\r\nUser-Agent")
      end)

      assert {:reply, {:ok, _response}, next_state} =
               RTSP.handle_call({:execute, request}, nil, state)

      assert next_state == %State{state | cseq: state.cseq + 1}
      assert_called(Fake, proxy: 2)
    end

    test "returns an error if response has different session", %{
      state: state
    } do
      resolver = fn _request -> {:error, :timeout} end
      state = %State{state | execution_options: [resolver: resolver]}

      {:reply, {:error, :timeout}, ^state} =
        RTSP.handle_call({:execute, %Request{method: "OPTIONS"}}, nil, state)
    end

    test "preserves session_id", %{request: request, state: state} do
      state = %State{state | session_id: nil}
      session_id = "arbitrary_string"
      request = request |> Request.with_header("Session", session_id)

      mock(Fake, [proxy: 2], fn serialized_request, _options ->
        assert String.contains?(serialized_request, "\r\nSession: " <> session_id <> "\r\n")
      end)

      assert {:reply, {:ok, _response}, state} = RTSP.handle_call({:execute, request}, nil, state)

      assert state.session_id == session_id

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)

      assert_called(Fake, proxy: 2)
    end

    test "add session_id header to request", %{request: request, state: state} do
      session_id = "arbitrary_string"
      state = %State{state | session_id: session_id}

      mock(Fake, [proxy: 2], fn serialized_request, _options ->
        assert String.contains?(serialized_request, "\r\nSession: " <> session_id <> "\r\n")
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

      mock(Fake, [proxy: 2], fn serialized_request, _ref ->
        assert String.contains?(
                 serialized_request,
                 "\r\nAuthorization: Basic #{encoded_credentials}\r\n"
               )
      end)

      parsed_uri = URI.parse("rtsp://#{credentials}@domain.net:554/vod/mp4:name.mov")
      state = %State{state | uri: parsed_uri, auth: :basic}

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)

      assert_called(Fake, proxy: 2)
    end

    test "does not apply credentials to request if they were already present", %{state: state} do
      request = %Request{method: "OPTIONS", headers: [{"Authorization", "Basic data"}]}

      mock(Fake, [proxy: 2], fn serialized_request, _ref ->
        assert String.contains?(
                 serialized_request,
                 "\r\nAuthorization: Basic data\r\n"
               )
      end)

      parsed_uri = URI.parse("rtsp://login:password@domain.net:554/vod/mp4:name.mov")
      state = %State{state | uri: parsed_uri}

      assert {:reply, {:ok, _response}, _state} =
               RTSP.handle_call({:execute, request}, nil, state)

      assert_called(Fake, proxy: 2)
    end
  end

  test "add digest information in the state", %{state: state, request: request} do
    resolver = fn _request ->
      {:ok,
       "RTSP/1.0 200 OK\r\nWWW-Authenticate: Digest realm=\"realm\", nonce=\"nonce\"\r\n\r\n"}
    end

    state = %State{state | execution_options: [resolver: resolver]}

    assert {:reply, {:ok, _response}, state} = RTSP.handle_call({:execute, request}, nil, state)

    assert state.auth == {:digest, %{nonce: "nonce", realm: "realm"}}

    assert_called(Fake, proxy: 2)
  end

  test "digest auth", %{state: state, request: request} do
    credentials = "login:password"

    mock(Fake, [proxy: 2], fn serialized_request, _ref ->
      assert String.contains?(
               serialized_request,
               "\r\nAuthorization: Digest username=\"login\", realm=\"realm\", nonce=\"nonce\", uri=\"rtsp://domain.net:554/vod/mp4:name.mov\", response=\"13afc9c7a879e7fbd27bab70d472c4fc\"\r\n"
             )
    end)

    parsed_uri = URI.parse("rtsp://#{credentials}@domain.net:554/vod/mp4:name.mov")
    digest_auth_options = {:digest, %{nonce: "nonce", realm: "realm"}}

    state = %State{state | uri: parsed_uri, auth: digest_auth_options}

    assert {:reply, {:ok, _response}, _state} = RTSP.handle_call({:execute, request}, nil, state)

    assert_called(Fake, proxy: 2)
  end
end
