defmodule Membrane.Support.Factory.SampleOptionsRequest do
  @moduledoc false
  alias Membrane.Protocol.RTSP.Request

  @external_resource "test/support/fixtures/options_request.bin"
  @spec raw() :: binary()
  def raw, do: "test/support/fixtures/options_request.bin" |> File.read!()

  @spec method() :: binary()
  def method, do: "OPTIONS"

  @spec url() :: URI.t()
  def url,
    do: "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov" |> URI.parse()

  @spec headers() :: [{binary(), binary()}]
  def headers,
    do: [
      {"CSeq", "2"},
      {"User-Agent", "LibVLC/3.0.4 (LIVE555 Streaming Media v2016.11.28)"}
    ]

  @spec request() :: Membrane.Protocol.RTSP.Request.t()
  def request,
    do: %Request{
      method: method(),
      headers: headers()
    }
end
