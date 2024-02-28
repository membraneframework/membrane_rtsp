defmodule Membrane.RTSP.Transport.TCPSocket do
  @moduledoc """
  This module implements the Transport behaviour and transmits requests over TCP
  Socket keeping connection until either session is closed or connection is
  closed by server.

  Supported options:
    * timeout - time after request will be deemed missing and error shall be
     returned.
  """
  use Membrane.RTSP.Transport
  import Mockery.Macro

  @connection_timeout 1000
  @response_timeout 5000

  @impl true
  def init(%URI{} = connection_info, options \\ []) do
    connection_timeout = options[:connection_timeout] || @connection_timeout

    with {:ok, socket} <- open(connection_info, connection_timeout) do
      {:ok, socket}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp open(%URI{host: host, port: port}, connection_timeout) do
    mockable(:gen_tcp).connect(
      to_charlist(host),
      port,
      [:binary, active: false],
      connection_timeout
    )
  end

  @impl true
  def execute(request, socket, options) do
    case mockable(:gen_tcp).send(socket, request) do
      :ok -> if options[:get_response], do: recv(socket, options), else: :ok
      error -> error
    end
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :socket_closed, state}
  end

  @impl true
  def close(_state), do: :ok

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
