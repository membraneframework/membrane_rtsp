defmodule Membrane.RTSP do
  @moduledoc "RTSP Session"
  use GenServer

  import Membrane.RTSP.Logic

  alias Membrane.RTSP
  alias Membrane.RTSP.Logic.State
  alias Membrane.RTSP.{Request, Response}

  @type t() :: pid()

  @doc """
  Starts and links session process.

  Sets following properties of Session:
    * transport - information for executing request over the network. For
    reference see `Membrane.RTSP.Transport`
    * url - a base path for requests
    * options - a keyword list that shall be passed when executing request over
    transport
  """
  @spec start_link(binary(), module() | URI.t(), Keyword.t()) :: GenServer.on_start()
  def start_link(url, transport \\ Membrane.RTSP.Transport.TCPSocket, options \\ []) do
    do_start(url, transport, options, &GenServer.start_link/2)
  end

  @spec start(binary(), module() | URI.t(), Keyword.t()) :: GenServer.on_start()
  def start(url, transport \\ Membrane.RTSP.Transport.TCPSocket, options \\ []) do
    do_start(url, transport, options, &GenServer.start/2)
  end

  defp do_start(url, transport, options, start_fun) do
    case URI.parse(url) do
      %URI{port: port, host: host, scheme: "rtsp"} = url
      when is_number(port) and is_binary(host) ->
        start_fun.(__MODULE__, %{
          transport: transport,
          url: url,
          options: options
        })

      _else ->
        {:error, :invalid_url}
    end
  end

  @impl true
  def init(%{url: url, options: options, transport: transport_module}) do
    auth_type =
      case url do
        %URI{userinfo: nil} -> nil
        # default to basic. If it is actually digest, it will get set
        # when the correct header is detected
        %URI{userinfo: info} when is_binary(info) -> :basic
      end

    with {:ok, transport} <- transport_module.init(url, options) do
      state = %State{
        transport: transport,
        transport_module: transport_module,
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
  def handle_call({:execute, request}, _from, %State{cseq: cseq} = state) do
    with {:ok, raw_response} <- execute(request, state),
         {:ok, parsed_response} <- Response.parse(raw_response),
         {:ok, state} <- handle_session_id(parsed_response, state),
         {:ok, state} <- detect_authentication_type(parsed_response, state) do
      state = %State{state | cseq: cseq + 1}
      {:reply, {:ok, parsed_response}, state}
    else
      {:error, :socket_closed} -> raise("Remote has closed a socket")
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call(:get_transport, _from, %State{transport: transport} = state) do
    {:reply, transport, state}
  end

  @impl true
  def handle_cast(:terminate, %State{} = state) do
    {:stop, :normal, state}
  end

  @impl true
  # this might be a message for transport layer. Redirect
  def handle_info(msg, %State{} = state) do
    state.transport_module.handle_info(msg, state.transport)
    |> translate(:transport, state)
  end

  @impl true
  def terminate(_reason, state) do
    state.transport_module.close(state.transport)
  end

  @spec request(pid(), binary(), RTSP.headers(), binary(), nil | binary()) :: Response.result()
  def request(session, method, headers \\ [], body \\ "", path \\ nil) do
    request = %Request{method: method, headers: headers, body: body, path: path}
    GenServer.call(session, {:execute, request})
  end

  @spec close(pid()) :: :ok
  def close(session), do: GenServer.cast(session, :terminate)

  defp translate({action, new_state}, key, state) do
    {action, Map.put(state, key, new_state)}
  end

  defp translate({action, reply, new_state}, key, state) do
    {action, reply, Map.put(state, key, new_state)}
  end

  @type headers :: [{binary(), binary()}]

  @spec get_transport(t()) :: any()
  def get_transport(session) do
    GenServer.call(session, :get_transport)
  end

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
  def play(session, headers \\ []) do
    request(session, "PLAY", headers, "")
  end

  @spec record(t(), headers()) :: Response.result()
  def record(session, headers \\ []), do: request(session, "RECORD", headers)

  @spec setup(t(), binary(), headers()) :: Response.result()
  def setup(session, path, headers \\ []) do
    request(session, "SETUP", headers, "", path)
  end

  @spec set_parameter(t(), headers(), binary()) :: Response.result()
  def set_parameter(session, headers \\ [], body \\ ""),
    do: request(session, "SET_PARAMETER", headers, body)

  @spec teardown(t(), headers()) :: Response.result()
  def teardown(session, headers \\ []), do: request(session, "TEARDOWN", headers)
end
