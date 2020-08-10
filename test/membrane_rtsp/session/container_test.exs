defmodule Membrane.RTSP.Session.ContainerTest do
  use ExUnit.Case

  alias Membrane.RTSP.{Session, Transport}

  @parsed_uri %URI{
    authority: "domain.com:554",
    host: "domain.com",
    path: "/vod/mp4:movie.mov",
    port: 554,
    scheme: "rtsp"
  }

  describe "Session Container" do
    test "when initializing returns correct spec when valid arguments were provided" do
      ref = "magic_ref"
      transport = Transport.new(Fake, ref)
      assert {:ok, {_, children_spec}} = Session.Container.init([transport, @parsed_uri, []])
      assert [session_spec, transport_spec] = children_spec

      assert %{
               id: Session.Manager,
               start: {Session.Manager, :start_link, [^transport, @parsed_uri, _options]}
             } = session_spec

      assert %{
               id: Transport,
               start: {Transport, :start_link, [^transport, @parsed_uri, _options]}
             } = transport_spec
    end

    test "start_link returns an error if invalid uri is provided" do
      assert {:error, :invalid_url} ==
               Session.Container.start_link(Fake, "rtsp://vod/mp4:movie.mov", [])
    end
  end
end
