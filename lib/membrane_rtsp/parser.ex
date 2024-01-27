defmodule Membrane.RTSP.Parser do
  @moduledoc false

  import NimbleParsec

  @methods [
    "DESCRIBE",
    "ANNOUNCE",
    "GET_PARAMETER",
    "OPTIONS",
    "PAUSE",
    "PLAY",
    "RECORD",
    "REDIRECT",
    "SETUP",
    "SET_PARAMETER",
    "TEARDOWN"
  ]

  defcombinatorp :space, ascii_char([?\s, ?\t]) |> times(min: 1)
  defcombinatorp :method, choice(Enum.map(@methods, &string/1))

  defcombinatorp :header,
                 ascii_string([?a..?z, ?A..?Z, ?-], min: 1)
                 |> ignore(ascii_char([?:]))
                 |> ignore(parsec(:space))
                 |> utf8_string([{:not, ?\r}], min: 1)
                 |> ignore(string("\r\n"))

  request_line =
    parsec(:method)
    |> ignore(times(string(" "), min: 1))
    |> utf8_string([{:not, ?\s}], min: 1)
    |> ignore(times(string(" "), min: 1))
    |> ignore(string("RTSP/1.0"))
    |> ignore(string("\r\n"))

  headers = parsec(:header) |> times(min: 1) |> post_traverse(:parse_headers)
  body = utf8_string([{:not, ?\r}], min: 1) |> ignore(string("\r\n"))

  defparsec :parse_request,
            request_line
            |> times(headers, min: 0)
            |> optional(body)
            |> ignore(string("\r\n"))

  defp parse_headers(rest, args, context, _line, _offset) do
    headers =
      args
      |> Enum.reverse()
      |> Enum.chunk_every(2)
      |> Enum.map(fn [key, value] -> {key, value} end)

    {rest, [headers], context}
  end
end
