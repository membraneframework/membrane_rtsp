defmodule Membrane.RTSP.Session.Manager do
  @moduledoc false
  use GenServer

  alias Membrane.RTSP.{Request, Response, Transport}

  @user_agent "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Client)"

  defmodule State do
    @moduledoc false
    @enforce_keys [:transport, :uri]
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
    @type t :: %__MODULE__{
            transport: Transport.t(),
            cseq: non_neg_integer(),
            uri: URI.t(),
            session_id: binary() | nil,
            auth: nil | :basic | {:digest, digest_opts()},
            execution_options: Keyword.t()
          }
  end

  @doc """
  Starts and links session process.

  Sets following properties of Session:
    * transport - information for executing request over the network. For
    reference see `Membrane.RTSP.Transport`
    * url - a base path for requests
    * options - a keyword list that shall be passed when executing request over
    transport
  """
  @spec start_link(Transport.t(), binary(), Keyword.t()) :: GenServer.on_start()
  def start_link(transport, url, options) do
    GenServer.start_link(__MODULE__, %{
      transport: transport,
      url: url,
      options: options
    })
  end

  @spec request(pid(), Request.t(), non_neg_integer()) :: {:ok, Response.t()} | {:error, atom()}
  def request(session, request, timeout \\ 5000) do
    GenServer.call(session, {:execute, request}, timeout)
  end

  @impl true
  def init(%{transport: transport, url: url, options: options}) do
    auth_type =
      case url do
        %URI{userinfo: nil} -> nil
        # default to basic. If it is actually digest, it will get set
        # when the correct header is detected
        %URI{userinfo: info} when is_binary(info) -> :basic
      end

    state = %State{
      transport: transport,
      uri: url,
      execution_options: options,
      auth: auth_type
    }

    {:ok, state}
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
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp execute(request, state) do
    %State{cseq: cseq, transport: transport, uri: uri, execution_options: options} = state

    request
    |> Request.with_header("CSeq", cseq |> to_string())
    |> Request.with_header("User-Agent", @user_agent)
    |> apply_credentials(uri, state.auth)
    |> Request.stringify(uri)
    |> transport.module.execute(transport.key, options)
  end

  defp apply_credentials(request, %URI{userinfo: nil}, _auth_options), do: request

  defp apply_credentials(%Request{headers: headers} = request, uri, auth) do
    case List.keyfind(headers, "Authorization", 0) do
      {"Authorization", _} ->
        request

      _ ->
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

  defp do_apply_credentials(request, _, _) do
    request
  end

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

  defp md5(value) do
    value
    |> Enum.join(":")
    |> IO.iodata_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end

  # Some responses do not have to return the Session ID
  # If it does return one, it needs to match one stored in the state.
  defp handle_session_id(%Response{} = response, state) do
    with {:ok, session_value} <- Response.get_header(response, "Session") do
      [session_id | _] = String.split(session_value, ";")

      case state do
        %State{session_id: nil} -> {:ok, %State{state | session_id: session_id}}
        %State{session_id: ^session_id} -> {:ok, state}
        _ -> {:error, :invalid_session_id}
      end
    else
      {:error, :no_such_header} -> {:ok, state}
    end
  end

  # Checks for the `nonce` and `realm` values in the `WWW-Authenticate` header.
  # if they exist, sets `type` to `{:digest, opts}`
  defp detect_authentication_type(%Response{} = response, state) do
    with {:ok, "Digest " <> digest} <- Response.get_header(response, "WWW-Authenticate") do
      [_, nonce] = Regex.run(~r/nonce=\"(?<nonce>.*)\"/U, digest)
      [_, realm] = Regex.run(~r/realm=\"(?<realm>.*)\"/U, digest)
      auth_options = %{type: {:digest, %{nonce: nonce, realm: realm}}}
      {:ok, %{state | auth_options: auth_options}}
    else
      # non digest auth?
      {:ok, _} ->
        {:ok, %{state | auth_options: %{state.auth_options | type: :basic}}}

      {:error, :no_such_header} ->
        {:ok, state}
    end
  end
end
