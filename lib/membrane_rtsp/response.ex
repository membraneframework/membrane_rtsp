defmodule Membrane.RTSP.Response do
  @moduledoc """
  This module represents a RTSP response.
  """

  @line_ending ["\r\n", "\r", "\n"]

  @enforce_keys [:status, :version]
  defstruct @enforce_keys ++ [headers: [], body: ""]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: Membrane.RTSP.headers(),
          body: ExSDP.t() | binary()
        }

  @type result :: {:ok, t()} | {:error, atom()}

  @spec new(non_neg_integer()) :: t()
  def new(status) do
    %__MODULE__{version: "1.0", status: status}
  end

  @doc """
  Attaches a header to a RTSP response struct.

  ```
    iex> Response.with_header(Response.new(200), "header_name", "header_value")
    %Response{version: "1.0", status: 200, headers: [{"header_name","header_value"}]}

  ```
  """
  @spec with_header(t(), binary(), binary()) :: t()
  def with_header(%__MODULE__{headers: headers} = request, name, value)
      when is_binary(name) and is_binary(value),
      do: %__MODULE__{request | headers: [{name, value} | headers]}

  @doc """
  Adds a body to the response and sets `Content-Length` header

  ```
    iex> Response.with_body(Response.new(200), "Hello World")
    %Response{version: "1.0", status: 200, headers: [{"Content-Length", "11"}], body: "Hello World"}

  ```
  """
  @spec with_body(t(), binary()) :: t()
  def with_body(%__MODULE__{} = response, body) do
    with_header(%__MODULE__{response | body: body}, "Content-Length", "#{byte_size(body)}")
  end

  @doc """
  Parses RTSP response.

  If the body is present it will be parsed according to `Content-Type` header.
  Currently only the `application/sdp` is supported.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, :invalid_start_line | :malformed_header}
  def parse(response) do
    [headers, body] = String.split(response, ["\r\n\r\n", "\n\n", "\r\r"], parts: 2)

    with {:ok, {%__MODULE__{} = response, headers}} <- parse_start_line(headers),
         {:ok, headers} <- parse_headers(headers),
         {:ok, body} <- parse_body(body, headers) do
      {:ok, %__MODULE__{response | headers: headers, body: body}}
    end
  end

  @doc """
  Renders an RTSP response struct into a binary that is a valid
  RTSP response string that can be transmitted via communication channel.

  ```
    iex> Response.stringify(%Response{version: "1.0", status: 200, headers: []})
    "RTSP/1.0 200 OK\\r\\n\\r\\n"

    iex> Response.stringify(%Response{version: "1.0", status: 200, headers: [{"Content-Length", "11"}, {"Session", "15569"}], body: "Hello World"})
    "RTSP/1.0 200 OK\\r\\nContent-Length: 11\\r\\nSession: 15569\\r\\n\\r\\nHello World"

  ```
  """
  @spec stringify(t()) :: binary()
  def stringify(%__MODULE__{status: status} = response) do
    status_line = Enum.join(["RTSP/1.0", "#{status}", render_status(status)], " ")

    Enum.join([
      status_line,
      render_headers(response.headers),
      "\r\n\r\n#{response.body}"
    ])
  end

  @doc """
  Verifies if raw response binary has got proper length by comparing `Content-Length` header value to actual size of body in response.
  Returns tuple with verdict, expected size and actual size of body

  Example responses:
  `{:ok, 512, 512}` - `Content-Length` header value and body size matched. A response is complete.
  `{:ok, 0, 0}` - `Content-Length` header missing or set to 0 and no body. A response is complete.
  `{:error, 512, 123}` - Missing part of body in response.
  `{:error, 512, 623}` - Body in response longer than expected.
  `{:error, 512, 0}` - Missing whole body in response.
  `{:error, 0, 123}` - Body is present despite not being expected.
  `{:error, 0, 0}` - Missing part of header or missing delimiter at the end of the header part.
  """
  @spec verify_content_length(binary()) ::
          {:ok | :error, expected_size :: non_neg_integer(), actual_size :: non_neg_integer()}
  def verify_content_length(response) do
    split_response = String.split(response, ["\r\n\r\n", "\n\n", "\r\r"], parts: 2)
    headers = Enum.at(split_response, 0)
    body = Enum.at(split_response, 1)

    with {:ok, {%__MODULE__{} = response, headers}} <- parse_start_line(headers),
         {:ok, headers} <- parse_headers(headers),
         false <- is_nil(body),
         body_size <- byte_size(body),
         {:ok, content_length_str} <-
           get_header(%__MODULE__{response | headers: headers}, "Content-Length") do
      {content_length, _remainder} = Integer.parse(content_length_str)

      if body_size == content_length do
        {:ok, content_length, body_size}
      else
        {:error, content_length, body_size}
      end
    else
      {:error, :no_such_header} when byte_size(body) == 0 ->
        {:ok, 0, 0}

      {:error, :no_such_header} ->
        {:error, 0, byte_size(body)}

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
  @spec get_header(t(), binary()) :: {:error, :no_such_header} | {:ok, binary()}
  def get_header(%__MODULE__{headers: headers}, name) do
    case List.keyfind(headers, name, 0) do
      {_name, value} -> {:ok, value}
      nil -> {:error, :no_such_header}
    end
  end

  @doc """
  Returns true if the response is a success.

  ```
    iex> Response.ok?(Response.new(204))
    true

    iex> Response.ok?(Response.new(400))
    false

  ```
  """
  @spec ok?(t()) :: boolean()
  def ok?(%__MODULE__{status: status}) when status >= 200 and status < 300, do: true
  def ok?(_response), do: false

  @spec parse_start_line(raw_response :: binary()) ::
          {:ok, {response :: t(), remainder :: binary}} | {:error, :invalid_start_line}
  defp parse_start_line(binary) do
    {line, rest} =
      case String.split(binary, @line_ending, parts: 2) do
        [line] -> {line, ""}
        [line, rest] -> {line, rest}
      end

    case Regex.run(~r/^RTSP\/(\d\.\d) (\d\d\d) [A-Z a-z]+$/, line) do
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

  defp render_headers([]), do: ""

  defp render_headers(list) do
    list
    |> Enum.map_join("\r\n", &header_to_string/1)
    |> String.replace_prefix("", "\r\n")
  end

  defp header_to_string({header, value}), do: header <> ": " <> value

  defp render_status(200), do: "OK"
  defp render_status(400), do: "Bad Request"
  defp render_status(401), do: "Unauthorized"
  defp render_status(403), do: "Forbidden"
  defp render_status(404), do: "Not Found"
  defp render_status(405), do: "Method Not Allowed"
  defp render_status(455), do: "Method Not Valid In This State"
  defp render_status(461), do: "Unsupported Transport"
  defp render_status(500), do: "Internal Server Error"
  defp render_status(501), do: "Not Implemented"
  defp render_status(_status), do: "Generic Error"
end
