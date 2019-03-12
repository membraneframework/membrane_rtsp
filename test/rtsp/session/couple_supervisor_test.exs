defmodule Membrane.Protocol.RTSP.Session.CoupleSupervisorTest do
  use ExUnit.Case

  alias Membrane.Protocol.RTSP.{Transport, Session}
  alias Membrane.Protocol.RTSP.Session.CoupleSupervisor

  @parsed_uri %URI{
    authority: "domain.com:554",
    fragment: nil,
    host: "domain.com",
    path: "/vod/mp4:movie.mov",
    port: 554,
    query: nil,
    scheme: "rtsp",
    userinfo: nil
  }

  describe "Couple Supervisor when initializing" do
    test "returns correct spec when valid arguments were provided" do
      url = "rtsp://domain.com:554/vod/mp4:movie.mov"
      assert {:ok, {_, children_spec}} = CoupleSupervisor.init([Fake, url, []])

      assert [session_spec, transport_spec] = children_spec

      assert %{id: Session, start: {Session, :start_link, [Fake, ref, @parsed_uri, []]}} =
               session_spec

      assert %{id: Transport, start: {Transport, :start_link, [Fake, ^ref, @parsed_uri]}} =
               transport_spec

      assert String.ends_with?(ref, url)
    end

    test "returns an error if invalid uri is provided" do
      assert {:stop, :invalid_url} ==
               CoupleSupervisor.init([Fake, "rtsp://vod/mp4:movie.mov", []])
    end
  end
end
