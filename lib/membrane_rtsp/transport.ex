defmodule Membrane.RTSP.Transport do
  @moduledoc false
  import Mockery.Macro

  alias Membrane.RTSP.Response

  @connection_timeout 1000
  @response_timeout 5000

  @spec connect(URI.t(), non_neg_integer() | nil) ::
          {:ok, :gen_tcp.socket()} | {:error, :timeout | :inet.posix()}
  def connect(%URI{host: host, port: port}, connection_timeout \\ @connection_timeout) do
    mockable(:gen_tcp).connect(
      to_charlist(host),
      port,
      [:binary, active: true],
      connection_timeout || @connection_timeout
    )
  end

  @spec execute(binary(), :gen_tcp.socket(), non_neg_integer() | nil, :socket | :external_process) ::
          {:ok, binary()} | {:error, :closed | :timeout | :inet.posix()}
  def execute(request, socket, response_timeout, receive_from) do
    :inet.setopts(socket, active: false)

    result =
      with :ok <- mockable(:gen_tcp).send(socket, request) do
        recv(socket, response_timeout, receive_from)
      end

    :inet.setopts(socket, active: true)
    result
  end

  @spec close(:gen_tcp.socket()) :: :ok
  def close(socket) do
    :gen_tcp.close(socket)
  end

  @spec recv(:gen_tcp.socket(), non_neg_integer() | nil, :socket | :external_process) ::
          {:ok, binary()} | {:error, :closed | :timeout | :inet.posix()}
  defp recv(socket, response_timeout, :socket) do
    recv_from_socket(socket, response_timeout)
  end

  defp recv(_socket, response_timeout, :external_process) do
    receive do
      {:raw_response, response} -> {:ok, response}
    after
      response_timeout || @response_timeout -> {:error, :timeout}
    end
  end

  defp recv_from_socket(socket, response_timeout, length \\ 0, acc \\ <<>>) do
    case do_recv(socket, response_timeout, length, acc) do
      {:ok, data} ->
        case Response.verify_content_length(data) do
          {:ok, _expected, _received} ->
            {:ok, data}

          {:error, expected, received} ->
            recv_from_socket(socket, response_timeout, expected - received, data)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_recv(socket, response_timeout, length, acc) do
    case mockable(:gen_tcp).recv(
           socket,
           length,
           response_timeout || @response_timeout
         ) do
      {:ok, data} -> {:ok, acc <> data}
      {:error, reason} -> {:error, reason}
    end
  end
end
