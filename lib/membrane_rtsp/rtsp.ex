defmodule Membrane.RTSP do
  @moduledoc """
  Functions for interfacing with a RTSP session
  """
  use GenServer

  alias Membrane.RTSP
  alias Membrane.RTSP.{Request, Response, TCPSocket}

  @type t() :: pid()

  @type options() :: [option()]
  @type option() ::
          {:connection_timeout, non_neg_integer()} | {:response_timeout, non_neg_integer()}

  @default_rtsp_port 554
  @user_agent "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Client)"

  defmodule State do
    @moduledoc false
    @enforce_keys [:socket, :uri]
    defstruct @enforce_keys ++
                [
                  :response_timeout,
                  :session_id,
                  cseq: 0,
                  auth: nil
                ]

    @type digest_opts() :: %{
            realm: String.t() | nil,
            nonce: String.t() | nil
          }

    @type auth() :: nil | :basic | {:digest, digest_opts()}

    @type t :: %__MODULE__{
            socket: :gen_tcp.socket(),
            cseq: non_neg_integer(),
            uri: URI.t(),
            session_id: binary() | nil,
            auth: auth(),
            response_timeout: non_neg_integer()
          }
  end

  @doc """
  Starts and links session process with given URL as a base path for requests.
  """
  @spec start_link(binary() | URI.t(), options()) :: GenServer.on_start()
  def start_link(url, options \\ []) do
    do_start(url, options, &GenServer.start_link/2)
  end

  @doc """
  Same as start_link/2, but doesn't link the session process.
  """
  @spec start(binary() | URI.t(), Keyword.t()) :: GenServer.on_start()
  def start(url, options \\ []) do
    do_start(url, options, &GenServer.start/2)
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

  @spec handle_response(t(), binary()) :: Response.result()
  def handle_response(session, raw_response),
    do: GenServer.call(session, {:parse_response, raw_response})

  @spec get_parameter_no_response(t(), headers(), binary()) :: :ok
  def get_parameter_no_response(session, headers \\ [], body \\ ""),
    do: request_no_response(session, "GET_PARAMETER", headers, body)

  @spec play_no_response(t(), headers()) :: :ok
  def play_no_response(session, headers \\ []),
    do: request_no_response(session, "PLAY", headers, "")

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
  @spec teardown(pid()) :: {:error, atom()} | {:ok, Membrane.RTSP.Response.t()}
  def teardown(session, headers \\ []), do: request(session, "TEARDOWN", headers)

  @spec user_agent() :: binary()
  def user_agent(), do: @user_agent

  @impl true
  def init(%{url: url, options: options}) do
    auth_type =
      case url do
        %URI{userinfo: nil} -> nil
        # default to basic. If it is actually digest, it will get set
        # when the correct header is detected
        %URI{userinfo: info} when is_binary(info) -> :basic
      end

    with {:ok, socket} <- TCPSocket.connect(url, options[:connection_timeout]) do
      state = %State{
        socket: socket,
        uri: url,
        response_timeout: options[:response_timeout],
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
        raise "Error executing request #{inspect(request)}, reason: #{inspect(reason)}"
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

  @spec do_start(URI.t(), options(), (module(), any() -> GenServer.on_start())) ::
          GenServer.on_start()
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

  @spec execute(Request.t(), State.t(), boolean()) ::
          :ok | {:ok, binary()} | {:error, reason :: any()}
  defp execute(request, state, get_response \\ true) do
    %State{
      cseq: cseq,
      socket: socket,
      uri: uri,
      session_id: session_id,
      response_timeout: response_timeout
    } = state

    request
    |> inject_session_header(session_id)
    |> inject_content_length()
    |> Request.with_header("CSeq", cseq |> to_string())
    |> Request.with_header("User-Agent", @user_agent)
    |> apply_credentials(uri, state.auth)
    |> Request.stringify(uri)
    |> TCPSocket.execute(socket, response_timeout, get_response)
  end

  @spec inject_session_header(Request.t(), binary()) :: Request.t()
  defp inject_session_header(request, session_id) do
    case session_id do
      nil -> request
      session -> Request.with_header(request, "Session", session)
    end
  end

  @spec inject_content_length(Request.t()) :: Request.t()
  defp inject_content_length(request) do
    case request.body do
      "" -> request
      body -> Request.with_header(request, "Content-Length", to_string(byte_size(body)))
    end
  end

  @spec apply_credentials(Request.t(), URI.t(), State.auth()) :: Request.t()
  defp apply_credentials(request, %URI{userinfo: nil}, _auth_options), do: request

  defp apply_credentials(%Request{headers: headers} = request, uri, auth) do
    case List.keyfind(headers, "Authorization", 0) do
      {"Authorization", _value} ->
        request

      _else ->
        do_apply_credentials(request, uri, auth)
    end
  end

  @spec parse_response(binary(), State.t()) ::
          {:ok, Response.t(), State.t()} | {:error, reason :: any()}
  defp parse_response(raw_response, state) do
    with {:ok, parsed_response} <- Response.parse(raw_response),
         {:ok, state} <- handle_session_id(parsed_response, state),
         {:ok, state} <- detect_authentication_type(parsed_response, state) do
      state = %State{state | cseq: state.cseq + 1}
      {:ok, parsed_response, state}
    end
  end

  @spec do_apply_credentials(Request.t(), URI.t(), State.auth()) :: Request.t()
  defp do_apply_credentials(request, %URI{userinfo: info}, :basic) do
    encoded = Base.encode64(info)
    Request.with_header(request, "Authorization", "Basic " <> encoded)
  end

  defp do_apply_credentials(request, %URI{} = uri, {:digest, options}) do
    encoded = encode_digest(request, uri, options)
    Request.with_header(request, "Authorization", encoded)
  end

  defp do_apply_credentials(request, _url, _options) do
    request
  end

  @spec encode_digest(Request.t(), URI.t(), State.digest_opts()) :: String.t()
  defp encode_digest(request, %URI{userinfo: userinfo} = uri, options) do
    [username, password] = String.split(userinfo, ":", parts: 2)
    encoded_uri = Request.process_uri(request, uri)
    ha1 = md5([username, options.realm, password])
    ha2 = md5([request.method, encoded_uri])
    response = md5([ha1, options.nonce, ha2])

    Enum.join(
      [
        "Digest",
        ~s(username="#{username}",),
        ~s(realm="#{options.realm}",),
        ~s(nonce="#{options.nonce}",),
        ~s(uri="#{encoded_uri}",),
        ~s(response="#{response}")
      ],
      " "
    )
  end

  @spec md5([String.t()]) :: String.t()
  defp md5(value) do
    value
    |> Enum.join(":")
    |> IO.iodata_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end

  # Some responses do not have to return the Session ID
  # If it does return one, it needs to match one stored in the state.
  @spec handle_session_id(Response.t(), State.t()) :: {:ok, State.t()} | {:error, reason :: any()}
  defp handle_session_id(%Response{} = response, state) do
    with {:ok, session_value} <- Response.get_header(response, "Session") do
      [session_id | _rest] = String.split(session_value, ";")

      case state do
        %State{session_id: nil} -> {:ok, %State{state | session_id: session_id}}
        %State{session_id: ^session_id} -> {:ok, state}
        _else -> {:error, :invalid_session_id}
      end
    else
      {:error, :no_such_header} -> {:ok, state}
    end
  end

  # Checks for the `nonce` and `realm` values in the `WWW-Authenticate` header.
  # if they exist, sets `type` to `{:digest, opts}`
  @spec detect_authentication_type(Response.t(), State.t()) :: {:ok, State.t()}
  defp detect_authentication_type(%Response{} = response, state) do
    with {:ok, "Digest " <> digest} <- Response.get_header(response, "WWW-Authenticate") do
      [_match, nonce] = Regex.run(~r/nonce=\"(?<nonce>.*)\"/U, digest)
      [_match, realm] = Regex.run(~r/realm=\"(?<realm>.*)\"/U, digest)
      auth_options = {:digest, %{nonce: nonce, realm: realm}}
      {:ok, %{state | auth: auth_options}}
    else
      # non digest auth?
      {:ok, _non_digest} ->
        {:ok, %{state | auth: :basic}}

      {:error, :no_such_header} ->
        {:ok, state}
    end
  end
end
