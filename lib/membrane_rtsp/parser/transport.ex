defmodule Membrane.RTSP.Parser.Transport do
  @moduledoc false

  import NimbleParsec

  lower_transport = ignore(string("/")) |> choice([string("TCP"), string("UDP")])
  mode = choice([string("unicast"), string("multicast")])

  param_value = utf8_string([{:not, ?\0..?\s}, {:not, ?;}, {:not, ?,}], min: 1)

  optional_value_param =
    string("destination")
    |> optional(string("=") |> concat(param_value))

  single_value_param =
    choice(Enum.map(["ttl", "layers", "ssrc", "mode", "source"], &string/1))
    |> string("=")
    |> concat(param_value)

  integer_range_param =
    choice(Enum.map(["port", "client_port", "server_port", "interleaved"], &string/1))
    |> string("=")
    |> integer(min: 1)
    |> optional(ignore(string("-")) |> integer(min: 1))

  parameters =
    ignore(string(";"))
    |> choice([
      string("append"),
      optional_value_param,
      single_value_param,
      integer_range_param
    ])
    |> post_traverse(:map_transport_param)
    |> times(min: 1)

  defparsec :parse_transport_header,
            string("RTP/AVP")
            |> ignore()
            |> optional(lower_transport)
            |> ignore(string(";"))
            |> concat(mode)
            |> optional(parameters)
            |> eos()

  defp map_transport_param(rest, args, context, _line, _offset) do
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
