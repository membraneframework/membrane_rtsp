defmodule Membrane.RTSP do
  @moduledoc "RTSP Session"
  use GenServer

  import Membrane.RTSP.Logic

  alias Membrane.RTSP
  alias Membrane.RTSP.Logic.State
  alias Membrane.RTSP.{Request, Response, TCPSocket}

  @type t() :: pid()

  @default_rtsp_port 554

  @doc """
  Starts and links session process.

  Sets following properties of Session:
    * transport - information for executing request over the network. For
    reference see `Membrane.RTSP.Transport`
    * url - a base path for requests
    * options - a keyword list that shall be passed when executing request over
    transport
  """
  @spec start_link(binary() | URI.t(), Keyword.t()) :: GenServer.on_start()
  def start_link(url, options \\ []) do
    do_start(url, options, &GenServer.start_link/2)
  end

  @spec start(binary() | URI.t(), Keyword.t()) :: GenServer.on_start()
  def start(url, options \\ []) do
    do_start(url, options, &GenServer.start/2)
  end

  defp do_start(url, options, start_fun) do
    case URI.parse(url) do
      %URI{host: host, scheme: "rtsp"} = url when is_binary(host) ->
        start_fun.(__MODULE__, %{
          url: %URI{url | port: url.port || @default_rtsp_port},
          options: options
        })

      _else ->
        {:error, :invalid_url}
    end
  end

  @impl true
  def init(%{url: url, options: options}) do
    auth_type =
      case url do
        %URI{userinfo: nil} -> nil
        # default to basic. If it is actually digest, it will get set
        # when the correct header is detected
        %URI{userinfo: info} when is_binary(info) -> :basic
      end

    with {:ok, socket} <- TCPSocket.connect(url, options) do
      state = %State{
        socket: socket,
        uri: url,
        execution_options: options,
        auth: auth_type
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:execute, request}, _from, state) do
    with {:ok, raw_response} <- execute(request, state),
         {:ok, response, state} <- parse_response(raw_response, state) do
      {:reply, {:ok, response}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(
        {:transfer_socket_control, new_controlling_process},
        _from,
        %State{socket: socket} = state
      ) do
    {:reply, :gen_tcp.controlling_process(socket, new_controlling_process), state}
  end

  @impl true
  def handle_call(:get_socket, _from, %State{socket: socket} = state) do
    {:reply, socket, state}
  end

  @impl true
  def handle_call({:parse_response, raw_response}, _from, state) do
    with {:ok, response, state} <- parse_response(raw_response, state) do
      {:reply, {:ok, response}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast(:terminate, %State{} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:execute, request}, %State{cseq: cseq} = state) do
    case execute(request, state, false) do
      :ok ->
        {:noreply, %State{state | cseq: cseq + 1}}

      {:error, reason} ->
        raise "Error: #{reason}"
    end
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :socket_closed, state}
  end

  @impl true
  def terminate(_reason, state) do
    TCPSocket.close(state.socket)
  end

  @spec request(pid(), binary(), RTSP.headers(), binary(), nil | binary()) :: Response.result()
  def request(session, method, headers \\ [], body \\ "", path \\ nil) do
    request = %Request{method: method, headers: headers, body: body, path: path}
    GenServer.call(session, {:execute, request}, :infinity)
  end

  @spec request_no_response(pid(), binary(), RTSP.headers(), binary(), nil | binary()) :: :ok
  def request_no_response(session, method, headers \\ [], body \\ "", path \\ nil) do
    request = %Request{method: method, headers: headers, body: body, path: path}
    GenServer.cast(session, {:execute, request})
  end

  @spec close(pid()) :: :ok
  def close(session), do: GenServer.cast(session, :terminate)

  @spec transfer_socket_control(t(), pid()) ::
          :ok | {:error, :closed | :not_owner | :badarg | :inet.posix()}
  def transfer_socket_control(session, new_controlling_process) do
    GenServer.call(session, {:transfer_socket_control, new_controlling_process})
  end

  @spec get_socket(t()) :: :gen_tcp.socket()
  def get_socket(session) do
    GenServer.call(session, :get_socket)
  end

  @type headers :: [{binary(), binary()}]

  @spec get_parameter_no_response(t(), headers(), binary()) :: :ok
  def get_parameter_no_response(session, headers \\ [], body \\ ""),
    do: request_no_response(session, "GET_PARAMETER", headers, body)

  @spec play_no_response(t(), headers()) :: :ok
  def play_no_response(session, headers \\ []),
    do: request_no_response(session, "PLAY", headers, "")

  @spec handle_response(t(), binary()) :: Response.result()
  def handle_response(session, raw_response),
    do: GenServer.call(session, {:parse_response, raw_response})

  @spec describe(t(), headers()) :: Response.result()
  def describe(session, headers \\ []), do: request(session, "DESCRIBE", headers, "")

  @spec announce(t(), headers(), binary()) :: Response.result()
  def announce(session, headers \\ [], body \\ ""),
    do: request(session, "ANNOUNCE", headers, body)

  @spec get_parameter(t(), headers(), binary()) :: Response.result()
  def get_parameter(session, headers \\ [], body \\ ""),
    do: request(session, "GET_PARAMETER", headers, body)

  @spec options(t(), headers()) :: Response.result()
  def options(session, headers \\ []), do: request(session, "OPTIONS", headers)

  @spec pause(t(), headers()) :: Response.result()
  def pause(session, headers \\ []), do: request(session, "PAUSE", headers)

  @spec play(t(), headers()) :: Response.result()
  def play(session, headers \\ []), do: request(session, "PLAY", headers, "")

  @spec record(t(), headers()) :: Response.result()
  def record(session, headers \\ []), do: request(session, "RECORD", headers)

  @spec setup(t(), binary(), headers()) :: Response.result()
  def setup(session, path, headers \\ []), do: request(session, "SETUP", headers, "", path)

  @spec set_parameter(t(), headers(), binary()) :: Response.result()
  def set_parameter(session, headers \\ [], body \\ ""),
    do: request(session, "SET_PARAMETER", headers, body)

  @spec teardown(t(), headers()) :: Response.result()
  def teardown(session, headers \\ []), do: request(session, "TEARDOWN", headers)
end
