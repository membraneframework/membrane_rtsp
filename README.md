# Membrane Protocol RTSP

RTSP client for elixir.

Currently supports only RTSP 1.1 defined by
[RFC2326](https://tools.ietf.org/html/rfc2326)

## Usage

To use Membrane Protocol RTSP client you must first start a session:

```elixir
alias Membrane.Protocol.RTSP

{:ok, session} = RTSP.start("rtsp://domain.name:port/path")
```

Then you can proceed with executing requests:

```elixir
alias Membrane.Protocol.RTSP.Response

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

Session is closed with system shutdown or by calling:

```elixir
RTSP.close(session)
```

## Implementing custom transport layer

To implement custom request execution logic you must implement
`Membrane.Protocol.RTSP.Transport` behaviour. Then you can pass
the name of your transport module to `Membrane.Protocol.RTSP.start/3` as
a second argument.

`Membrane.Protocol.RTSP.start/3` assumes that transport module also implements
GenServer behaviour.

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

## External tests

Tests that use external RTSP service are disabled by default but they are present
in the codebase. They are tagged as external and are usually accompanied by
tests that mimic they behaviour by using predefined responses.

## Copyright and License

Copyright 2019, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://membraneframework.github.io/static/logo/swm_logo_readme.png)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)