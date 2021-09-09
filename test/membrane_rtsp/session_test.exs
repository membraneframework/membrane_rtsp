defmodule Membrane.RTSP.SessionTest do
  use ExUnit.Case

  alias Membrane.RTSP
  alias Membrane.RTSP.{Session, Transport}

  describe "Session" do
    test "start fails if uri is not valid" do
      assert {:error, :invalid_url} = Session.start_link("invalid uri")
    end

    test "start fails when server can not be reached" do
      assert {:error, :nxdomain} = Session.start_link("rtsp://non.existent.domain.com:444")
    end
  end
end
