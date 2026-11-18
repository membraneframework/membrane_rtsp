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

  @spec execute(
          binary(),
          :gen_tcp.socket(),
          non_neg_integer() | nil,
          :socket | :external_process,
          binary()
        ) :: {:ok, binary()} | {:error, :closed | :timeout | :inet.posix()}
  def execute(request, socket, response_timeout, receive_from, pending_data \\ <<>>)

  def execute(request, socket, response_timeout, :socket, pending_data) do
    :inet.setopts(socket, active: false)

    result =
      with :ok <- mockable(:gen_tcp).send(socket, request) do
        # One deadline for the whole response: a server that keeps sending something
        # else, such as interleaved packets, must not keep the caller waiting forever.
        # `pending_data` is what arrived before the request and is not a whole message
        # yet, such as the beginning of a request of the server; the response follows it.
        recv(
          socket,
          System.monotonic_time(:millisecond) + (response_timeout || @response_timeout),
          0,
          pending_data
        )
      end

    :inet.setopts(socket, active: true)
    result
  end

  def execute(request, socket, response_timeout, :external_process, _pending_data) do
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

  @doc """
  Answers the complete requests of the server that the data starts with and returns
  what follows them.
  """
  @spec reply_to_server_requests(:gen_tcp.socket(), binary()) :: binary()
  def reply_to_server_requests(socket, data) do
    with true <- ServerRequest.request?(data),
         {request, rest} <- split_message(data) do
      reply_to_server_request(socket, request)
      reply_to_server_requests(socket, rest)
    else
      _not_a_complete_request -> data
    end
  end

  # Splits the first RTSP message off the data, if all of it is there.
  defp split_message(data) do
    case Response.verify_content_length(data) do
      {:ok, _expected, _received} ->
        {data, <<>>}

      {:error, expected, received} when received > expected ->
        :erlang.split_binary(data, byte_size(data) - (received - expected))

      {:error, _expected, _received} ->
        nil
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

  defp recv(socket, deadline, length \\ 0, acc \\ <<>>) do
    with {:ok, data} <- do_recv(socket, deadline, length, acc) do
      handle_received(data, socket, deadline)
    end
  end

  defp handle_received(<<>>, socket, deadline) do
    recv(socket, deadline)
  end

  # skip rtp/rtcp packets
  defp handle_received(
         <<"$", _channel::8, size::16, _rtp::binary-size(size), rest::binary>>,
         socket,
         deadline
       ) do
    handle_received(rest, socket, deadline)
  end

  defp handle_received(<<"$", _rest::binary>> = data, socket, deadline) do
    recv(socket, deadline, 0, data)
  end

  defp handle_received(data, socket, deadline) do
    case Response.verify_content_length(data) do
      {:ok, _expected, _received} ->
        handle_message(data, <<>>, socket, deadline)

      {:error, expected, received} when received > expected ->
        {message, rest} = :erlang.split_binary(data, byte_size(data) - (received - expected))
        handle_message(message, rest, socket, deadline)

      {:error, expected, received} ->
        recv(socket, deadline, expected - received, data)
    end
  end

  # A request of the server is answered and reading goes on with what follows it,
  # anything else is the awaited response.
  defp handle_message(message, rest, socket, deadline) do
    cond do
      ServerRequest.request?(message) ->
        reply_to_server_request(socket, message)
        handle_received(rest, socket, deadline)

      rest == <<>> ->
        {:ok, message}

      # what follows the response may be requests of the server, which are answered
      true ->
        case reply_to_server_requests(socket, rest) do
          <<>> ->
            :ok

          rest ->
            Logger.warning(
              "Received #{byte_size(rest)} bytes after the end of the response. Truncating the response."
            )
        end

        {:ok, message}
    end
  end

  defp do_recv(socket, deadline, length, acc) do
    case deadline - System.monotonic_time(:millisecond) do
      remaining when remaining > 0 ->
        case mockable(:gen_tcp).recv(socket, length, remaining) do
          {:ok, data} -> {:ok, acc <> data}
          {:error, reason} -> {:error, reason}
        end

      _deadline_passed ->
        {:error, :timeout}
    end
  end
end
