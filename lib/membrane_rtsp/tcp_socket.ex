defmodule Membrane.RTSP.TCPSocket do
  @moduledoc false
  import Mockery.Macro

  @connection_timeout 1000
  @response_timeout 5000

  @spec connect(URI.t(), non_neg_integer() | nil) ::
          {:ok, :gen_tcp.socket()} | {:error, :timeout | :inet.posix()}
  def connect(%URI{host: host, port: port}, connection_timeout \\ @connection_timeout) do
    mockable(:gen_tcp).connect(
      to_charlist(host),
      port,
      [:binary, active: false],
      connection_timeout || @connection_timeout
    )
  end

  @spec execute(binary(), :gen_tcp.socket(), non_neg_integer() | nil, boolean()) ::
          :ok | {:ok, binary()} | {:error, :closed | :timeout | :inet.posix()}
  def execute(request, socket, response_timeout, true = _get_response) do
    with :ok <- mockable(:gen_tcp).send(socket, request) do
      recv(socket, response_timeout)
    end
  end

  def execute(request, socket, _response_timeout, false = _get_response) do
    mockable(:gen_tcp).send(socket, request)
  end

  @spec close(:gen_tcp.socket()) :: :ok
  def close(socket) do
    :gen_tcp.close(socket)
  end

  defp recv(socket, response_timeout, length \\ 0, acc \\ <<>>) do
    case do_recv(socket, response_timeout, length, acc) do
      {:ok, data} ->
        case Membrane.RTSP.Response.verify_content_length(data) do
          {:ok, _expected, _received} ->
            {:ok, data}

          {:error, expected, received} ->
            recv(socket, response_timeout, expected - received, data)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_recv(socket, response_timeout, length, acc) do
    case mockable(:gen_tcp).recv(socket, length, response_timeout || @response_timeout) do
      {:ok, data} -> {:ok, acc <> data}
      {:error, reason} -> {:error, reason}
    end
  end
end
