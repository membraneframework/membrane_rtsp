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
  def execute(request, socket, response_timeout, :socket) do
    :inet.setopts(socket, active: false)

    result =
      with :ok <- mockable(:gen_tcp).send(socket, request) do
        recv(socket, response_timeout)
      end

    :inet.setopts(socket, active: true)
    result
  end

  def execute(request, socket, response_timeout, :external_process) do
    with :ok <- mockable(:gen_tcp).send(socket, request) do
      receive do
        {:raw_response, response} -> {:ok, response}
      after
        response_timeout || @response_timeout -> {:error, :timeout}
      end
    end
  end

  @spec close(:gen_tcp.socket()) :: :ok
  def close(socket) do
    :gen_tcp.close(socket)
  end

  defp recv(socket, response_timeout, length \\ 0, acc \\ <<>>) do
    case do_recv(socket, response_timeout, length, acc) do
      # skip rtp/rtcp packets
      {:ok, <<"$", _channel::8, size::16, _rtp::binary-size(size), rest::binary>>} ->
        recv(socket, response_timeout, 0, rest)

      {:ok, <<"$", _rest::binary>> = data} ->
        recv(socket, response_timeout, 0, data)

      {:ok, data} ->
        case Response.verify_content_length(data) do
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
