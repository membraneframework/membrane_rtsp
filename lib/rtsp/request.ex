defmodule Membrane.Protocol.RTSP.Request do
  @moduledoc """
  This module represents a RTSP 1.0 request.
  """
  @enforce_keys [:method]
  defstruct @enforce_keys ++ [:path, headers: [], body: ""]
  use Bunch

  alias Membrane.Protocol.RTSP

  @type t :: %__MODULE__{
          method: binary(),
          body: binary(),
          headers: RTSP.headers(),
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
  def with_header(%__MODULE__{headers: headers} = request, name, value),
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

  defp process_uri(request, uri) do
    %URI{uri | userinfo: nil}
    |> to_string()
    |> apply_path(request)
  end

  defp apply_path(url, %__MODULE__{path: nil}), do: url

  defp apply_path(url, %__MODULE__{path: path}),
    do: Path.join(url, path)

  defp render_headers([]), do: ""

  defp render_headers(list) do
    list
    |> Enum.map(fn elem -> header_to_string(elem) end)
    |> Enum.join("\r\n")
    ~> ("\r\n" <> &1)
  end

  defp header_to_string({header, value}), do: header <> ": " <> to_string(value)
end
