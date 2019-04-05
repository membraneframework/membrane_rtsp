defmodule Membrane.Protocol.RTSP.Response do
  @moduledoc """
  This module represents a RTSP response.
  """

  @start_line_regex ~r/^RTSP\/(\d\.\d) (\d\d\d) [A-Z a-z]+$/
  @line_delimiter ["\r\n", "\r", "\n"]

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

  If the body is present it will be parsed according to `Content-Type` header.
  Currently only the `application/sdp` is supported.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, :invalid_start_line | :malformed_header}
  def parse(response) do
    [headers, body] = String.split(response, ["\r\n\r\n", "\n\n", "\r\r"], parts: 2)

    with {:ok, {response, headers}} <- parse_start_line(headers),
         {:ok, headers} <- parse_headers(headers),
         {:ok, body} <- parse_body(body, headers) do
      {:ok, %__MODULE__{response | headers: headers, body: body}}
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
    [line, rest] = String.split(binary, @line_delimiter, parts: 2)

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

  defp parse_headers(headers) do
    headers
    |> String.split(@line_delimiter)
    |> Bunch.Enum.try_map(fn header ->
      case String.split(header, ":", parts: 2) do
        [name, " " <> value] -> {:ok, {name, value}}
        _ -> {:error, {:malformed_header, header}}
      end
    end)
  end

  defp parse_body(data, headers) do
    case List.keyfind(headers, "Content-Type", 0) do
      {"Content-Type", "application/sdp"} ->
        with {:ok, result} <- SDP.parse(data) do
          {:ok, result}
        end

      _ ->
        {:ok, data}
    end
  end
end
