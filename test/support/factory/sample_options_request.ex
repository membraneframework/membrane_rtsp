defmodule Membrane.Support.Factory.SampleOptionsRequest do
  alias Membrane.Protocol.RTSP.Request

  @external_resource "test/support/fixtures/options_request.bin"
  def raw, do: "test/support/fixtures/options_request.bin" |> File.read!()
  def method, do: "OPTIONS"

  def url,
    do: "rtsp://wowzaec2demo.streamlock.net:554/vod/mp4:BigBuckBunny_115k.mov" |> URI.parse()

  def headers,
    do: [
      {"CSeq", 2},
      {"User-Agent", "LibVLC/3.0.4 (LIVE555 Streaming Media v2016.11.28)"}
    ]

  def request,
    do: %Request{
      method: method(),
      headers: headers(),
      body: nil
    }
end
