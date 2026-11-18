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

  # the two replies may arrive in one read or in two
  defp receive_from_client(server, timeout \\ 1_000) do
    case :gen_tcp.recv(server, 0, timeout) do
      {:ok, data} -> data
      {:error, :timeout} -> ""
    end
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

    test "a request arriving in one segment after the awaited response is answered", ctx do
      task = request(ctx.session)
      assert "OPTIONS " <> _rest = receive_from_client(ctx.server)

      :ok = :gen_tcp.send(ctx.server, "RTSP/1.0 200 OK\r\nCSeq: 0\r\n\r\n" <> @ping)
      assert {:ok, %RTSP.Response{status: 200}} = Task.await(task)
      assert receive_from_client(ctx.server) == @ping_reply
    end

    test "two requests arriving in one segment when no response is awaited are both answered",
         ctx do
      :ok = :gen_tcp.send(ctx.server, @ping <> String.replace(@ping, "CSeq: 77", "CSeq: 78"))

      assert receive_from_client(ctx.server) <> receive_from_client(ctx.server, 300) ==
               @ping_reply <> String.replace(@ping_reply, "CSeq: 77", "CSeq: 78")
    end

    test "a request arriving when no response is awaited is answered", ctx do
      :ok = :gen_tcp.send(ctx.server, @ping)
      assert receive_from_client(ctx.server) == @ping_reply
    end
  end

  describe "a session that reads the socket itself" do
    test "answers a request that arrives in two segments when no response is awaited", ctx do
      {first, second} = String.split_at(@ping, 30)

      :ok = :gen_tcp.send(ctx.server, first)
      Process.sleep(50)
      :ok = :gen_tcp.send(ctx.server, second)

      assert receive_from_client(ctx.server) == @ping_reply
    end

    test "gives up on a response when the server keeps sending something else", ctx do
      task = request(ctx.session)
      assert "OPTIONS " <> _rest = receive_from_client(ctx.server)

      # interleaved packets and no response, for twice the response timeout of 1 s
      server = ctx.server

      sender =
        Task.async(fn ->
          for _n <- 1..40 do
            :gen_tcp.send(server, <<"$", 0, 4::16, 1, 2, 3, 4>>)
            Process.sleep(50)
          end
        end)

      started = System.monotonic_time(:millisecond)
      assert {:error, :timeout} = Task.await(task, 3_000)
      assert System.monotonic_time(:millisecond) - started < 1_800
      Task.await(sender, 5_000)
    end

    test "stops when the socket reports an error", ctx do
      Process.flag(:trap_exit, true)
      session = ctx.session
      socket = RTSP.get_socket(session)

      capture_log(fn ->
        send(session, {:tcp_error, socket, :etimedout})
        assert_receive {:EXIT, ^session, {:socket_error, :etimedout}}, 1_000
      end)
    end

    test "survives a message that it does not know", ctx do
      log =
        capture_log(fn ->
          send(ctx.session, :something_else)
          assert is_port(RTSP.get_socket(ctx.session))
        end)

      assert log =~ "something_else"
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
