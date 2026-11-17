defmodule Membrane.RTSP.ServerRequestTest do
  @moduledoc """
  A server may send requests of its own on the client's connection. RFC 2326 allows
  OPTIONS, GET_PARAMETER, SET_PARAMETER, ANNOUNCE and REDIRECT in that direction, and
  some servers use the first three to check that the client is still there.
  libavformat and GStreamer answer them; a client that does not may be disconnected.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Membrane.RTSP

  @ping "GET_PARAMETER rtsp://localhost/stream RTSP/1.0\r\nCSeq: 77\r\nSession: abc\r\n\r\n"
  @ping_reply "RTSP/1.0 200 OK\r\nCSeq: 77\r\nSession: abc\r\n\r\n"

  setup do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen_socket)

    {:ok, session} = RTSP.start_link("rtsp://localhost:#{port}/stream", response_timeout: 1_000)
    {:ok, server_socket} = :gen_tcp.accept(listen_socket, 1_000)

    on_exit(fn -> :gen_tcp.close(listen_socket) end)

    [session: session, server: server_socket]
  end

  defp request(session) do
    Task.async(fn -> RTSP.options(session) end)
  end

  defp receive_from_client(server) do
    {:ok, data} = :gen_tcp.recv(server, 0, 1_000)
    data
  end

  describe "while the session reads the socket itself" do
    test "a request arriving before the awaited response is answered", ctx do
      task = request(ctx.session)
      assert "OPTIONS " <> _rest = receive_from_client(ctx.server)

      :ok = :gen_tcp.send(ctx.server, @ping)
      assert receive_from_client(ctx.server) == @ping_reply

      :ok = :gen_tcp.send(ctx.server, "RTSP/1.0 200 OK\r\nCSeq: 0\r\n\r\n")
      assert {:ok, %RTSP.Response{status: 200}} = Task.await(task)
    end

    test "a request arriving in one segment with the awaited response is answered", ctx do
      task = request(ctx.session)
      assert "OPTIONS " <> _rest = receive_from_client(ctx.server)

      :ok =
        :gen_tcp.send(ctx.server, @ping <> "RTSP/1.0 200 OK\r\nCSeq: 0\r\nPublic: PLAY\r\n\r\n")

      assert receive_from_client(ctx.server) == @ping_reply

      assert {:ok, %RTSP.Response{status: 200} = response} = Task.await(task)
      assert RTSP.Response.get_header(response, "Public") == {:ok, "PLAY"}
    end

    test "a request with a body is consumed whole", ctx do
      task = request(ctx.session)
      assert "OPTIONS " <> _rest = receive_from_client(ctx.server)

      :ok =
        :gen_tcp.send(
          ctx.server,
          "SET_PARAMETER rtsp://localhost/stream RTSP/1.0\r\nCSeq:5\r\nContent-Length: 10\r\n\r\nping: now\n"
        )

      assert receive_from_client(ctx.server) == "RTSP/1.0 200 OK\r\nCSeq: 5\r\n\r\n"

      :ok = :gen_tcp.send(ctx.server, "RTSP/1.0 200 OK\r\nCSeq: 0\r\n\r\n")
      assert {:ok, %RTSP.Response{status: 200}} = Task.await(task)
    end

    test "a request the client does not implement is refused with 501", ctx do
      task = request(ctx.session)
      assert "OPTIONS " <> _rest = receive_from_client(ctx.server)

      log =
        capture_log(fn ->
          :ok =
            :gen_tcp.send(
              ctx.server,
              "REDIRECT rtsp://localhost/stream RTSP/1.0\r\nCSeq: 9\r\n\r\n"
            )

          assert receive_from_client(ctx.server) ==
                   "RTSP/1.0 501 Not Implemented\r\nCSeq: 9\r\n\r\n"

          :ok = :gen_tcp.send(ctx.server, "RTSP/1.0 200 OK\r\nCSeq: 0\r\n\r\n")
          assert {:ok, %RTSP.Response{status: 200}} = Task.await(task)
        end)

      assert log =~ "REDIRECT"
    end

    test "a request arriving when no response is awaited is answered", ctx do
      :ok = :gen_tcp.send(ctx.server, @ping)
      assert receive_from_client(ctx.server) == @ping_reply
    end
  end

  describe "while another process reads the socket" do
    setup ctx do
      :ok = RTSP.transfer_socket_control(ctx.session, self())
      :ok
    end

    test "a request handed over before the awaited response is answered", ctx do
      task = request(ctx.session)
      assert "OPTIONS " <> _rest = receive_from_client(ctx.server)

      :ok = RTSP.handle_response(ctx.session, @ping)
      assert receive_from_client(ctx.server) == @ping_reply

      :ok = RTSP.handle_response(ctx.session, "RTSP/1.0 200 OK\r\nCSeq: 0\r\n\r\n")
      assert {:ok, %RTSP.Response{status: 200}} = Task.await(task)
    end

    test "a request handed over when no response is awaited is answered", ctx do
      :ok = RTSP.handle_response(ctx.session, @ping)
      assert receive_from_client(ctx.server) == @ping_reply
    end

    test "a response nobody waits for is dropped without crashing the session", ctx do
      log =
        capture_log(fn ->
          :ok = RTSP.handle_response(ctx.session, "RTSP/1.0 200 OK\r\nCSeq: 41\r\n\r\n")

          # the session is still there and still works
          task = request(ctx.session)
          assert "OPTIONS " <> _rest = receive_from_client(ctx.server)
          :ok = RTSP.handle_response(ctx.session, "RTSP/1.0 200 OK\r\nCSeq: 0\r\n\r\n")
          assert {:ok, %RTSP.Response{status: 200}} = Task.await(task)
        end)

      assert log =~ "CSeq: 41"
    end
  end
end
