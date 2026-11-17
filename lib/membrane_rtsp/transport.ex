defmodule Membrane.RTSP.Transport do
  @moduledoc false
  use Mockery.Macro

  require Logger

  alias Membrane.RTSP.{Response, ServerRequest}

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
      timeout = response_timeout || @response_timeout
      await_response(socket, System.monotonic_time(:millisecond) + timeout)
    end
  end

  @doc """
  Answers a request that the server sent on the client's connection.
  """
  @spec reply_to_server_request(:gen_tcp.socket(), binary()) :: :ok
  def reply_to_server_request(socket, request) do
    case mockable(:gen_tcp).send(socket, ServerRequest.reply(request)) do
      {:error, reason} ->
        Logger.warning("Failed to answer a request of the RTSP server: #{inspect(reason)}")

      _sent ->
        :ok
    end
  end

  # Waits for the response supplied by the process that reads the socket. Requests of
  # the server that arrive in the meantime are answered and the wait goes on.
  defp await_response(socket, deadline) do
    receive do
      {:raw_response, message} ->
        if ServerRequest.request?(message) do
          reply_to_server_request(socket, message)
          await_response(socket, deadline)
        else
          {:ok, message}
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, :timeout}
    end
  end

  @spec close(:gen_tcp.socket()) :: :ok
  def close(socket) do
    :gen_tcp.close(socket)
  end

  defp recv(socket, response_timeout, length \\ 0, acc \\ <<>>) do
    with {:ok, data} <- do_recv(socket, response_timeout, length, acc) do
      handle_received(data, socket, response_timeout)
    end
  end

  defp handle_received(<<>>, socket, response_timeout) do
    recv(socket, response_timeout)
  end

  # skip rtp/rtcp packets
  defp handle_received(
         <<"$", _channel::8, size::16, _rtp::binary-size(size), rest::binary>>,
         socket,
         response_timeout
       ) do
    handle_received(rest, socket, response_timeout)
  end

  defp handle_received(<<"$", _rest::binary>> = data, socket, response_timeout) do
    recv(socket, response_timeout, 0, data)
  end

  defp handle_received(data, socket, response_timeout) do
    case Response.verify_content_length(data) do
      {:ok, _expected, _received} ->
        handle_message(data, <<>>, socket, response_timeout)

      {:error, expected, received} when received > expected ->
        {message, rest} = :erlang.split_binary(data, byte_size(data) - (received - expected))
        handle_message(message, rest, socket, response_timeout)

      {:error, expected, received} ->
        recv(socket, response_timeout, expected - received, data)
    end
  end

  # A request of the server is answered and reading goes on with what follows it,
  # anything else is the awaited response.
  defp handle_message(message, rest, socket, response_timeout) do
    cond do
      ServerRequest.request?(message) ->
        reply_to_server_request(socket, message)
        handle_received(rest, socket, response_timeout)

      rest == <<>> ->
        {:ok, message}

      true ->
        Logger.warning(
          "Received #{byte_size(rest)} bytes after the end of the response. Truncating the response."
        )

        {:ok, message}
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
