defmodule Membrane.RTSP.Logic do
  @moduledoc """
  Logic for RTSP session
  """
  alias Membrane.RTSP.{Request, Response}
  @user_agent "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Client)"

  defmodule State do
    @moduledoc "Struct representing the state of RTSP session"
    @enforce_keys [:transport, :uri, :transport_module]
    defstruct @enforce_keys ++
                [
                  :session_id,
                  cseq: 0,
                  execution_options: [],
                  auth: nil
                ]

    @type digest_opts() :: %{
            realm: String.t() | nil,
            nonce: String.t() | nil
          }

    @type auth_t() :: nil | :basic | {:digest, digest_opts()}

    @type t :: %__MODULE__{
            transport: any(),
            cseq: non_neg_integer(),
            uri: URI.t(),
            session_id: binary() | nil,
            auth: auth_t(),
            execution_options: Keyword.t()
          }
  end

  @spec user_agent() :: binary()
  def user_agent(), do: @user_agent

  @spec execute(Request.t(), State.t(), boolean()) ::
          :ok | {:ok, binary()} | {:error, reason :: any()}
  def execute(request, state, get_reply \\ true) do
    %State{
      cseq: cseq,
      transport: transport,
      transport_module: transport_module,
      uri: uri,
      session_id: session_id
    } = state

    request
    |> inject_session_header(session_id)
    |> Request.with_header("CSeq", cseq |> to_string())
    |> Request.with_header("User-Agent", @user_agent)
    |> apply_credentials(uri, state.auth)
    |> Request.stringify(uri)
    |> transport_module.execute(transport, state.execution_options, get_reply: get_reply)
  end

  @spec inject_session_header(Request.t(), binary()) :: Request.t()
  def inject_session_header(request, session_id) do
    case session_id do
      nil -> request
      session -> Request.with_header(request, "Session", session)
    end
  end

  @spec apply_credentials(Request.t(), URI.t(), State.auth_t()) :: Request.t()
  def apply_credentials(request, %URI{userinfo: nil}, _auth_options), do: request

  def apply_credentials(%Request{headers: headers} = request, uri, auth) do
    case List.keyfind(headers, "Authorization", 0) do
      {"Authorization", _value} ->
        request

      _else ->
        do_apply_credentials(request, uri, auth)
    end
  end

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
  def encode_digest(request, %URI{userinfo: userinfo} = uri, options) do
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
  def md5(value) do
    value
    |> Enum.join(":")
    |> IO.iodata_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end

  # Some responses do not have to return the Session ID
  # If it does return one, it needs to match one stored in the state.
  @spec handle_session_id(Response.t(), State.t()) :: {:ok, State.t()} | {:error, reason :: any()}
  def handle_session_id(%Response{} = response, state) do
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
  def detect_authentication_type(%Response{} = response, state) do
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
