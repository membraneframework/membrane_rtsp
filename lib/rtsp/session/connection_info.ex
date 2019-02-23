defmodule Membrane.RTSP.Session.ConnectionInfo do
  use Bunch
  @enforce_keys [:host, :port, :path]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          path: binary(),
          port: non_neg_integer(),
          host: binary()
        }

  @spec from_url(binary() | URI.t()) :: {:error, :invalid_url} | {:ok, t()}
  def from_url(url) do
    case URI.parse(url) do
      %URI{scheme: "rtsp"} = uri ->
        %URI{
          host: host,
          path: path,
          port: port
        } = uri

        %__MODULE__{
          host: host,
          port: port,
          path: path
        }
        ~> {:ok, &1}

      _ ->
        {:error, :invalid_url}
    end
  end
end
