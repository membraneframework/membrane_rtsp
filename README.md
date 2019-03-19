# Membrane Protocol RTSP

RTSP client for elixir.

Currently supports only RTSP 1.1 defined by
[RFC2326](https://tools.ietf.org/html/rfc2326)

## Usage

To use Membrane Protocol RTSP client you must first start a session:

```elixir
{:ok, session} = RTSP.start("rtsp://domain.name:port/path")
```

Then you can proceed with executing requests:

```elixir
{:ok, %Response{status: 200}} = RTSP.describe(session)

{:ok, %Response{status: 200}} =
  RTSP.setup(session, "/trackID=1", [
    {"Transport", "RTP/AVP;unicast;client_port=57614-57615"}
  ])

{:ok, %Response{status: 200}} =
  RTSP.setup(session, "/trackID=2", [
    {"Transport", "RTP/AVP;unicast;client_port=52614-52615"}
  ])

{:ok, %Response{status: 200}} = RTSP.play(session)
```

## Implementing custom transport layer

To implement custom request execution logic you must implement
`Membrane.Protocol.RTSP.Transport` behaviour. Then you can pass
name of your transport module to `RTSP.start/3` as second argument.

`RTSP.start/3` assumes that transport module also implements GenServer
behaviour.

## Installation

The package can be installed by adding `membrane_rtsp` to your list 
of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_rtsp, "~> 0.1.0"}
  ]
end
```

The docs can be found at [https://hexdocs.pm/membrane_protocol_rtsp](https://hexdocs.pm/membrane_protocol_rtsp).

