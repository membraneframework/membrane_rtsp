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

  describe "Session when initializing" do
    test "parses uri and spawns connection" do
      ref = "ref"

      assert {:ok, state} =
               "rtsp://domain.net:554/vod/mp4:name.mov"
               ~> %{url: &1, transport: Fake, ref: ref}
               |> Session.init()

      assert %Session.State{
               cseq: 0,
               session_id: nil,
               transport: Fake,
               transport_executor: ^ref,
               uri: %URI{host: "domain.net", port: 554}
             } = state
    end

    test "returns an error when uri does not contain host and port" do
      assert {:stop, :invalid_uri} ==
               "rtsp://:file.extension"
               ~> %{url: &1, transport: Fake, ref: ""}
               |> Session.init()
    end
  end

  describe "Session when terminating" do
    setup do
      {:ok, session} = Session.start_link("rtsp://domain.net:554/vod/mp4:name.mov", Fake)
      [session: session]
    end

    test "does nothing if connection is dead", %{session: session} do
      assert Process.alive?(session)
      Session.close(session)
      :timer.sleep(1)
      refute Process.alive?(session)
    end
  end
end
