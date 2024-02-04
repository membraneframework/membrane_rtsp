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

  alpha_num = ascii_string([?0..?9, ?a..?z, ?A..?Z, ?-, ?_], min: 1)
  space = ascii_string([?\s, ?\t, ?\f], min: 1)
  delimeter = choice(Enum.map(["\r\n", "\r", "\n"], &string/1))

  ignored_space = ignore(space)
  ignored_delimeter = ignore(delimeter)

  methods = choice(Enum.map(@methods, &string/1))

  header =
    alpha_num
    |> ignore(string(":"))
    |> concat(ignored_space)
    |> utf8_string([{:not, ?\r}, {:not, ?\n}], min: 1)
    |> concat(ignored_delimeter)

  request_line =
    methods
    |> concat(ignored_space)
    |> utf8_string([{:not, ?\s}], min: 1)
    |> concat(ignored_space)
    |> ignore(string("RTSP/1.0"))
    |> concat(ignored_delimeter)

  headers = header |> times(min: 0) |> post_traverse(:parse_headers)

  defparsec :parse_request,
            request_line
            |> optional(headers)
            |> concat(ignored_delimeter)
            |> optional(utf8_string([], min: 1))
            |> eos()

  # Parse Transport header
  transport_param_value = utf8_string([{:not, ?\0..?\s}, {:not, ?;}], min: 1)

  transport_dest_param =
    string("destination") |> optional(string("=") |> concat(transport_param_value))

  transport_value_param =
    choice(Enum.map(["ttl", "layers", "ssrc", "mode"], &string/1))
    |> string("=")
    |> concat(transport_param_value)

  transport_integer_params =
    choice(Enum.map(["port", "client_port", "server_port", "interleaved"], &string/1))
    |> string("=")
    |> integer(min: 1)
    |> optional(ignore(string("-")) |> integer(min: 1))

  transport_params =
    ignore(string(";"))
    |> choice([
      string("append"),
      transport_dest_param,
      transport_value_param,
      transport_integer_params
    ])
    |> post_traverse(:map_transport_params)
    |> times(min: 1)

  defparsec :parse_transport_header,
            string("RTP/AVP")
            |> ignore()
            |> optional(ignore(string("/")) |> choice([string("TCP"), string("UDP")]))
            |> ignore(string(";"))
            |> choice([string("unicast"), string("multicast")])
            |> optional(transport_params)
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

  defp map_transport_params(rest, args, context, _line, _offset) do
    new_value =
      case Enum.reverse(args) do
        [key] -> {key, nil}
        [key, "=", value] when is_binary(value) -> {key, value}
        [key, "=", value] -> {key, {value, value + 1}}
        [key, "=", min_value, max_value] -> {key, {min_value, max_value}}
      end

    {rest, [new_value], context}
  end
end
