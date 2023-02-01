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
    |> URI.to_string
  end

  defp render_headers([]), do: ""

  defp render_headers(list) do
    list
    |> Enum.map_join("\r\n", &header_to_string/1)
    |> String.replace_prefix("", "\r\n")
  end

  defp header_to_string({header, value}), do: header <> ": " <> value
end
