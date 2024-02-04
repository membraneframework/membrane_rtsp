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
      request_handler_state: FakeHandler.handle_open_connection(nil)
    }

    [state: state]
  end

  test "handle OPTIONS request", %{state: state} do
    mock(:gen_tcp, [send: 2], fn %{}, response ->
      assert response =~ "200"
      assert response =~ "\r\nPublic: #{Enum.join(Logic.allowed_methods(), ", ")}\r\n"
    end)

    assert {:ok, ^state} =
             %Request{method: "OPTIONS"}
             |> Request.stringify(@url)
             |> Logic.process_request(state)
  end

  test "handle GET_PARAMETER request", %{state: state} do
    mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "200" end)

    assert {:ok, ^state} =
             %Request{method: "GET_PARAMETER"}
             |> Request.stringify(@url)
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
      assert response =~ "200"
      assert response =~ "\r\nContent-Type: application/sdp\r\n"
    end)

    expected_uri = URI.to_string(@url)

    assert {:ok, %{request_handler_state: %{described_url: ^expected_uri}}} =
             %Request{method: "DESCRIBE"}
             |> Request.stringify(@url)
             |> Logic.process_request(state)
  end

  describe "handle SETUP request" do
    test "setup track", %{state: state} do
      control_path = URI.to_string(@url) <> "/trackId=0"

      mock(FakeHandler, [respond: 2], fn request, %{} ->
        assert request.path == control_path
        {Response.new(200), state}
      end)

      mock(:gen_tcp, [send: 2], fn %{}, response ->
        assert response =~ "200"
        assert response =~ "\r\nSession: #{state.session_id}\r\n"
      end)

      assert {:ok, state} =
               %Request{method: "SETUP"}
               |> Request.with_header("Transport", "RTP/AVP/TCP;unicast;interleaved=0-1")
               |> Request.stringify(%URI{@url | path: "/stream/trackId=0"})
               |> Logic.process_request(state)

      assert state.phase == :setup

      assert %{
               ^control_path => %{
                 transport: :TCP,
                 tcp_socket: %{},
                 channels: {0, 1}
               }
             } = state.setupped_tracks
    end

    test "invalid/missing transport header", %{state: state} do
      mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "400" end)

      assert {:ok, ^state} =
               %Request{method: "SETUP"}
               |> Request.with_header("Transport", "RTP/AVP")
               |> Request.stringify(@url)
               |> Logic.process_request(state)

      assert {:ok, ^state} =
               %Request{method: "SETUP"}
               |> Request.stringify(@url)
               |> Logic.process_request(state)
    end

    test "multicast not supported", %{state: state} do
      mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "400" end)

      assert {:ok, ^state} =
               %Request{method: "SETUP"}
               |> Request.with_header("Transport", "RTP/AVP;multicast")
               |> Request.stringify(@url)
               |> Logic.process_request(state)
    end

    test "udp not supported if rtp socket is nil", %{state: state} do
      mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "400" end)

      assert {:ok, ^state} =
               %Request{method: "SETUP"}
               |> Request.with_header("Transport", "RTP/AVP;unicast;client_port=3000-3001")
               |> Request.stringify(@url)
               |> Logic.process_request(state)
    end

    test "not allowed when playing", %{state: state} do
      state = %State{state | phase: :playing}

      mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "405" end)

      assert {:ok, ^state} =
               %Request{method: "SETUP"}
               |> Request.stringify(@url)
               |> Logic.process_request(state)
    end
  end

  describe "handle PLAY request" do
    test "handle PLAY request", %{state: state} do
      uri = %URI{@url | path: "/stream/trackId=0"}

      setupped_tracks = %{
        URI.to_string(uri) => %{
          ssrc: :rand.uniform(100_000),
          transport: :UDP,
          rtp_socket: %{},
          rtcp_socket: %{},
          client_port: {3000, 3001}
        }
      }

      state = %State{state | phase: :setup, setupped_tracks: setupped_tracks}

      mock(FakeHandler, [respond: 2], fn ^setupped_tracks, state ->
        {Response.new(200), state}
      end)

      mock(:gen_tcp, [send: 2], fn %{}, response ->
        assert response =~ "200"
        assert response =~ "\r\nSession: #{state.session_id}\r\n"
      end)

      assert {:ok, %{phase: :playing}} =
               %Request{method: "PLAY"}
               |> Request.stringify(uri)
               |> Logic.process_request(state)
    end

    test "not allowed before setup", %{state: state} do
      mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "405" end)

      assert {:ok, ^state} =
               %Request{method: "PLAY"}
               |> Request.stringify(@url)
               |> Logic.process_request(state)
    end
  end

  test "handle TEARDOWN request", %{state: state} do
    state = %State{state | phase: :playing}

    mock(FakeHandler, [respond: 2], fn nil, state -> {Response.new(200), state} end)
    mock(:gen_tcp, [send: 2], fn %{}, response -> assert response =~ "200" end)

    assert {:close, ^state} =
             %Request{method: "TEARDOWN"}
             |> Request.stringify(@url)
             |> Logic.process_request(state)
  end

  test "return 501 (Not Implemented) for not supported methods", %{state: state} do
    mock(:gen_tcp, [send: 2], fn %{}, response ->
      assert {:ok, %Response{status: 501}} = Response.parse(response)
    end)

    request = "ANNOUNCE rtsp://localhost:554/stream RTSP/1.0\r\n\r\n"
    assert {:ok, ^state} = Logic.process_request(request, state)
  end

  test "parse invalid request returns Bad Request", %{state: state} do
    mock(:gen_tcp, [send: 2], fn %{}, response ->
      assert {:ok, %Response{status: 400}} = Response.parse(response)
    end)

    request = "OPTIONS rtsp://localhost:554/stream RTSP\r\n"
    assert {:ok, ^state} = Logic.process_request(request, state)
  end
end
