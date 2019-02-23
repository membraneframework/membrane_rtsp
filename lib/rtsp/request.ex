defmodule Membrane.RTSP.Request do
  @enforce_keys [:method, :url]
  defstruct @enforce_keys ++ [:headers]

  @type t :: %__MODULE__{
          method: binary(),
          url: binary(),
          headers: [tuple()]
        }

  @spec options(binary()) :: t()
  def options(url), do: new("OPTIONS", url)

  @spec with_header(t(), tuple()) :: t()
  def with_header(%__MODULE__{headers: headers} = request, {_name, _value} = header),
    do: %__MODULE__{request | headers: [header | headers]}

  @spec new(binary(), binary()) :: t()
  def new(method, url), do: %__MODULE__{method: method, url: url, headers: []}

  def execute(%__MODULE__{url: url}) do
    # Call executor here
  end
end

defimpl String.Chars, for: Membrane.RTSP.Request do
  use Bunch
  alias Membrane.RTSP.Request

  @spec to_string(Request.t()) :: binary()
  def to_string(%Request{method: method, url: url, headers: headers}) do
    method <> " " <> url <> " RTSP/1.0\r\n" <> render_headers(headers) <> "\r\n"
  end

  defp header_to_string({header, value}), do: header <> ": " <> String.Chars.to_string(value)
  defp render_headers([]), do: ""

  defp render_headers(list),
    do:
      list
      |> Enum.map(fn elem -> header_to_string(elem) end)
      |> Enum.join("\r\n")
      ~> Kernel.<>(&1, "\r\n")
end
