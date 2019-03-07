defmodule Membrane.Protocol.RTSP.TransportTest do
  use ExUnit.Case

  alias Membrane.Protocol.RTSP.Transport
  alias Membrane.Protocol.RTSP.Transport.Fake

  test "Transport process registers self immediately" do
    unique_ref = "12332313123123rtsp://magicklink.compile"

    info = %URI{
      host: "wowzaec2demo.streamlock.net",
      path: "/vod/mp4:BigBuckBunny_115k.mov",
      port: 554
    }

    {:ok, pid} = Transport.start_link(Fake, unique_ref, info)
    assert [unique_ref] == Registry.keys(TransportRegistry, pid)
  end
end
