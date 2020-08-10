defmodule Membrane.RTSP.Transport.TCPSocketTest do
  use ExUnit.Case
  import Mockery
  import Mockery.Assertions
  alias Membrane.RTSP.Transport.TCPSocket

  setup do
    state = %TCPSocket.State{
      connection_info: %URI{
        port: 4000,
        host: "test.com",
        path: "/"
      },
      caller: nil,
      connection_timeout: 500
    }

    [state: state]
  end

  describe "Pipeable TCP Socket does" do
    test "consume connection info and produces state" do
      mock(:gen_tcp, [connect: 4], fn _, _, _, _ -> {:ok, :super_port} end)

      uri = %URI{
        host: "wowzaec2demo.streamlock.net",
        path: "/vod/mp4:BigBuckBunny_115k.mov",
        port: 554
      }

      info = %{
        uri: uri,
        options: []
      }

      assert {:ok,
              %TCPSocket.State{
                connection: :super_port,
                connection_info: ^uri,
                caller: nil
              }} = TCPSocket.init(info)
    end

    test "open new connection if one present in state is dead", %{state: state} do
      mock(:gen_tcp, [connect: 4], fn _, _, _, _ -> {:ok, :super_port} end)
      mock(:gen_tcp, [send: 2], :ok)

      assert {:noreply,
              %Membrane.RTSP.Transport.TCPSocket.State{
                connection: conn,
                caller: caller
              }} = TCPSocket.handle_call({:execute, "123"}, self(), state)

      assert_called(:gen_tcp, :connect)
      assert caller == self()
    end

    test "uses already open connection if possible", %{state: state} do
      mock(:gen_tcp, [send: 2], :ok)
      state = %TCPSocket.State{state | connection: :stub}

      assert {:noreply, result_state} = TCPSocket.handle_call({:execute, "123"}, self(), state)

      assert %Membrane.RTSP.Transport.TCPSocket.State{
               connection: conn,
               caller: caller
             } = result_state

      refute_called(:gen_tco, :connect)
      assert caller == self()
    end

    test "marks connection as dead when when received tcp_closed message", %{state: state} do
      assert {:noreply, %TCPSocket.State{connection: nil}} =
               TCPSocket.handle_info({:tcp_closed, :socket}, state)
    end

    test "replies to most recent sender when received tcp message", %{state: state} do
      sample = "RTSP/1.0 200 OK"
      self_client = {self(), :tag}
      state = %{state | caller: self_client}
      assert {:noreply, state} = TCPSocket.handle_info({:tcp, :socket, sample}, state)
      assert state = %TCPSocket.State{state | connection: nil}
      assert_received {:tag, {:ok, ^sample}}
    end

    test "does return an error if connection can't be made", %{state: state} do
      mock(:gen_tcp, [connect: 4], {:error, :etimedout})

      assert {:reply, {:error, :etimedout}, _} =
               TCPSocket.handle_call({:execute, "123"}, self(), state)
    end

    test "does return an error if message couldn't be sent", %{state: state} do
      mock(:gen_tcp, [send: 2], {:error, :closed})
      state = %TCPSocket.State{state | connection: self()}

      assert {:reply, {:error, :closed}, result_state} =
               TCPSocket.handle_call({:execute, "123"}, self(), state)
    end
  end
end
