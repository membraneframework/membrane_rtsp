defmodule Membrane.Protocol.RTSP.Session do
  use GenServer
  use Bunch

  alias __MODULE__.ConnectionInfo
  alias Membrane.Protocol.RTSP.{Request, Response}
  alias Membrane.Protocol.RTSP.Transport.Supervisor

  defmodule State do
    # TODO enforce keys
    defstruct [:transport, :cseq, :uri, :connection_info, :transport_executor]

    @type t :: %__MODULE__{
            transport: module(),
            cseq: non_neg_integer(),
            uri: binary(),
            connection_info: ConnectionInfo.t(),
            transport_executor: binary()
          }
  end

  # TODO make transport a registered process

  def start_link(uri, transport) do
    # TODO: There is a lot uri as url and url as uri, that needs sorting out
    GenServer.start_link(__MODULE__, %{transport: transport, url: uri})
  end

  @spec init(%{transport: any(), url: binary() | URI.t()}) ::
          {:stop, :invalid_url} | {:ok, Membrane.Protocol.RTSP.Session.State.t()}
  def init(%{transport: transport, url: url}) do
    ref = :os.system_time(:millisecond) |> to_string() ~> (&1 <> url)

    with {:ok, info} <- ConnectionInfo.from_url(url),
         # TODO: Should it be linked or should it be supervised
         {:ok, _pid} <- Supervisor.start_child(transport, ref, info) do
      %State{
        transport: transport,
        cseq: 0,
        connection_info: info,
        transport_executor: ref,
        uri: url
      }
      ~> {:ok, &1}
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
         {:ok, parsed_respone} <- Response.parse(raw_response) do
      state = %State{state | cseq: cseq + 1}
      {:reply, {:ok, parsed_respone}, state}
    else
      # TODO: test this behaviour
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp perform_execution(request, %State{uri: uri} = state) do
    %State{cseq: cseq, transport: transport, transport_executor: executor} = state

    request
    |> Request.with_header({"cseq", cseq})
    |> Request.to_string(uri)
    |> transport.execute(executor |> name())
  end

  defp name(ref), do: {:via, Registry, {TransportRegistry, ref}}
end
