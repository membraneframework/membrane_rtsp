defmodule Membrane.RTSP.Response do
  use Bunch
  defstruct [:status, :headers, :body, :version]

  @start_line_regex ~r/^RTSP\/(\d\.\d) (\d\d\d) [A-Z ]+$/

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: [{binary(), binary()}],
          body: any()
        }

  @spec parse(binary()) :: {:ok, t()} | {:error, :invalid_start_line | :invalid_status_code}
  def parse(response) do
    {%__MODULE__{}, response}
    |> parse_start_line()
    ~>> ({:ok, result} -> parse_headers(result))
    ~>> ({:ok, result} -> parse_body(result))
  end

  defp parse_start_line({response, binary}) do
    [line, rest] = split_next_chunk(binary)

    case Regex.run(@start_line_regex, line) do
      [_, version, code] ->
        case Integer.parse(code) do
          :error ->
            {:error, :invalid_status_code}

          {code, _} when is_number(code) ->
            %__MODULE__{response | version: version, status: code}
            ~> {:ok, {&1, rest}}
        end

      _ ->
        {:error, :invalid_start_line}
    end
  end

  defp parse_headers(data, acc \\ [])

  defp parse_headers({response, "\r\n" <> rest}, acc) do
    acc
    |> Enum.into(%{})
    ~> %__MODULE__{response | headers: &1}
    ~> {:ok, {&1, rest}}
  end

  defp parse_headers({response, binary}, acc) do
    [line, rest] = split_next_chunk(binary)

    case String.split(line, ":", parts: 2) |> IO.inspect() do
      [name, " " <> value | []] -> parse_headers({response, rest}, [{name, value} | acc])
      _ -> {:error, {:malformed_header, line}}
    end
  end

  defp parse_body({%__MODULE__{headers: headers} = response, data}) do
    case headers["Content-Type"] do
      "application/sdp" ->
        # TODO use this
        # parsed = SDPParser.parse(data)
        # IO.inspect(parsed, label: "Parsuje sdp")
        IO.inspect(data)
        {:ok, %__MODULE__{response | body: data}}

      _ ->
        {:ok, %__MODULE__{response | body: data}}
    end
  end

  defp split_next_chunk(response), do: String.split(response, "\r\n", parts: 2)
end
