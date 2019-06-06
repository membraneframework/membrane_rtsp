# Membrane Protocol RTSP

Elixir RTSP client.

Currently supports only RTSP 1.1 defined by
[RFC2326](https://tools.ietf.org/html/rfc2326)

## Usage

To use Membrane Protocol RTSP client you must first start a session by calling
either:

```elixir
alias Membrane.Protocol.RTSP

# It will exit if Session can't be started
{:ok, session} = RTSP.Session.start_link("rtsp://domain.name:port/path")
# OR
# Requires you to start under Supervision tree providing Supervisor
{:ok, session} = RTSP.Session.new(supervisor, "rtsp://domain.name:port/path")
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

If you started session without linking it, it is advised to close it manually
by calling:

```elixir
RTSP.close(supervisor, session)
```

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

The docs can be found at [HexDocs](https://hexdocs.pm/membrane_protocol_rtsp).

## Implementing custom transport layer

To implement custom request execution logic you must implement
`Membrane.Protocol.RTSP.Transport` behavior. Then you can pass
the name of your transport module to `Membrane.Protocol.RTSP.Session.new/4`.

`Membrane.Protocol.RTSP.Session.new/4` assumes that the transport module also
implements GenServer behavior.

## Architecture

`Session` consists of two processes: `Manager` and `Transport`.

`Manager` is responsible for tracking `CSeq` header and `SessionId` and
`Transport` is responsible for transmitting the request and receiving a response.
We don't want `Manager` to die when `Transport` dies and vice versa, so they are
started together using `Container` which allows starting and stopping them as
one.

## External tests

Tests that use external RTSP service are disabled by default but they are present
in the codebase. They are tagged as external and are usually accompanied by
tests that mimic their behavior by using predefined responses.

## Copyright and License

Copyright 2019, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://membraneframework.github.io/static/logo/swm_logo_readme.png)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)