defmodule Membrane.RTSP do
  @moduledoc """
  Functions for interfacing with a RTSP session
  """
  use GenServer

  require Logger
  alias Membrane.RTSP
  alias Membrane.RTSP.{Request, Response, Transport}

  @type t() :: pid()

  @type options() :: [option()]
  @type option() ::
          {:connection_timeout, non_neg_integer()} | {:response_timeout, non_neg_integer()}

  @default_rtsp_port 554
  @user_agent "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Client)"

  defmodule State do
    @moduledoc false
    @type digest_opts() :: %{
            realm: String.t() | nil,
            nonce: String.t() | nil,
            qop: String.t() | nil,
            nc: non_neg_integer()
          }

    @type auth() :: nil | :basic | {:digest, digest_opts()}

    @type t :: %__MODULE__{
            socket: :gen_tcp.socket(),
            cseq: non_neg_integer(),
            uri: URI.t(),
            session_id: binary() | nil,
            auth: auth(),
            response_timeout: non_neg_integer() | nil,
            receive_from: :socket | :external_process,
            retries: non_neg_integer()
          }

    @enforce_keys [:socket, :uri, :response_timeout]
    defstruct @enforce_keys ++
                [
                  session_id: nil,
                  cseq: 0,
                  auth: nil,
                  receive_from: :socket,
                  retries: 0
                ]
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

  @spec close(pid()) :: :ok
  def close(session), do: GenServer.cast(session, :terminate)

  @doc """
  Transfer the control of the TCP socket the session was using to a new process. For more information see `:gen_tcp.controlling_process/2`.
  From now on the session won't try to receive responses to requests from the socket, since now an other process is controlling it.
  Instead of this, the session will synchronously wait for the response to be supplied with `handle_response/2`.
  """
  @spec transfer_socket_control(t(), pid()) ::
          :ok | {:error, :closed | :not_owner | :badarg | :inet.posix()}
  def transfer_socket_control(session, new_controlling_process) do
    GenServer.call(session, {:transfer_socket_control, new_controlling_process})
  end

  @spec get_socket(t()) :: :gen_tcp.socket()
  def get_socket(session) do
    GenServer.call(session, :get_socket)
  end

  @spec handle_response(t(), binary()) :: :ok
  def handle_response(session, raw_response) do
    send(session, {:raw_response, raw_response})
    :ok
  end

  @type headers :: [{binary(), binary()}]

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

    with {:ok, socket} <- Transport.connect(url, options[:connection_timeout]) do
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
    handle_execute_call(request, true, state)
  end

  @impl true
  def handle_call({:transfer_socket_control, new_controlling_process}, _from, state) do
    {
      :reply,
      :gen_tcp.controlling_process(state.socket, new_controlling_process),
      %{state | receive_from: :external_process}
    }
  end

  @impl true
  def handle_call(:get_socket, _from, %State{socket: socket} = state) do
    {:reply, socket, state}
  end

  @impl true
  def handle_cast(:terminate, %State{} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    Logger.warning("Received an unexpected packet, ignoring: #{inspect(data)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :socket_closed, state}
  end

  @impl true
  def terminate(_reason, state) do
    Transport.close(state.socket)
  end

  @spec do_start(binary() | URI.t(), options(), (module(), any() -> GenServer.on_start())) ::
          GenServer.on_start()
  defp do_start(url, options, start_fun) do
    case URI.parse(url) do
      %URI{host: host, scheme: "rtsp"} = url when is_binary(host) ->
        start_fun.(__MODULE__, %{
          url: %URI{url | port: url.port || @default_rtsp_port, path: url.path || "/"},
          options: options
        })

      _else ->
        {:error, :invalid_url}
    end
  end

  @spec execute(Request.t(), State.t()) :: {:ok, binary()} | {:error, reason :: any()}
  defp execute(request, state) do
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
    |> Transport.execute(socket, response_timeout, state.receive_from)
  end

  @spec inject_session_header(Request.t(), binary() | nil) :: Request.t()
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
         {:ok, %State{} = state} <- detect_authentication_type(parsed_response, state) do
      state = %State{state | cseq: state.cseq + 1}
      state = increment_nc(state)
      {:ok, parsed_response, state}
    end
  end

  defp increment_nc(%State{auth: {:digest, %{nc: nc} = opts}} = state) do
    %State{state | auth: {:digest, %{opts | nc: nc + 1}}}
  end

  defp increment_nc(state), do: state

  @spec handle_execute_call(Request.t(), boolean(), State.t()) ::
          {:reply, Response.result(), State.t()}
  defp handle_execute_call(request, retry, state) do
    with {:ok, raw_response} <- execute(request, state),
         {:ok, response, state} <- parse_response(raw_response, state) do
      case response do
        %Response{status: 401} when retry ->
          handle_execute_call(request, false, state)

        response ->
          {:reply, {:ok, response}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
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

    encode_digest_auth(username, encoded_uri, ha1, ha2, options)
  end

  defp encode_digest_auth(username, encoded_uri, ha1, ha2, %{qop: nil} = options) do
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

  defp encode_digest_auth(username, encoded_uri, ha1, ha2, %{qop: qop} = options) do
    nc = options[:nc] || 1
    nc_hex = :io_lib.format("~8.16.0b", [nc]) |> IO.iodata_to_binary()
    cnonce = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    response = md5([ha1, options.nonce, nc_hex, cnonce, qop, ha2])

    "Digest " <>
      Enum.join(
        [
          ~s(username="#{username}"),
          ~s(realm="#{options.realm}"),
          ~s(nonce="#{options.nonce}"),
          ~s(uri="#{encoded_uri}"),
          ~s(response="#{response}"),
          ~s(algorithm=MD5),
          ~s(qop=#{qop}),
          ~s(nc=#{nc_hex}),
          ~s(cnonce="#{cnonce}")
        ],
        ","
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
  defp handle_session_id(%Response{} = response, %State{} = state) do
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

      qop =
        case Regex.run(~r/qop=\"?([^",]+)\"?/, digest) do
          [_match, qop_value] -> qop_value
          nil -> nil
        end

      auth_options = {:digest, %{nonce: nonce, realm: realm, qop: qop, nc: 1}}
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
