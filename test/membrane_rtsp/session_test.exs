defmodule Membrane.RTSP.SessionTest do
  use ExUnit.Case

  alias Membrane.RTSP
  alias Membrane.RTSP.{Session, Transport}

  setup_all do
    {:ok, supervisor} = RTSP.Supervisor.start_link()
    [supervisor: supervisor]
  end

  describe "Session" do
    test "start fails if uri is not valid", %{supervisor: supervisor} do
      assert {:error, :invalid_url} = Session.new(supervisor, "invalid uri")
    end

    test "start fails when server can not be reached", %{supervisor: supervisor} do
      assert {:error, reason} = Session.new(supervisor, "rtsp://non.existent.domain.com:444")
      assert reason == {:shutdown, {:failed_to_start_child, Transport, :nxdomain}}
    end
  end
end
