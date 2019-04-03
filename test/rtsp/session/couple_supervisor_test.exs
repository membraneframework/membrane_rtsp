defmodule Membrane.Protocol.RTSP.Session.CoupleSupervisorTest do
  use ExUnit.Case

  alias Membrane.Protocol.RTSP.{Session, Transport}
  alias Membrane.Protocol.RTSP.Session.CoupleSupervisor

  @parsed_uri %URI{
    authority: "domain.com:554",
    host: "domain.com",
    path: "/vod/mp4:movie.mov",
    port: 554,
    scheme: "rtsp"
  }

  describe "Couple Supervisor " do
    test "when initializing returns correct spec when valid arguments were provided" do
      ref = "magic_ref"
      transport = Transport.new(Fake, ref)
      assert {:ok, {_, children_spec}} = CoupleSupervisor.init([transport, @parsed_uri, []])
      assert [session_spec, transport_spec] = children_spec

      assert %{id: Session, start: {Session, :start_link, [^transport, @parsed_uri, []]}} =
               session_spec

      assert %{id: Transport, start: {Transport, :start_link, [^transport, @parsed_uri]}} =
               transport_spec
    end

    test "start_link returns an error if invalid uri is provided" do
      assert {:stop, :invalid_url} ==
               CoupleSupervisor.start_link(Fake, "rtsp://vod/mp4:movie.mov", [])
    end
  end
end
