defmodule Membrane.RTSP.UserAgentTest do
  @moduledoc """
  membrane_core#1205: at least one camera firmware answers every request that carries
  the default User-Agent with 503 and accepts the same request under another name.
  """
  use ExUnit.Case, async: true

  alias Membrane.RTSP

  defp user_agent_sent(options) do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen_socket)

    {:ok, session} =
      RTSP.start_link("rtsp://localhost:#{port}/stream", [response_timeout: 1_000] ++ options)

    {:ok, server_socket} = :gen_tcp.accept(listen_socket, 1_000)

    task = Task.async(fn -> RTSP.options(session) end)
    {:ok, request} = :gen_tcp.recv(server_socket, 0, 1_000)
    :ok = :gen_tcp.send(server_socket, "RTSP/1.0 200 OK\r\nCSeq: 0\r\n\r\n")
    assert {:ok, %RTSP.Response{status: 200}} = Task.await(task)

    :gen_tcp.close(listen_socket)

    [_match, user_agent] = Regex.run(~r/\r\nUser-Agent: ([^\r]*)\r\n/, request)
    user_agent
  end

  test "is the library's own by default" do
    assert user_agent_sent([]) == RTSP.user_agent()
    assert RTSP.user_agent() =~ "MembraneRTSP/"
  end

  test "can be replaced with the :user_agent option" do
    assert user_agent_sent(user_agent: "LibVLC/3.0.20") == "LibVLC/3.0.20"
  end
end
