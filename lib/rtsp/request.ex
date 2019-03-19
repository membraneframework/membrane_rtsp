defmodule Membrane.Protocol.RTSP.Request do
  @enforce_keys [:method]
  defstruct @enforce_keys ++ [{:headers, []}, {:body, ""}, :path]

  @type t :: %__MODULE__{
          method: binary(),
          body: binary(),
          headers: [{binary(), binary()}],
          path: nil | binary()
        }

  @spec with_header(t(), binary(), binary()) :: t()
  def with_header(%__MODULE__{headers: headers} = request, name, value),
    do: %__MODULE__{request | headers: [{name, value} | headers]}

  @spec to_string(t(), URI.t()) :: binary()
  def to_string(%__MODULE__{method: method, headers: headers} = request, uri) do
    method <>
      " " <> process_uri(request, uri) <> " RTSP/1.0\r\n" <> render_headers(headers) <> "\r\n\r\n"
  end

  defp process_uri(request, uri) do
    uri
    |> sanitize_uri()
    |> String.Chars.to_string()
    |> apply_path(request)
  end

  defp sanitize_uri(uri), do: %URI{uri | userinfo: nil}

  defp apply_path(url, %__MODULE__{path: nil}), do: url

  defp apply_path(url, %__MODULE__{path: path}),
    do: Path.join(url, path)

  defp header_to_string({header, value}), do: header <> ": " <> String.Chars.to_string(value)
  defp render_headers([]), do: ""

  defp render_headers(list) do
    list
    |> Enum.map(fn elem -> header_to_string(elem) end)
    |> Enum.join("\r\n")
  end
end
