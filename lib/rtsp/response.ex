defmodule Membrane.Protocol.RTSP.Response do
  @moduledoc """
  This module represents RTSP response.
  """
  use Bunch

  @start_line_regex ~r/^RTSP\/(\d\.\d) (\d\d\d) [A-Z a-z]+$/

  @enforce_keys [:status, :version]
  defstruct @enforce_keys ++ [headers: [], body: ""]

  alias Membrane.Protocol.SDP

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: [{binary(), binary()}],
          body: any()
        }

  @doc """
  Parses RTSP response.

  Requires raw response to be `\\r\\n` delimited. If body is present
  it will be parsed according to `Content-Type` header. Currently
  only the `application/sdp` is supported.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, :invalid_start_line | :malformed_header}
  def parse(response) do
    with {:ok, result} <- response |> parse_start_line(),
         {:ok, result} <- parse_headers(result) do
      parse_body(result)
    end
  end

  @doc """
  Retrieves the first header matching given name from a response.

  ```
    iex> response = %Response{
    ...>   status: 200,
    ...>   version: "1.0",
    ...>   headers: [{"header_name", "header_value"}]
    ...> }
    iex> Response.get_header(response, "header_name")
    {:ok, "header_value"}
    iex> Response.get_header(response, "non_existent_header")
    {:error, :no_such_header}

  ```

  """

  @spec get_header(__MODULE__.t(), binary()) :: {:error, :no_such_header} | {:ok, binary()}
  def get_header(%__MODULE__{headers: headers}, name) do
    case List.keyfind(headers, name, 0) do
      {_, value} -> {:ok, value}
      nil -> {:error, :no_such_header}
    end
  end

  @spec parse_start_line(raw_response :: binary()) ::
          {:ok, {response :: t(), remainder :: binary}} | {:error, :invalid_start_line}
  defp parse_start_line(binary) do
    [line, rest] = split_next_chunk(binary)

    case Regex.run(@start_line_regex, line) do
      [_, version, code] ->
        case Integer.parse(code) do
          :error ->
            {:error, :invalid_status_code}

          {code, _} when is_number(code) ->
            response = %__MODULE__{version: version, status: code}
            {:ok, {response, rest}}
        end

      _ ->
        {:error, :invalid_start_line}
    end
  end

  @spec parse_headers({t, raw_headers :: binary}) ::
          {:ok, {t, rest :: binary}} | {:error, :malformed_header}
  defp parse_headers(data, acc \\ [])

  defp parse_headers({response, "\r\n" <> rest}, acc) do
    headers = Enum.reverse(acc)
    response = %__MODULE__{response | headers: headers}
    {:ok, {response, rest}}
  end

  defp parse_headers({response, binary}, acc) do
    [line, rest] = split_next_chunk(binary)

    case String.split(line, ":", parts: 2) do
      [name, " " <> value | []] -> parse_headers({response, rest}, [{name, value} | acc])
      _ -> {:error, {:malformed_header, line}}
    end
  end

  defp split_next_chunk(response), do: String.split(response, "\r\n", parts: 2)

  @spec parse_body({t(), raw_body :: binary}) :: {:ok, t()} | {:error, atom()}
  defp parse_body({%__MODULE__{headers: headers} = response, data}) do
    case List.keyfind(headers, "Content-Type", 0) do
      {"Content-Type", "application/sdp"} ->
        data
        |> SDP.parse()
        ~>> ({:ok, result} -> {:ok, %__MODULE__{response | body: result}})

      _ ->
        {:ok, %__MODULE__{response | body: data}}
    end
  end
end
