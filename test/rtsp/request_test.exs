defmodule Membrane.Protocol.RTSP.RequestTest do
  use ExUnit.Case

  alias Membrane.Support.Factory
  alias Membrane.Protocol.RTSP.Request

  describe "Renders request properly" do
    test "for method OPTIONS" do
      assert Factory.SampleOptionsRequest.raw() ==
               Factory.SampleOptionsRequest.request()
               |> Request.to_string(Factory.SampleOptionsRequest.url())
    end
  end
end
