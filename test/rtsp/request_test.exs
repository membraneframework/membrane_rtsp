defmodule Membrane.RTSP.RequestTest do
  use ExUnit.Case

  alias Membrane.Support.Factory

  describe "Renders request properly" do
    test "for method OPTIONS" do
      assert Factory.SampleOptionsRequest.raw() ==
               Factory.SampleOptionsRequest.request() |> String.Chars.to_string()
    end
  end
end
