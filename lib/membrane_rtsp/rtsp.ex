defmodule Membrane.RTSP do
  @moduledoc """
  Functions for interfacing with a RTSP session
  """
  use GenServer

  require Logger
  alias Membrane.RTSP
  alias Membrane.RTSP.{Request, Response, ServerRequest, Transport}

  @type t() :: pid()

  @typedoc """
  Options of a session:
  * `:connection_timeout` - time in milliseconds to wait for the TCP connection.
  * `:response_timeout` - time in milliseconds to wait for a response to a request.
  * `:user_agent` - value of the `User-Agent` header sent with every request, for
    servers that treat clients differently by name. Defaults to `user_agent/0`.
  """
  @type options() :: [option()]
  @type option() ::
          {:connection_timeout, non_neg_integer()}
          | {:response_timeout, non_neg_integer()}
          | {:user_agent, binary()}

  @default_rtsp_port 554
  # the most that is kept of a request of the server while its end is awaited
  @max_unsolicited_data_size 4096
  # a longer challenge is not worth the time that reading it could take
  @max_challenge_size 4096
  @user_agent "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Client)"

  defmodule State do
    @moduledoc false
    @type digest_opts() :: %{
            required(:realm) => String.t() | nil,
            required(:nonce) => String.t() | nil,
            required(:qop) => String.t() | nil,
            required(:nc) => non_neg_integer(),
            optional(:opaque) => String.t(),
            optional(:algorithm) => String.t()
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
            retries: non_neg_integer(),
            user_agent: binary() | nil,
            unsolicited_data: binary(),
            content_base: binary() | nil,
            append_control_to_base?: boolean()
          }

    @enforce_keys [:socket, :uri, :response_timeout]
    defstruct @enforce_keys ++
                [
                  session_id: nil,
                  cseq: 0,
                  auth: nil,
                  receive_from: :socket,
                  retries: 0,
                  user_agent: nil,
                  unsolicited_data: <<>>,
                  content_base: nil,
                  append_control_to_base?: false
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

  @doc """
  Supplies the session with an RTSP message read from the socket by the process that
  controls it (see `transfer_socket_control/2`).

  The message is either the response to the request the session is waiting on, or a
  request sent by the server, which the session answers on its own.
  """
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
        auth: auth_type,
        user_agent: options[:user_agent]
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:execute, %Request{method: "SETUP"} = request}, _from, %State{} = state) do
    execute_setup(request, state)
  end

  @impl true
  def handle_call({:execute, request}, _from, %State{} = state) do
    with {:reply, {:ok, %Response{} = response}, state} <-
           handle_execute_call(request, true, state) do
      {:reply, {:ok, response}, store_content_base(request, response, state)}
    end
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
  def handle_info({:tcp, _socket, data}, %State{} = state) do
    # A request of the server may come in more than one segment, so its beginning
    # is kept until the rest arrives.
    case handle_unsolicited_message(state.unsolicited_data <> data, state) do
      <<>> ->
        {:noreply, %State{state | unsolicited_data: <<>>}}

      rest ->
        if ServerRequest.request?(rest) and byte_size(rest) <= @max_unsolicited_data_size do
          {:noreply, %State{state | unsolicited_data: rest}}
        else
          Logger.warning("Received an unexpected packet, ignoring: #{inspect(rest)}")
          {:noreply, %State{state | unsolicited_data: <<>>}}
        end
    end
  end

  # A message handed over with `handle_response/2` while no request is in progress.
  @impl true
  def handle_info({:raw_response, message}, state) do
    case handle_unsolicited_message(message, state) do
      <<>> -> :ok
      rest -> Logger.warning("Received an unexpected packet, ignoring: #{inspect(rest)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, {:socket_error, reason}, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :socket_closed, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("Ignoring an unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Transport.close(state.socket)
  end

  # Servers may send requests of their own, typically to check that the client is still
  # there, and those are answered. Anything else that arrives while no request is in
  # progress, such as a response that came after its request had timed out, is dropped.
  @spec handle_unsolicited_message(binary(), State.t()) :: binary()
  defp handle_unsolicited_message(message, %State{socket: socket}) do
    Transport.reply_to_server_requests(socket, message)
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
    |> Request.with_header("User-Agent", state.user_agent || @user_agent)
    |> apply_credentials(uri, state.auth)
    |> Request.stringify(uri)
    |> Transport.execute(socket, response_timeout, state.receive_from, state.unsolicited_data)
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
  defp handle_execute_call(request, retry, %State{} = state) do
    result = execute(request, state)
    # what had arrived before the request went into the reading of its response
    state = %State{state | unsolicited_data: <<>>}

    with {:ok, raw_response} <- result,
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

  # The DESCRIBE reply may name the URL that relative control URLs of the description
  # are resolved against (RFC 2326, appendix C.1.1). It is kept for `SETUP`.
  @spec store_content_base(Request.t(), Response.t(), State.t()) :: State.t()
  defp store_content_base(%Request{method: "DESCRIBE"}, %Response{} = response, %State{} = state) do
    with true <- Response.ok?(response),
         {:ok, value} <- base_url_of_description(response),
         %URI{scheme: scheme, host: host} = content_base
         when scheme in ["rtsp", "rtsps"] and is_binary(host) and host != "" <-
           URI.parse(String.trim(value)) do
      %State{state | content_base: URI.to_string(%URI{content_base | userinfo: nil})}
    else
      _other -> %State{state | content_base: nil}
    end
  end

  defp store_content_base(_request, _response, state), do: state

  # A control attribute of the session that holds a URL names the base itself and
  # goes before the Content-Base header, as in libavformat and gortsplib, which found
  # servers whose Content-Base lacks a part of the URL that this attribute has.
  @spec base_url_of_description(Response.t()) :: {:ok, binary()} | {:error, :no_such_header}
  defp base_url_of_description(%Response{body: %ExSDP{} = sdp} = response) do
    case ExSDP.get_attribute(sdp, "control") do
      {"control", "rtsp" <> _rest = url} -> {:ok, url}
      _other -> Response.get_header(response, "Content-Base")
    end
  end

  defp base_url_of_description(response), do: Response.get_header(response, "Content-Base")

  # `SETUP` for a relative control path is first sent to the URL that this client has
  # always built: the session URL without its query, followed by the path. A server
  # that rejects it gets a second attempt with the path appended to the base URL as
  # it stands: `Content-Base` if the server sent one, the session URL with its query
  # otherwise. That is how libavformat, live555 and gortsplib build the URL in the
  # first place. Once it has worked, the remaining tracks are set up the same way
  # without the detour.
  @spec execute_setup(Request.t(), State.t()) :: {:reply, Response.result(), State.t()}
  defp execute_setup(%Request{} = request, %State{} = state) do
    request_url = Request.process_uri(request, state.uri)

    case appended_control_url(request, state) do
      url when url in [nil, request_url] ->
        handle_execute_call(request, true, state)

      url when state.append_control_to_base? ->
        handle_execute_call(%Request{request | path: url}, true, state)

      url ->
        with {:reply, {:ok, %Response{status: status}}, %State{} = state}
             when status not in 200..299 and status not in [401, 461] <-
               handle_execute_call(request, true, state) do
          Logger.warning(
            "SETUP of #{request_url} was rejected with status #{status}, " <>
              "retrying with the control path appended to the base URL: #{url}"
          )

          retry_setup(%Request{request | path: url}, state)
        end
    end
  end

  @spec retry_setup(Request.t(), State.t()) :: {:reply, Response.result(), State.t()}
  defp retry_setup(request, state) do
    case handle_execute_call(request, true, state) do
      {:reply, {:ok, %Response{status: status}} = result, %State{} = state}
      when status in 200..299 ->
        {:reply, result, %State{state | append_control_to_base?: true}}

      other ->
        other
    end
  end

  @spec appended_control_url(Request.t(), State.t()) :: binary() | nil
  defp appended_control_url(%Request{path: path}, _state) when path in [nil, "", "*"], do: nil

  defp appended_control_url(%Request{path: path}, %State{uri: %URI{} = uri} = state) do
    base = state.content_base || URI.to_string(%URI{uri | userinfo: nil})

    case {URI.parse(path), path} do
      # a control that is only a query is put right behind the base (as in gortsplib)
      {%URI{host: nil}, "?" <> _query} ->
        base <> path

      {%URI{host: nil}, _path} ->
        String.trim_trailing(base, "/") <> "/" <> String.trim_leading(path, "/")

      _absolute ->
        nil
    end
  end

  @spec do_apply_credentials(Request.t(), URI.t(), State.auth()) :: Request.t()
  defp do_apply_credentials(request, %URI{} = uri, :basic) do
    {username, password} = credentials(uri)
    encoded = Base.encode64(username <> ":" <> password)
    Request.with_header(request, "Authorization", "Basic " <> encoded)
  end

  defp do_apply_credentials(request, %URI{} = uri, {:digest, options}) do
    encoded = encode_digest(request, uri, options)
    Request.with_header(request, "Authorization", encoded)
  end

  defp do_apply_credentials(request, _url, _options) do
    request
  end

  # Reserved characters in the userinfo part of a URL are percent-encoded
  # (RFC 3986, section 3.2.1), so the credentials are decoded before use.
  # The password may be missing altogether.
  @spec credentials(URI.t()) :: {username :: String.t(), password :: String.t()}
  defp credentials(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [username, password] -> {URI.decode(username), URI.decode(password)}
      [username] -> {URI.decode(username), ""}
    end
  end

  @spec encode_digest(Request.t(), URI.t(), State.digest_opts()) :: String.t()
  defp encode_digest(request, %URI{} = uri, options) do
    {username, password} = credentials(uri)
    encoded_uri = Request.process_uri(request, uri)
    ha1 = digest_hash([username, options.realm, password], options)
    ha2 = digest_hash([request.method, encoded_uri], options)

    encode_digest_auth(username, encoded_uri, ha1, ha2, options)
  end

  defp encode_digest_auth(username, encoded_uri, ha1, ha2, %{qop: nil} = options) do
    response = digest_hash([ha1, options.nonce, ha2], options)

    "Digest " <>
      Enum.join(
        [
          ~s(username="#{username}"),
          ~s(realm="#{options.realm}"),
          ~s(nonce="#{options.nonce}"),
          ~s(uri="#{encoded_uri}"),
          ~s(response="#{response}")
        ] ++ algorithm_param(options, nil) ++ opaque_param(options),
        ", "
      )
  end

  defp encode_digest_auth(username, encoded_uri, ha1, ha2, %{qop: qop} = options) do
    nc = options[:nc] || 1
    nc_hex = :io_lib.format("~8.16.0b", [nc]) |> IO.iodata_to_binary()
    cnonce = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    response = digest_hash([ha1, options.nonce, nc_hex, cnonce, qop, ha2], options)

    "Digest " <>
      Enum.join(
        [
          ~s(username="#{username}"),
          ~s(realm="#{options.realm}"),
          ~s(nonce="#{options.nonce}"),
          ~s(uri="#{encoded_uri}"),
          ~s(response="#{response}")
        ] ++
          algorithm_param(options, qop) ++
          [
            ~s(qop=#{qop}),
            ~s(nc=#{nc_hex}),
            ~s(cnonce="#{cnonce}")
          ] ++ opaque_param(options),
        ","
      )
  end

  defp opaque_param(%{opaque: opaque}), do: [~s(opaque="#{opaque}")]
  defp opaque_param(_options), do: []

  # The algorithm is sent back only when the server named one: servers that do not
  # know the parameter reject a request that carries it unprompted. An MD5 challenge
  # without qop is answered in the RFC 2069 form, which has no such parameter.
  defp algorithm_param(%{algorithm: algorithm} = options, qop) do
    if qop != nil or sha256?(options), do: [~s(algorithm=#{algorithm})], else: []
  end

  defp algorithm_param(_options, _qop), do: []

  defp sha256?(%{algorithm: algorithm}), do: String.upcase(algorithm, :ascii) == "SHA-256"
  defp sha256?(_options), do: false

  @spec digest_hash([String.t()], State.digest_opts()) :: String.t()
  defp digest_hash(values, options) do
    data = Enum.join(values, ":")
    hash = if sha256?(options), do: :crypto.hash(:sha256, data), else: :erlang.md5(data)
    Base.encode16(hash, case: :lower)
  end

  # Some responses do not have to return the Session ID.
  # The first one received is used for the rest of the session. A server that later
  # answers with a different one is not failed for it: libavformat keeps the first
  # identifier as well, and failing here would cost a reply that is otherwise fine.
  @spec handle_session_id(Response.t(), State.t()) :: {:ok, State.t()}
  defp handle_session_id(%Response{} = response, %State{} = state) do
    case Response.parse_session_header(response) do
      {:ok, %{session_id: session_id}} ->
        case state do
          %State{session_id: nil} ->
            {:ok, %State{state | session_id: session_id}}

          %State{session_id: ^session_id} ->
            {:ok, state}

          %State{session_id: current_session_id} ->
            Logger.warning(
              "Server answered with session id #{inspect(session_id)}, " <>
                "keeping #{inspect(current_session_id)} that was established first"
            )

            {:ok, state}
        end

      {:error, :no_such_header} ->
        {:ok, state}
    end
  end

  # Picks the authentication scheme from the `WWW-Authenticate` challenges of a response.
  #
  # A server may send several challenges, one per header (RFC 2617, section 1.2).
  # Digest is preferred over Basic whatever their order. Scheme and parameter names are
  # case-insensitive and values may be quoted strings or bare tokens.
  @spec detect_authentication_type(Response.t(), State.t()) :: {:ok, State.t()}
  defp detect_authentication_type(%Response{headers: headers}, state) do
    challenges =
      for {name, value} <- headers,
          String.downcase(name, :ascii) == "www-authenticate",
          challenge <- parse_challenges(value),
          do: challenge

    case challenges do
      [] -> {:ok, state}
      challenges -> {:ok, %{state | auth: select_auth(challenges)}}
    end
  end

  # A header usually carries one challenge, but may carry several, separated by commas
  # like the parameters are (RFC 2617, section 1.2). A new challenge starts where a
  # scheme name stands in front of a parameter. Within a challenge the first
  # occurrence of a parameter counts.
  @spec parse_challenges(binary()) :: [{scheme :: binary(), params :: %{binary() => binary()}}]
  defp parse_challenges(header) when byte_size(header) > @max_challenge_size do
    Logger.warning("Ignoring a WWW-Authenticate header of #{byte_size(header)} bytes")
    []
  end

  defp parse_challenges(header) do
    ~r/(?:([A-Za-z][A-Za-z0-9_-]*)[ \t]+)?([A-Za-z0-9_-]+)[ \t]*=[ \t]*(?:"([^"]*)"|([^\s,]*))/
    |> Regex.scan(header)
    |> Enum.reduce([], fn [_match, scheme, name | value], challenges ->
      param = {String.downcase(name, :ascii), List.last(value)}

      case {scheme, challenges} do
        {"", [{scheme, params} | rest]} -> [{scheme, [param | params]} | rest]
        {"", []} -> []
        {scheme, challenges} -> [{String.downcase(scheme, :ascii), [param]} | challenges]
      end
    end)
    |> case do
      # a scheme alone, without any parameter
      [] ->
        [{header |> String.trim() |> String.downcase(:ascii), %{}}]

      challenges ->
        for {scheme, params} <- Enum.reverse(challenges), do: {scheme, Map.new(params)}
    end
  end

  @spec select_auth([{binary(), map()}]) :: State.auth()
  defp select_auth(challenges) do
    digests = for {"digest", params} <- challenges, options = digest_options(params), do: options

    # MD5 is what this client has always answered with, so it stays the first choice.
    # SHA-256 (RFC 7616) is used when the server offers nothing else.
    digest = Enum.find(digests, &(not sha256?(&1))) || List.first(digests)

    cond do
      digest != nil ->
        {:digest, digest}

      List.keymember?(challenges, "basic", 0) ->
        :basic

      true ->
        schemes = Enum.map_join(challenges, ", ", &elem(&1, 0))

        Logger.warning(
          "No usable authentication challenge among: #{schemes}, falling back to Basic"
        )

        :basic
    end
  end

  @spec digest_options(map()) :: State.digest_opts() | nil
  defp digest_options(params) do
    algorithm = params["algorithm"]

    cond do
      params["nonce"] in [nil, ""] ->
        Logger.warning("Ignoring a Digest challenge without a nonce")
        nil

      algorithm != nil and String.upcase(algorithm, :ascii) not in ["MD5", "SHA-256"] ->
        Logger.warning("Ignoring a Digest challenge with unsupported algorithm #{algorithm}")
        nil

      true ->
        options = %{
          nonce: params["nonce"],
          realm: params["realm"] || "",
          qop: select_qop(params["qop"]),
          nc: 1
        }

        # The server expects `opaque` back unchanged (RFC 2617, section 3.2.1),
        # and `algorithm` only when it named one.
        Enum.reduce([opaque: params["opaque"], algorithm: algorithm], options, fn
          {_key, nil}, options -> options
          {key, value}, options -> Map.put(options, key, value)
        end)
    end
  end

  # Only `auth` is implemented. When the server offers a list, `auth` is taken from it;
  # when it offers none we can do, the RFC 2069 response without qop is used.
  @spec select_qop(binary() | nil) :: binary() | nil
  defp select_qop(nil), do: nil

  defp select_qop(qop) do
    options = qop |> String.split(",") |> Enum.map(&String.trim/1)

    if "auth" in options do
      "auth"
    else
      Logger.warning("Unsupported Digest qop #{inspect(qop)}, authenticating without qop")
      nil
    end
  end
end
