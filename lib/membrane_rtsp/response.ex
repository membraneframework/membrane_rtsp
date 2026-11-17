defmodule Membrane.RTSP.Response do
  @moduledoc """
  This module represents a RTSP response.
  """

  require Logger

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
  @spec parse(binary()) :: {:ok, t()} | {:error, :invalid_start_line | term()}
  def parse(response) do
    {headers, body} =
      case String.split(response, ["\r\n\r\n", "\n\n", "\r\r"], parts: 2) do
        [headers, body] -> {headers, body}
        [headers] -> {headers, ""}
      end

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

  Only the headers are inspected, not the start line, so this also tells where a
  request sent by the server ends.

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
    case String.split(response, ["\r\n\r\n", "\n\n", "\r\r"], parts: 2) do
      # The headers have not arrived in full yet, so nothing can be said about them.
      [_incomplete_headers] ->
        {:error, 0, 0}

      [headers, body] ->
        headers =
          case String.split(headers, @line_ending, parts: 2) do
            [_start_line, headers] -> headers
            [_start_line] -> ""
          end

        # lines that are not headers are reported when the message is parsed, not here
        {:ok, headers} = parse_headers(headers, false)

        content_length =
          case find_header(headers, "Content-Length") do
            {:ok, content_length} -> parse_content_length(content_length)
            {:error, :no_such_header} -> 0
          end

        if byte_size(body) == content_length,
          do: {:ok, content_length, byte_size(body)},
          else: {:error, content_length, byte_size(body)}
    end
  end

  @doc """
  Retrieves the first header matching given name from a response.

  Header names are matched case-insensitively, as RFC 2326 requires.

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
  def get_header(%__MODULE__{headers: headers}, name), do: find_header(headers, name)

  defp find_header(headers, name) do
    name = String.downcase(name, :ascii)

    case Enum.find(headers, fn {key, _value} -> String.downcase(key, :ascii) == name end) do
      {_name, value} -> {:ok, value}
      nil -> {:error, :no_such_header}
    end
  end

  @doc """
  Parses the `Session` header of a response.

  Returns the session identifier and the session timeout in seconds, or `nil`
  for the timeout when the server did not announce a usable one. A client should
  send a request more often than that, otherwise the server may close the session
  (RFC 2326, section 12.37).

  ```
    iex> response = Response.new(200) |> Response.with_header("Session", "12345678;timeout=60")
    iex> Response.parse_session_header(response)
    {:ok, %{session_id: "12345678", timeout: 60}}
    iex> Response.parse_session_header(Response.new(200))
    {:error, :no_such_header}

  ```
  """
  @spec parse_session_header(t()) ::
          {:ok, %{session_id: binary(), timeout: pos_integer() | nil}}
          | {:error, :no_such_header}
  def parse_session_header(%__MODULE__{} = response) do
    with {:ok, value} <- get_header(response, "Session") do
      [session_id | params] = value |> String.split(";") |> Enum.map(&String.trim/1)

      {:ok, %{session_id: session_id, timeout: Enum.find_value(params, &parse_session_timeout/1)}}
    end
  end

  # The parameter name is matched case-insensitively and whitespace around "=" is
  # allowed, as libavformat and live555 do.
  defp parse_session_timeout(param) do
    with [name, value] <- String.split(param, "=", parts: 2),
         "timeout" <- name |> String.trim() |> String.downcase(:ascii),
         {timeout, _rest} when timeout > 0 <- value |> String.trim() |> Integer.parse() do
      timeout
    else
      _other -> nil
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

    # The reason phrase is free text and may be empty (RFC 2326, section 7.1),
    # so only the version and the status code are validated.
    case Regex.run(~r/^RTSP\/(\d\.\d) (\d\d\d)(?: .*)?$/, line) do
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

  # Header syntax follows RFC 2616, section 4.2 (referenced by RFC 2326): any amount
  # of whitespace may surround the value, the value may be empty and it may continue
  # on following lines that start with a space or a tab. Lines that are not headers
  # at all are skipped, so that one of them does not cost the whole response.
  defp parse_headers(headers, log_malformed? \\ true) do
    headers
    |> String.split(@line_ending)
    |> Enum.reduce([], fn
      "", acc ->
        acc

      <<char, _rest::binary>> = line, [{name, value} | acc] when char in [?\s, ?\t] ->
        [{name, String.trim(value <> " " <> String.trim(line))} | acc]

      line, acc ->
        case String.split(line, ":", parts: 2) do
          [name, value] when name != "" ->
            [{name, String.trim(value)} | acc]

          _other ->
            log_malformed_header(line, log_malformed?)
            acc
        end
    end)
    |> Enum.reverse()
    |> then(&{:ok, &1})
  end

  defp log_malformed_header(line, true),
    do: Logger.warning("Ignoring a malformed RTSP header line: #{inspect(line)}")

  defp log_malformed_header(_line, false), do: :ok

  # A value that is not a non-negative integer is treated as no body at all,
  # which is what libavformat does, instead of raising on input from the network.
  defp parse_content_length(value) do
    case Integer.parse(value) do
      {content_length, _remainder} when content_length >= 0 ->
        content_length

      _other ->
        Logger.warning("Ignoring an invalid Content-Length header: #{inspect(value)}")
        0
    end
  end

  defp parse_body(data, headers) do
    case find_header(headers, "Content-Type") do
      {:ok, content_type} ->
        if sdp_content_type?(content_type), do: parse_sdp(data), else: {:ok, data}

      # Some servers describe a stream without saying that the body is SDP.
      # A body that starts like a session description is given to the SDP parser;
      # if that fails, it is returned as it came, as any other untyped body.
      {:error, :no_such_header} ->
        with "v=" <> _rest <- data,
             {:ok, sdp} <- parse_sdp(data) do
          {:ok, sdp}
        else
          _other -> {:ok, data}
        end
    end
  end

  # Descriptions sent by cameras break the SDP grammar in many small ways that do not
  # stop other clients from using the stream, so lines that cannot be parsed are
  # skipped (and logged by the parser) instead of failing the whole response.
  defp parse_sdp(data), do: ExSDP.parse(data, lenient: true)

  # The media type is case-insensitive and may be followed by parameters
  # (RFC 2616, section 3.7), e.g. "Application/SDP; charset=utf-8".
  defp sdp_content_type?(content_type) do
    [media_type | _parameters] = String.split(content_type, ";", parts: 2)
    media_type |> String.trim() |> String.downcase(:ascii) == "application/sdp"
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
