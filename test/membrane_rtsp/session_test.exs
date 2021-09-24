defmodule Membrane.RTSPTest do
  use ExUnit.Case

  alias Membrane.RTSP

  describe "Session" do
    test "start fails if uri is not valid" do
      assert {:error, :invalid_url} = RTSP.start_link("invalid uri")
    end

    test "start fails when server can not be reached" do
      assert {:error, :nxdomain} = RTSP.start_link("rtsp://non.existent.domain.com:444")
    end
  end
end
