defmodule Membrane.RTSP.Session do
  @moduledoc false
  use GenServer

  alias Membrane.RTSP
  alias Membrane.RTSP.{Request, Response}
  import Membrane.RTSP.Manager.Logic
  alias Membrane.RTSP.Manager.Logic.State

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
  @spec start_link(module(), binary(), Keyword.t()) :: GenServer.on_start()
  def start_link(transport \\ Membrane.RTSP.Transport.TCPSocket, url, options \\ []) do
    case URI.parse(url) do
      %URI{port: port, host: host, scheme: "rtsp"} = url
      when is_number(port) and is_binary(host) ->
        GenServer.start_link(__MODULE__, %{
          transport: transport,
          url: url,
          options: options
        })

      _ ->
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

    with {:ok, transport} <- Membrane.RTSP.Transport.TCPSocket.init(url) do
      state = %State{
        transport: transport,
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
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @spec request(pid(), binary(), RTSP.headers(), binary(), nil | binary()) :: Response.result()
  def request(session, method, headers \\ [], body \\ "", path \\ nil) do
    request = %Request{method: method, headers: headers, body: body, path: path}
    GenServer.call(session, {:execute, request})
  end
end
