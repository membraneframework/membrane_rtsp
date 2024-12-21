defmodule Membrane.RTSP.ServerLogicTest do
  @moduledoc false

  use ExUnit.Case

  import Mockery

  alias Membrane.RTSP.{Request, Response}
  alias Membrane.RTSP.Server.FakeHandler
  alias Membrane.RTSP.Server.{Logic, Logic.State}

  @url %URI{scheme: "rtsp", host: "localhost", port: 554, path: "/stream"}

  setup_all do
    state = %State{
      socket: %{},
      request_handler: FakeHandler,
      request_handler_state: FakeHandler.handle_open_connection(nil, []),
      session_timeout: :timer.minutes(1),
      incoming_media: %{},
      configured_media: %{}
    }

    [state: state]
  end

  test "handle OPTIONS request", %{state: state} do
    mock(:gen_tcp, [send: 2], fn %{}, response ->
      assert response =~ "RTSP/1.0 200 OK"
      assert response =~ "\r\nPublic: #{Enum.join(Logic.allowed_methods(), ", ")}\r\n"
    end)

    assert state ==
             %Request{method: "OPTIONS"}
             |> Logic.process_request(state)
  end

  test "handle GET_PARAMETER request", %{state: state} do
    mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "RTSP/1.0 200 OK" end)

    assert state ==
             %Request{method: "GET_PARAMETER"}
             |> Logic.process_request(state)
  end

  test "handle DESCRIBE request", %{state: state} do
    media = ExSDP.Media.new(:video, 0, "RTP/AVP", 96)
    sdp = ExSDP.new() |> ExSDP.add_media(%{media | connection_data: nil})

    mock(FakeHandler, [respond: 2], fn request, %{} ->
      response =
        Response.new(200)
        |> Response.with_header("Content-Type", "application/sdp")
        |> Response.with_body(to_string(sdp))

      {response, %{described_url: request.path}}
    end)

    mock(:gen_tcp, [send: 2], fn %{}, response ->
      assert response =~ "RTSP/1.0 200 OK"
      assert response =~ "\r\nContent-Type: application/sdp\r\n"
      assert response =~ "\r\nm=video"
    end)

    expected_uri = URI.to_string(@url)

    assert %{request_handler_state: %{described_url: ^expected_uri}} =
             Logic.process_request(%Request{method: "DESCRIBE", path: expected_uri}, state)
  end

  describe "handle SETUP request" do
    test "setup track", %{state: state} do
      control_path = URI.to_string(@url) <> "/trackId=0"

      mock(FakeHandler, [respond: 2], fn request, %{} ->
        assert request.path == control_path
        {Response.new(200), state}
      end)

      mock(:gen_tcp, [send: 2], fn %{}, response ->
        assert response =~ "RTSP/1.0 200 OK"
        assert response =~ "\r\nSession: #{state.session_id};timeout=60\r\n"
      end)

      state =
        %Request{method: "SETUP", path: control_path}
        |> Request.with_header("Transport", "RTP/AVP/TCP;unicast;interleaved=0-1")
        |> Logic.process_request(state)

      assert state.session_state == :ready

      assert %{
               ^control_path => %{
                 transport: :TCP,
                 tcp_socket: %{},
                 channels: {0, 1}
               }
             } = state.configured_media
    end

    test "invalid/missing transport header", %{state: state} do
      mock(:gen_tcp, [send: 2], fn %{}, response ->
        assert response =~ "RTSP/1.0 400 Bad Request"
      end)

      assert ^state =
               %Request{method: "SETUP"}
               |> Request.with_header("Transport", "RTP/AVP")
               |> Logic.process_request(state)

      assert ^state = Logic.process_request(%Request{method: "SETUP"}, state)
    end

    test "multicast not supported", %{state: state} do
      mock(:gen_tcp, [send: 2], fn %{}, response ->
        assert response =~ "RTSP/1.0 400 Bad Request"
      end)

      assert ^state =
               %Request{method: "SETUP"}
               |> Request.with_header("Transport", "RTP/AVP;multicast")
               |> Logic.process_request(state)
    end

    test "udp not supported if rtp socket is nil", %{state: state} do
      mock(:gen_tcp, [send: 2], fn %{}, response ->
        assert response =~ "RTSP/1.0 400 Bad Request"
      end)

      assert ^state =
               %Request{method: "SETUP"}
               |> Request.with_header("Transport", "RTP/AVP;unicast;client_port=3000-3001")
               |> Logic.process_request(state)
    end

    test "not allowed when playing", %{state: state} do
      state = %State{state | session_state: :playing}

      mock(:gen_tcp, [send: 2], fn %{}, response ->
        assert response =~ "RTSP/1.0 455 Method Not Valid In This State"
      end)

      assert ^state =
               %Request{method: "SETUP", path: @url}
               |> Logic.process_request(state)
    end
  end

  describe "handle PLAY request" do
    test "handle PLAY request", %{state: state} do
      uri = %URI{@url | path: "/stream/trackId=0"} |> URI.to_string()

      configured_media = %{
        uri => %{
          ssrc: :rand.uniform(100_000),
          transport: :UDP,
          rtp_socket: %{},
          rtcp_socket: %{},
          client_port: {3000, 3001}
        }
      }

      state = %State{state | session_state: :ready, configured_media: configured_media}

      mock(FakeHandler, [respond: 2], fn ^configured_media, state ->
        {Response.new(200), state}
      end)

      mock(:gen_tcp, [send: 2], fn %{}, response ->
        assert response =~ "RTSP/1.0 200 OK"
        assert response =~ "\r\nSession: #{state.session_id};timeout=60\r\n"
      end)

      assert %{session_state: :playing} =
               %Request{method: "PLAY", path: uri}
               |> Logic.process_request(state)
    end

    test "not allowed before setup", %{state: state} do
      mock(:gen_tcp, [send: 2], fn %{}, response ->
        assert response =~ "RTSP/1.0 455 Method Not Valid In This State"
      end)

      assert ^state =
               %Request{method: "PLAY", path: @url}
               |> Logic.process_request(state)
    end
  end

  describe "handle TEARDOWN request" do
    test "Re-initialize the session if it's not playing", %{state: state} do
      state = %State{
        state
        | session_state: :ready,
          configured_media: %{"control_path" => %{ssrc: 112_235}}
      }

      mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "RTSP/1.0 200 OK" end)

      assert %{session_state: :init, configured_media: %{}} =
               %Request{method: "TEARDOWN"}
               |> Logic.process_request(state)
    end

    test "free resources", %{state: state} do
      state = %State{state | session_state: :playing}

      mock(FakeHandler, [respond: 2], fn nil, state -> {Response.new(200), state} end)
      mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "RTSP/1.0 200 OK" end)

      assert %{session_state: :init, configured_media: %{}} =
               %Request{method: "TEARDOWN", path: @url}
               |> Logic.process_request(state)
    end
  end

  test "return 501 (Not Implemented) for not supported methods", %{state: state} do
    mock(:gen_tcp, [send: 2], fn %{}, response ->
      assert response =~ "RTSP/1.0 501 Not Implemented"
    end)

    assert ^state = Logic.process_request(%Request{method: "SET_PARAMETER"}, state)
  end
end
