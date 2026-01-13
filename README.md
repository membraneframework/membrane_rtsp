# Membrane RTSP

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtsp.svg)](https://hex.pm/packages/membrane_rtsp)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtsp/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_rtsp.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_rtsp)


The RTSP client and server for Elixir

Currently supports only RTSP 1.0 defined by
[RFC2326](https://tools.ietf.org/html/rfc2326)

## Installation

The package can be installed by adding `membrane_rtsp` to your list
of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_rtsp, "~> 0.12.0"}
  ]
end
```

## Usage

To use the Membrane RTSP client you must first start a session:

```elixir
{:ok, session} = Membrane.RTSP.start_link("rtsp://domain.name:port/path")
```

Then you can proceed with executing requests:

```elixir
alias Membrane.RTSP
alias Membrane.RTSP.Response

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

If you started a session without linking it, it is advised to close it manually
by calling:

```elixir
RTSP.close(session)
```

## External tests

Tests that use external RTSP service are disabled by default but they are present
in the codebase. They are tagged as external and are usually accompanied by
tests that mimic their behavior by using predefined responses.

## Copyright and License

Copyright 2019, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
