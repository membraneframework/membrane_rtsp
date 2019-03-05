defmodule Membrane.Protocol.RTSP.Request do
  @enforce_keys [:method, :body]
  defstruct @enforce_keys ++ [:headers]
  use Bunch

  @type header :: {binary(), binary()}

  @type t :: %__MODULE__{
          method: binary(),
          body: binary(),
          headers: [header]
        }

  @spec with_header(t(), header) :: t()
  def with_header(%__MODULE__{headers: headers} = request, {_name, _value} = header),
    do: %__MODULE__{request | headers: [header | headers]}

  @spec new(binary(), binary()) :: t()
  def new(method, body \\ ""), do: %__MODULE__{method: method, body: body, headers: []}

  @spec to_string(t(), binary()) :: binary()
  def to_string(%__MODULE__{method: method, headers: headers}, url) do
    method <> " " <> url <> " RTSP/1.0\r\n" <> render_headers(headers) <> "\r\n"
  end

  defp header_to_string({header, value}), do: header <> ": " <> String.Chars.to_string(value)
  defp render_headers([]), do: ""

  defp render_headers(list),
    do:
      list
      |> Enum.map(fn elem -> header_to_string(elem) end)
      |> Enum.join("\r\n")
      ~> (&1 <> "\r\n")
end
