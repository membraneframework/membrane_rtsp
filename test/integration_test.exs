defmodule Membrane.Protocol.RTSP.IntegrationTest do
  use ExUnit.Case

  alias Membrane.Support.Factory.SampleOptionsRequest
  alias Membrane.Protocol.RTSP.Request

  test "Remove me" do
    query = SampleOptionsRequest.request() |> Request.to_string(SampleOptionsRequest.url())

    {:ok, socket} =
      :gen_tcp.connect("wowzaec2demo.streamlock.net" |> to_charlist(), 554, [
        :binary,
        {:active, false},
        {:keepalive, true}
      ])

    :gen_tcp.send(socket, query)

    assert {:ok, response} = :gen_tcp.recv(socket, 100)
  end
end
