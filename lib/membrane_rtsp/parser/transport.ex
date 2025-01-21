defmodule Membrane.RTSP.Parser.Transport do
  @moduledoc false

  import NimbleParsec

  lower_transport = ignore(string("/")) |> choice([string("TCP"), string("UDP")])
  mode = ignore(string(";")) |> choice([string("unicast"), string("multicast")])

  param_value = utf8_string([{:not, ?\0..?\s}, {:not, ?;}, {:not, ?,}], min: 1)

  optional_value_param =
    string("destination")
    |> optional(string("=") |> concat(param_value))

  single_value_param =
    choice(Enum.map(["ssrc", "source"], &string/1))
    |> string("=")
    |> concat(param_value)

  play_mode = to_charlist("PLAY") |> Enum.reduce(empty(), &ascii_char(&2, [&1, &1 + 32]))
  record_mode = to_charlist("RECORD") |> Enum.reduce(empty(), &ascii_char(&2, [&1, &1 + 32]))
  mode_param = string("mode") |> string("=") |> choice([play_mode, record_mode])

  integer_value_param =
    choice(Enum.map(["ttl", "layers"], &string/1))
    |> string("=")
    |> integer(min: 1, max: 3)

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
      mode_param,
      single_value_param,
      integer_value_param,
      integer_range_param
    ])
    |> post_traverse(:map_transport_param)
    |> times(min: 1)

  defparsec :parse_transport_header,
            ignore(string("RTP/AVP"))
            |> optional(lower_transport)
            |> post_traverse(:maybe_inject_transport_default_value)
            |> optional(mode)
            |> post_traverse(:maybe_inject_mode_default_value)
            |> optional(parameters)
            |> eos()

  defp map_transport_param(rest, args, context, _line, _offset) do
    new_value =
      case Enum.reverse(args) do
        [key] -> {key, nil}
        [key, "=", value] when is_binary(value) or key in ["ttl", "layers"] -> {key, value}
        ["mode", "=" | value] -> {"mode", to_string(value)}
        [key, "=", value] -> {key, {value, value + 1}}
        [key, "=", min_value, max_value] -> {key, {min_value, max_value}}
      end

    {rest, [new_value], context}
  end

  defp maybe_inject_transport_default_value(rest, args, context, _line, _offset) do
    case args do
      [] -> {rest, ["UDP"], context}
      args -> {rest, args, context}
    end
  end

  defp maybe_inject_mode_default_value(rest, args, context, _line, _offset) do
    case args do
      [mode | _rest] = args when mode in ["unicast", "multicast"] -> {rest, args, context}
      _other -> {rest, ["multicast" | args], context}
    end
  end
end
