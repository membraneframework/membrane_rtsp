defmodule Membrane.Protocol.RTSP.SessionTest do
  use ExUnit.Case

  alias Membrane.Protocol.RTSP.{Session, Transport}

  describe "Session" do
    test "start fails if uri is not valid" do
      assert {:error, :invalid_url} = Session.start("invalid uri")
    end

    test "start fails when server can not be reached" do
      assert {:error, reason} = Session.start("rtsp://non.existent.domain.com:444")
      assert reason == {:shutdown, {:failed_to_start_child, Transport, :timeout}}
    end
  end
end
