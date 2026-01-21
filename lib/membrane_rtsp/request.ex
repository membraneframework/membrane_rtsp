defmodule Membrane.RTSP.Request do
  @moduledoc """
  This module represents a RTSP 1.0 request.
  """

  alias Membrane.RTSP.Parser

  @enforce_keys [:method]
  defstruct @enforce_keys ++ [:path, headers: [], body: ""]

  @type t :: %__MODULE__{
          method: binary(),
          body: binary(),
          headers: Membrane.RTSP.headers(),
          path: nil | binary()
        }

  @type transport_header :: [
          transport: :TCP | :UDP,
          network_mode: :unicast | :multicast,
          mode: :play | :record,
          parameters: map()
        ]

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
  Retrieves the first header matching given name from a request.

  ```
    iex> request = %Request{
    ...>   method: "OPTIONS",
    ...>   headers: [{"header_name", "header_value"}]
    ...> }
    iex> Request.get_header(request, "header_name")
    {:ok, "header_value"}
    iex> Request.get_header(request, "non_existent_header")
    {:error, :no_such_header}

  ```

  """
  @spec get_header(t(), binary()) :: {:ok, binary()} | {:error, :no_such_header}
  def get_header(%__MODULE__{headers: headers}, header) do
    case List.keyfind(headers, header, 0) do
      {_name, value} -> {:ok, value}
      nil -> {:error, :no_such_header}
    end
  end

  @doc """
  Renders the a RTSP request struct into a binary that is a valid
  RTSP request string that can be transmitted via communication channel.

  ```
  iex> uri = URI.parse("rtsp://domain.net:554/path:movie.mov")
  iex> Request.stringify(%Request{method: "DESCRIBE"}, uri)
  "DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\n\\r\\n"
  iex> Request.stringify(%Request{method: "PLAY", path: "trackID=2"}, uri)
  "PLAY rtsp://domain.net:554/path:movie.mov/trackID=2 RTSP/1.0\\r\\n\\r\\n"
  iex> Request.stringify(%Request{method: "SET_PARAMETER", body: "parameter:value"}, uri)
  "SET_PARAMETER rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\n\\r\\nparameter:value"

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
      "\r\n\r\n",
      request.body
    ])
  end

  @doc """
  Parse a binary request into RTSP Request struct

  ```
    iex> Request.parse("DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\n\\r\\n")
    {:ok, %Request{method: "DESCRIBE", path: "rtsp://domain.net:554/path:movie.mov", headers: [], body: nil}}

    iex> Request.parse("DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\nCSeq: 1\\r\\n\\r\\n")
    {:ok, %Request{method: "DESCRIBE", path: "rtsp://domain.net:554/path:movie.mov", headers: [{"CSeq", "1"}], body: nil}}

    iex> Request.parse("DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.0\\r\\nContent-Length: 11\\r\\n\\r\\nHello World")
    {:ok, %Request{method: "DESCRIBE", path: "rtsp://domain.net:554/path:movie.mov", headers: [{"Content-Length", "11"}], body: "Hello World"}}

    iex> Request.parse("DESCRIBE rtsp://domain.net:554/path:movie.mov RTSP/1.1\\r\\n\\r\\n")
    {:error, "expected string \\"RTSP/1.0\\""}

  ```
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  defdelegate parse(request), to: Parser, as: :parse_request

  @doc """
  Parse the Transport header.

  ```
    iex> req = %Request{method: "SETUP", headers: [{"Transport", "RTP/AVP;unicast;client_port=30001-30002"}]}
    iex> Request.parse_transport_header(req)
    {:ok, [transport: :UDP, network_mode: :unicast, mode: :play, parameters: %{"client_port" => {30001, 30002}}]}

    iex> req = %Request{method: "SETUP", headers: [{"Transport", "RTP/AVP;ttl=15"}]}
    iex> Request.parse_transport_header(req)
    {:ok, [transport: :UDP, network_mode: :multicast, mode: :play, parameters: %{"ttl" => 15}]}

    iex> req = %Request{method: "SETUP", headers: [{"Transport", "RTP/AVP/TCP;unicast;interleaved=0-1;mode=record"}]}
    iex> Request.parse_transport_header(req)
    {:ok, [transport: :TCP, network_mode: :unicast, mode: :record, parameters: %{"interleaved" => {0, 1}}]}

    iex> req = %Request{method: "SETUP", headers: [{"Transport", "RTP/AVP/TCP;unicast;interleaved=0-1;mode=\\"play\\""}]}
    iex> Request.parse_transport_header(req)
    {:ok, [transport: :TCP, network_mode: :unicast, mode: :play, parameters: %{"interleaved" => {0, 1}}]}

    iex> req = %Request{method: "SETUP", headers: [{"Transport", "RTP/AVP"}]}
    iex> Request.parse_transport_header(req)
    {:ok, [transport: :UDP, network_mode: :multicast, mode: :play, parameters: %{}]}

    iex> req = %Request{method: "SETUP", headers: [{"Transport", "RTP/AV"}]}
    iex> Request.parse_transport_header(req)
    {:error, :invalid_header}

    iex> Request.parse_transport_header(%Request{method: "SETUP"})
    {:error, :no_such_header}

  ```
  """
  @spec parse_transport_header(t()) ::
          {:ok, transport_header()} | {:error, :no_such_header | :invalid_header}
  def parse_transport_header(request) do
    with {:ok, value} <- get_header(request, "Transport") do
      Parser.parse_transport_header(value)
    end
  end

  @doc """
  Returns the encoded URI as a binary. This is handy for
  digest auth since this value must be encoded as per the digest
  algorithm
  """
  @spec process_uri(t(), URI.t()) :: binary()
  def process_uri(request, %URI{} = uri) do
    apply_path(%URI{uri | userinfo: nil}, request)
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
