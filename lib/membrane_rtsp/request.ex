defmodule Membrane.RTSP.Request do
  @moduledoc """
  This module represents a RTSP 1.0 request.
  """
  @enforce_keys [:method]
  defstruct @enforce_keys ++ [:path, headers: [], body: ""]

  @type t :: %__MODULE__{
          method: binary(),
          body: binary(),
          headers: Membrane.RTSP.headers(),
          path: nil | binary()
        }

  @doc """
  Attaches a header to a RTSP request struct.

  ```
    iex> Request.with_header(%Request{method: "DESCRIBE"}, "header_name", "header_value")
    %Request{method: "DESCRIBE", headers: [{"header_name","header_value"}]}

  ```
  """
  @spec with_header(t(), binary(), binary()) :: t()
  def with_header(%__MODULE__{headers: headers} = request, name, value)
      when is_binary(name) and is_binary(value),
      do: %__MODULE__{request | headers: [{name, value} | headers]}

  @doc """
  Renders the a RTSP request struct into a binary that is a valid
  RTSP request string that can be transmitted via communication channel.

  ```
  iex> uri = URI.parse("rtsp://domain.net:554/path:movie.mov")
  iex> Request.stringify(%Request{method: "DESCRIBE"}, uri)
  "DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\n\\r\\n"
  iex> Request.stringify(%Request{method: "PLAY", path: "trackID=2"}, uri)
  "PLAY rtsp://domain.net:554/path:movie.mov/trackID=2 RTSP/1.0\\r\\n\\r\\n"

  ```

  Access credentials won't be rendered into an url present in a RTSP start line.

  ```
  iex> uri = URI.parse("rtsp://user:password@domain.net:554/path:movie.mov")
  iex> Request.stringify(%Request{method: "DESCRIBE"}, uri)
  "DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\n\\r\\n"

  ```
  """
  @spec stringify(t(), URI.t()) :: binary()
  def stringify(%__MODULE__{method: method, headers: headers} = request, uri) do
    Enum.join([
      method,
      " ",
      process_uri(request, uri),
      " RTSP/1.0",
      render_headers(headers),
      "\r\n\r\n"
    ])
  end

  @doc """
  Parse a binary request into RTSP Request struct

  ```
    iex> Request.parse("DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\n\\r\\n")
    {:ok, %Request{method: "DESCRIBE", path: "rtsp://domain.net:554/path:movie.mov", headers: [], body: nil}}

  ```

  ```
    iex> Request.parse("DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\nCSeq: 1\\r\\n\\r\\n")
    {:ok, %Request{method: "DESCRIBE", path: "rtsp://domain.net:554/path:movie.mov", headers: [{"CSeq", "1"}], body: nil}}

  ```

  ```
    iex> Request.parse("DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\nContent-Length: 11\\r\\nHello World\\r\\n\\r\\n")
    {:ok, %Request{method: "DESCRIBE", path: "rtsp://domain.net:554/path:movie.mov", headers: [{"Content-Length", "11"}], body: "Hello World"}}

  ```

  ```
    iex> Request.parse("DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.1\\r\\n\\r\\n")
    {:error, "expected string \\"RTSP/1.0\\", followed by string \\"\\\\r\\\\n\\""}

  ```
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(request) do
    with {:ok, args} <- do_parse(request) do
      {method, uri, headers, body} =
        case args do
          [method, uri] -> {method, uri, [], nil}
          [method, uri, headers] -> {method, uri, headers, nil}
          [method, uri, headers, body] -> {method, uri, headers, body}
        end

      {:ok,
       %__MODULE__{
         method: method,
         path: uri,
         headers: headers,
         body: body
       }}
    end
  end

  defp do_parse(request) do
    case Membrane.RTSP.Parser.parse_request(request) do
      {:ok, args, _rest, _context, _line, _byte_offset} ->
        {:ok, args}

      {:error, reason, _rest, _context, _line, _byte_offset} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the encoded URI as a binary. This is handy for
  digest auth since this value must be encoded as per the digest
  algorithm
  """
  @spec process_uri(t(), URI.t()) :: binary()
  def process_uri(request, uri) do
    %URI{uri | userinfo: nil}
    |> apply_path(request)
  end

  defp apply_path(%URI{} = base_url, %__MODULE__{path: nil}), do: base_url

  defp apply_path(%URI{} = base_url, %__MODULE__{path: path}) do
    URI.parse(path)
    |> Map.get(:path)
    |> Path.relative_to(base_url.path)
    |> then(&Path.join(base_url.path, &1))
    |> then(&Map.put(base_url, :path, &1))
    |> URI.to_string()
  end

  defp render_headers([]), do: ""

  defp render_headers(list) do
    list
    |> Enum.map_join("\r\n", &header_to_string/1)
    |> String.replace_prefix("", "\r\n")
  end

  defp header_to_string({header, value}), do: header <> ": " <> value
end
