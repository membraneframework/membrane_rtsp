defmodule Membrane.Protocol.RTSP.Session do
  use GenServer
  use Bunch

  alias Membrane.Protocol.RTSP.{Request, Response}
  alias Membrane.Protocol.RTSP.Transport
  alias Membrane.Protocol.RTSP.Transport.Supervisor

  # TODO: Change me
  # Maybe something similar but with version
  @user_agent "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Client)"

  # TODO implement session close

  defmodule State do
    # TODO enforce keys
    defstruct [:transport, {:cseq, 0}, :uri, :transport_executor, :session_id]

    @type t :: %__MODULE__{
            transport: module(),
            cseq: non_neg_integer(),
            uri: URI.t(),
            transport_executor: binary(),
            session_id: binary() | nil
          }
  end

  # TODO make transport a registered process

  def start_link(uri, transport) do
    GenServer.start_link(__MODULE__, %{transport: transport, url: uri})
  end

  @spec init(%{transport: any(), url: binary() | URI.t()}) ::
          {:stop, :invalid_url} | {:ok, Membrane.Protocol.RTSP.Session.State.t()}
  def init(%{transport: transport, url: url}) do
    ref = :os.system_time(:millisecond) |> to_string() ~> (&1 <> url)

    with %URI{port: port, host: host, scheme: "rtsp"} = uri
         when is_number(port) and is_binary(host) <- URI.parse(url),
         {:ok, _pid} <- Supervisor.start_child(transport, ref, uri) do
      %State{
        transport: transport,
        transport_executor: ref,
        uri: uri
      }
      ~> {:ok, &1}
    else
      %URI{} -> {:stop, :invalid_uri}
      {:error, reason} -> {:stop, reason}
    end
  end

  @spec execute(pid(), Request.t()) :: {:ok, Response.t()} | {:error, atom()}
  def execute(session, request) do
    # Maybe configure timeout somehow?
    # Should I handle timeout
    try do
      GenServer.call(session, {:execute, request})
    catch
      exit: _ -> {:error, :timeout}
    end
  end

  def handle_call({:execute, request}, _from, %State{cseq: cseq} = state) do
    with {:ok, raw_response} <- perform_execution(request, state),
         {:ok, parsed_respone} <- Response.parse(raw_response),
         {:ok, state} <- handle_session_id(parsed_respone, state) do
      # Should I bump cseq if request fails?
      state = %State{state | cseq: cseq + 1}
      {:reply, {:ok, parsed_respone}, state}
    else
      # TODO: test this behaviour
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp perform_execution(request, %State{uri: uri} = state) do
    %State{cseq: cseq, transport: transport, transport_executor: executor} = state
    transport_ref = Transport.transport_name(executor)

    request
    |> Request.with_header("CSeq", cseq)
    |> Request.with_header("User-Agent", @user_agent)
    |> apply_credentials(uri)
    |> Request.to_string(uri)
    |> transport.execute(transport_ref)
  end

  defp apply_credentials(request, %URI{userinfo: nil}), do: request

  defp apply_credentials(request, %URI{userinfo: info}),
    do: info |> Base.encode64() ~> Request.with_header(request, "Authorization", "Basic " <> &1)

  # Some responses does not have to return Session ID
  # If it does return one it needs to match one stored in state
  defp handle_session_id(%Response{} = response, state) do
    with {:ok, session_value} <- Response.get_header(response, "Session") do
      [session_id | _] = String.split(session_value, ";")

      case state do
        %State{session_id: nil} -> %State{state | session_id: session_id} ~> {:ok, &1}
        %State{session_id: ^session_id} -> {:ok, state}
        _ -> {:error, :invalid_session_id}
      end
    else
      {:error, :no_such_header} -> {:ok, state}
    end
  end
end
