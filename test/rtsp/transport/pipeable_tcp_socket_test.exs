defmodule Membrane.Protocol.RTSP.Transport.PipeableTCPSocketTest do
  use ExUnit.Case
  import Mockery
  import Mockery.Assertions
  alias Membrane.Protocol.RTSP.Transport.PipeableTCPSocket

  setup do
    state = %PipeableTCPSocket.State{
      connection_info: %URI{
        port: 4000,
        host: "test.com",
        path: "/"
      },
      caller: nil
    }

    [state: state]
  end

  describe "Pipeable TCP Socket does" do
    test "consume connection info and produces state" do
      info = %URI{
        host: "wowzaec2demo.streamlock.net",
        path: "/vod/mp4:BigBuckBunny_115k.mov",
        port: 554
      }

      assert PipeableTCPSocket.init(info) ==
               {:ok,
                %PipeableTCPSocket.State{
                  connection: nil,
                  connection_info: info,
                  caller: nil
                }}
    end

    test "open new connection if one present in state is dead", %{state: state} do
      mock(:gen_tcp, [connect: 3], fn _, _, _ -> {:ok, :super_port} end)
      mock(:gen_tcp, [send: 2], :ok)

      assert {:noreply,
              %Membrane.Protocol.RTSP.Transport.PipeableTCPSocket.State{
                connection: conn,
                caller: caller
              }} = PipeableTCPSocket.handle_call({:execute, "123"}, self(), state)

      assert_called(:gen_tcp, :connect)
      assert caller == self()
    end

    test "uses already open connection if possible", %{state: state} do
      mock(:gen_tcp, [send: 2], :ok)
      state = %PipeableTCPSocket.State{state | connection: :stub}

      assert {:noreply, result_state} =
               PipeableTCPSocket.handle_call({:execute, "123"}, self(), state)

      assert %Membrane.Protocol.RTSP.Transport.PipeableTCPSocket.State{
               connection: conn,
               caller: caller
             } = result_state

      refute_called(:gen_tco, :connect)
      assert caller == self()
    end

    test "marks connection as dead when when received tcp_closed message", %{state: state} do
      assert {:noreply, %PipeableTCPSocket.State{connection: nil}} =
               PipeableTCPSocket.handle_info({:tcp_closed, :socket}, state)
    end

    test "replies to most recent sender when received tcp message", %{state: state} do
      sample = "RTSP/1.0 200 OK"
      self_client = {self(), :tag}
      state = %{state | caller: self_client}
      assert {:noreply, state} = PipeableTCPSocket.handle_info({:tcp, :socket, sample}, state)
      assert state = %PipeableTCPSocket.State{state | connection: nil}
      assert_received {:tag, {:ok, ^sample}}
    end

    test "does return an error if connection can't be made", %{state: state} do
      mock(:gen_tcp, [connect: 3], {:error, :etimedout})

      assert {:reply, {:error, :etimedout}, _} =
               PipeableTCPSocket.handle_call({:execute, "123"}, self(), state)
    end

    test "does return an error if message couldn't be sent", %{state: state} do
      mock(:gen_tcp, [send: 2], {:error, :closed})
      state = %PipeableTCPSocket.State{state | connection: self()}

      assert {:reply, {:error, :closed}, result_state} =
               PipeableTCPSocket.handle_call({:execute, "123"}, self(), state)
    end
  end

  describe "Pipeable TCP Socket when terminating" do
    test "closes open connection", %{state: state} do
      mock(:gen_tcp, :close, :ok)
      state = %PipeableTCPSocket.State{state | connection: :connection}

      assert :ok == PipeableTCPSocket.terminate(:shutdown, state)
      assert_called(:gen_tcp, :close, [:connection])
    end

    test "ignores closed connection", %{state: state} do
      state = %PipeableTCPSocket.State{state | connection: nil}
      assert :ok == PipeableTCPSocket.terminate(:shutdown, state)
    end
  end
end
