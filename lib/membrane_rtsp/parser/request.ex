defmodule Membrane.RTSP.Parser.Request do
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

  space = ascii_string([?\s, ?\t], min: 1)
  delimiter = choice(Enum.map(["\r\n", "\r", "\n"], &string/1))

  method = choice(Enum.map(@methods, &string/1))
  request_uri = utf8_string([{:not, ?\s}, {:not, ?\t}], min: 1)
  rtsp_version = string("RTSP/1.0")

  request_line =
    method
    |> ignore(space)
    |> concat(request_uri)
    |> ignore(space)
    |> ignore(rtsp_version)
    |> ignore(delimiter)

  header_name = ascii_string([?0..?9, ?a..?z, ?A..?Z, ?-, ?_], min: 1)
  header_value = utf8_string([{:not, ?\r}, {:not, ?\n}], min: 1)

  header =
    header_name
    |> ignore(string(":"))
    |> ignore(space)
    |> concat(header_value)
    |> ignore(delimiter)

  headers = header |> times(min: 0) |> post_traverse(:parse_headers)
  body = utf8_string([], min: 1)

  defparsec :parse_request,
            request_line
            |> optional(headers)
            |> ignore(delimiter)
            |> optional(body)
            |> eos()

  # Private functions
  defp parse_headers(rest, args, context, _line, _offset) do
    headers =
      args
      |> Enum.reverse()
      |> Enum.chunk_every(2)
      |> Enum.map(fn [key, value] -> {key, value} end)

    {rest, [headers], context}
  end
end
