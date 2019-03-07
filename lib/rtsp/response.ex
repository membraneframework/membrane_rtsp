defmodule Membrane.Protocol.RTSP.Response do
  use Bunch
  defstruct [:status, :headers, :body, :version]

  alias Membrane.Protocol.SDP

  @start_line_regex ~r/^RTSP\/(\d\.\d) (\d\d\d) [A-Z a-z]+$/

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: [{binary(), binary()}],
          body: any()
        }

  @spec parse(binary()) :: {:ok, t()} | {:error, atom()}
  def parse(response) do
    with {:ok, result} <- {%__MODULE__{}, response} |> parse_start_line(),
         {:ok, result} <- parse_headers(result) do
      parse_body(result)
    end
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
    |> Enum.reverse()
    ~> %__MODULE__{response | headers: &1}
    ~> {:ok, {&1, rest}}
  end

  defp parse_headers({response, binary}, acc) do
    [line, rest] = split_next_chunk(binary)

    case String.split(line, ":", parts: 2) do
      [name, " " <> value | []] -> parse_headers({response, rest}, [{name, value} | acc])
      _ -> {:error, {:malformed_header, line}}
    end
  end

  defp parse_body({%__MODULE__{headers: headers} = response, data}) do
    case List.keyfind(headers, "Content-Type", 0) do
      {"Content-Type", "application/sdp"} ->
        data
        |> SDP.parse()
        ~>> ({:ok, result} -> %__MODULE__{response | body: result} ~> {:ok, &1})

      _ ->
        {:ok, %__MODULE__{response | body: data}}
    end
  end

  defp split_next_chunk(response), do: String.split(response, "\r\n", parts: 2)
end
