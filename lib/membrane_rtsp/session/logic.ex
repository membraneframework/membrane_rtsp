defmodule Membrane.RTSP.Manager.Logic do
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

  def execute(request, state) do
    %State{
      cseq: cseq,
      transport: transport,
      uri: uri,
      session_id: session_id,
      execution_options: options
    } = state

    request
    |> inject_session_header(session_id)
    |> Request.with_header("CSeq", cseq |> to_string())
    |> Request.with_header("User-Agent", @user_agent)
    |> apply_credentials(uri, state.auth)
    |> Request.stringify(uri)
    |> transport.module.execute(transport)
  end

  def inject_session_header(request, session_id) do
    case session_id do
      nil -> request
      session -> Request.with_header(request, "Session", session)
    end
  end

  def apply_credentials(request, %URI{userinfo: nil}, _auth_options), do: request

  def apply_credentials(%Request{headers: headers} = request, uri, auth) do
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

  def md5(value) do
    value
    |> Enum.join(":")
    |> IO.iodata_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end

  # Some responses do not have to return the Session ID
  # If it does return one, it needs to match one stored in the state.
  def handle_session_id(%Response{} = response, state) do
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
  def detect_authentication_type(%Response{} = response, state) do
    with {:ok, "Digest " <> digest} <- Response.get_header(response, "WWW-Authenticate") do
      [_, nonce] = Regex.run(~r/nonce=\"(?<nonce>.*)\"/U, digest)
      [_, realm] = Regex.run(~r/realm=\"(?<realm>.*)\"/U, digest)
      auth_options = {:digest, %{nonce: nonce, realm: realm}}
      {:ok, %{state | auth: auth_options}}
    else
      # non digest auth?
      {:ok, _} ->
        {:ok, %{state | auth: :basic}}

      {:error, :no_such_header} ->
        {:ok, state}
    end
  end
end
