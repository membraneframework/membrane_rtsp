defmodule Membrane.Protocol.RTSP.SessionTest do
  use ExUnit.Case
  use Bunch

  alias Membrane.Protocol.RTSP.{Request, SessionManager, Transport}
  alias Membrane.Protocol.RTSP.SessionManager.State
  alias Membrane.Protocol.RTSP.Transport.Fake

  import Mockery
  import Mockery.Assertions

  setup_all do
    transport = Transport.new(Fake, "fake_executor")

    state = %State{
      transport: transport,
      cseq: 0,
      uri: "rtsp://domain.net:554/vod/mp4:name.mov" |> URI.parse(),
      session_id: "fake_session"
    }

    request = %Request{method: "OPTIONS"}

    [state: state, request: request]
  end

  describe "Session when executing a request" do
    test """
         adds default headers and increments cseq every time a request is \
         resolved successfully\
         """,
         %{state: state, request: request} do
      mock(Fake, [proxy: 2], fn serialized_request, _ ->
        assert String.contains?(serialized_request, "\r\nUser-Agent")
      end)

      assert {:reply, {:ok, _}, next_state} =
               SessionManager.handle_call({:execute, request}, nil, state)

      assert next_state == %State{state | cseq: state.cseq + 1}
      assert_called(Fake, proxy: 2)
    end

    test "returns an error if response has different session", %{
      state: state
    } do
      resolver = fn _ -> {:error, :timeout} end
      state = %State{state | execution_options: [resolver: resolver]}

      {:reply, {:error, :timeout}, ^state} =
        SessionManager.handle_call({:execute, %Request{method: "OPTIONS"}}, nil, state)
    end

    test "preserves session_id", %{request: request, state: state} do
      state = %State{state | session_id: nil}
      session_id = "arbitrary_string"
      request = request |> Request.with_header("Session", session_id)

      mock(Fake, [proxy: 2], fn serialized_request, _ ->
        assert String.contains?(serialized_request, "\r\nSession: " <> session_id <> "\r\n")
      end)

      assert {:reply, {:ok, _}, state} =
               SessionManager.handle_call({:execute, request}, nil, state)

      assert state.session_id == session_id
      assert {:reply, {:ok, _}, _} = SessionManager.handle_call({:execute, request}, nil, state)
      assert_called(Fake, proxy: 2)
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
      state = %State{state | uri: parsed_uri}

      assert {:reply, {:ok, _}, state} =
               SessionManager.handle_call({:execute, request}, nil, state)

      assert_called(Fake, proxy: 2)
    end
  end
end
