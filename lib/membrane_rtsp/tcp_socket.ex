defmodule Membrane.RTSP.TCPSocket do
  @moduledoc """
  This module transmits requests over TCP
  Socket keeping connection until either session is closed or connection is
  closed by server.

  Supported options:
    * timeout - time after request will be deemed missing and error shall be
     returned.
  """
  import Mockery.Macro

  @connection_timeout 1000
  @response_timeout 5000

  @spec connect(URI.t(), nil | maybe_improper_list() | map()) :: any()
  def connect(%URI{host: host, port: port}, options \\ []) do
    connection_timeout = options[:connection_timeout] || @connection_timeout

    mockable(:gen_tcp).connect(
      to_charlist(host),
      port,
      [:binary, active: false],
      connection_timeout
    )
  end

  @spec execute(binary(), :gen_tcp.socket(), Keyword.t()) ::
          :ok | {:ok, binary()} | {:error, :closed | :timeout | :inet.posix()}
  def execute(request, socket, options) do
    case mockable(:gen_tcp).send(socket, request) do
      :ok -> if options[:get_response], do: recv(socket, options), else: :ok
      error -> error
    end
  end

  def close(socket) do
    :gen_tcp.close(socket)
  end

  defp recv(socket, options, length \\ 0, acc \\ <<>>) do
    case do_recv(socket, options, length, acc) do
      {:ok, data} ->
        case Membrane.RTSP.Response.verify_content_length(data) do
          {:ok, _expected, _received} -> {:ok, data}
          {:error, expected, received} -> recv(socket, options, expected - received, data)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_recv(socket, options, length, acc) do
    timeout = options[:response_timeout] || @response_timeout

    case mockable(:gen_tcp).recv(socket, length, timeout) do
      {:ok, data} -> {:ok, acc <> data}
      {:error, reason} -> {:error, reason}
    end
  end
end
