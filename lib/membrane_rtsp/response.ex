defmodule Membrane.RTSP.Response do
  @moduledoc """
  This module represents a RTSP response.
  """

  @start_line_regex ~r/^RTSP\/(\d\.\d) (\d\d\d) [A-Z a-z]+$/
  @line_ending ["\r\n", "\r", "\n"]

  @enforce_keys [:status, :version]
  defstruct @enforce_keys ++ [headers: [], body: ""]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: Membrane.RTSP.headers(),
          body: ExSDP.t() | binary()
        }

  @type result :: {:ok, t()} | {:error, atom()}

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
  Verifies if raw response binary has got proper length by comparing `Content-Length` header value to actual size of body in response.
  Returns tuple with verdict, expected size and actual size of body

  Example responses:
  `{:ok, 512, 512}` - `Content-Length` header value and body size matched. A response is complete.
  `{:ok, 0, 0}` - `Content-Length` header missing or set to 0 and no body. A response is complete.
  `{:error, 512, 123}` - Missing part of body in response.
  `{:error, 512, 0}` - Missing whole body in response.
  `{:error, 0, 0}` - Missing part of header or missing delimiter at the and of header part.
  """
  @spec verify_content_length(binary()) ::
          {:ok, non_neg_integer(), non_neg_integer()}
          | {:error, non_neg_integer(), non_neg_integer()}
  def verify_content_length(response) do
    splittet_response = String.split(response, ["\r\n\r\n", "\n\n", "\r\r"], parts: 2)
    headers = Enum.at(splittet_response, 0)
    body = Enum.at(splittet_response, 1)

    with {:ok, {response, headers}} <- parse_start_line(headers),
         {:ok, headers} <- parse_headers(headers),
         false <- is_nil(body),
         body_size <- byte_size(body),
         {:ok, content_legth_str} <-
           get_header(%__MODULE__{response | headers: headers}, "Content-Length") do
      {content_length, _remainder} = Integer.parse(content_legth_str)

      if body_size == content_length do
        {:ok, content_length, body_size}
      else
        {:error, content_length, body_size}
      end
    else
      {:error, :no_such_header} ->
        if byte_size(body) == 0 do
          {:ok, 0, 0}
        else
          {:error, 0, 0}
        end

      _other ->
        {:error, 0, 0}
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
      {_name, value} -> {:ok, value}
      nil -> {:error, :no_such_header}
    end
  end

  @spec parse_start_line(raw_response :: binary()) ::
          {:ok, {response :: t(), remainder :: binary}} | {:error, :invalid_start_line}
  defp parse_start_line(binary) do
    [line, rest] = String.split(binary, @line_ending, parts: 2)

    case Regex.run(@start_line_regex, line) do
      [_match, version, code] ->
        case Integer.parse(code) do
          :error ->
            {:error, :invalid_status_code}

          {code, _rest} when is_number(code) ->
            response = %__MODULE__{version: version, status: code}
            {:ok, {response, rest}}
        end

      _other ->
        {:error, :invalid_start_line}
    end
  end

  defp parse_headers(headers) do
    headers
    |> String.split(@line_ending)
    |> Bunch.Enum.try_map(fn header ->
      case String.split(header, ":", parts: 2) do
        [name, " " <> value] -> {:ok, {name, value}}
        _else -> {:error, {:malformed_header, header}}
      end
    end)
  end

  defp parse_body(data, headers) do
    case List.keyfind(headers, "Content-Type", 0) do
      {"Content-Type", "application/sdp"} ->
        ExSDP.parse(data)

      _other ->
        {:ok, data}
    end
  end
end
