defmodule Membrane.Protocol.RTSP.SessionTest do
  use ExUnit.Case
  use Bunch

  alias Membrane.Protocol.RTSP.{Transport, Request, Session}
  alias Membrane.Protocol.RTSP.Session.State
  alias Membrane.Protocol.RTSP.Transport.Fake

  import Mockery
  import Membrane.Support.MockeryHelper

  setup_all do
    ref = Transport.transport_name("fake_executor")

    state = %State{
      transport: Fake,
      cseq: 0,
      uri: "rtsp://domain.net:554/vod/mp4:name.mov" |> URI.parse(),
      transport_executor: ref,
      session_id: "fake_session"
    }

    request = %Request{method: "OPTIONS"}

    [state: state, request: request, ref: ref]
  end

  describe "Session when executing request" do
    test "increments cseq every successful request and adds default headers", %{
      state: state,
      request: request
    } do
      mock(Fake, :proxy, nil)

      assert {:reply, {:ok, _}, next_state} = Session.handle_call({:execute, request}, nil, state)
      assert next_state == %State{state | cseq: state.cseq + 1}

      assert_called(Fake, :proxy, fn [serialized_request | _] ->
        String.contains?(serialized_request, "\r\nUser-Agent")
      end)
    end

    test "returns an error if response has different session", %{
      state: state
    } do
      resolver = fn _ -> {:error, :timeout} end
      state = %Session.State{state | execution_options: [resolver: resolver]}

      {:reply, {:error, :timeout}, ^state} =
        Session.handle_call({:execute, %Request{method: "OPTIONS"}}, nil, state)
    end

    test "preserves session_id", %{request: request, state: state} do
      state = %State{state | session_id: nil}
      session_id = "arbitrary_string"
      request = request |> Request.with_header("Session", session_id)

      assert {:reply, {:ok, _}, state} = Session.handle_call({:execute, request}, nil, state)
      assert state.session_id == session_id
      assert {:reply, {:ok, _}, _} = Session.handle_call({:execute, request}, nil, state)

      assert_called(Fake, :proxy, fn [serialized_request | _] ->
        String.contains?(serialized_request, "\r\nSession: " <> session_id <> "\r\n")
      end)
    end

    test "applies credentials to request if they were provided in the uri", %{
      state: state,
      request: request
    } do
      credentials = "login:password"
      encoded_credentials = credentials |> Base.encode64()

      state =
        "rtsp://#{credentials}@domain.net:554/vod/mp4:name.mov"
        |> URI.parse()
        ~> %State{state | uri: &1}

      assert {:reply, {:ok, _}, state} = Session.handle_call({:execute, request}, nil, state)

      assert_called(Fake, :proxy, fn [serialized_request | _] ->
        String.contains?(
          serialized_request,
          "\r\nAuthorization: Basic #{encoded_credentials}\r\n"
        )
      end)
    end
  end
end
