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
      [:binary, active: true],
      connection_timeout
    )
  end

  @impl true
  def execute(request, socket, _options \\ []) do
    with :ok <- mockable(:gen_tcp).send(socket, request),
         {:ok, data} <- recv() do
      {:ok, data}
    else
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :socket_closed, state}
  end

  @impl true
  def close(_state), do: :ok

  defp recv() do
    receive do
      {:tcp, _socket, data} ->
        {:ok, data}

      {:tcp_closed, _socket} ->
        {:error, :connection_closed}
    end
  end
end
