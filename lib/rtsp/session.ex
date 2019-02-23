defmodule Membrane.RTSP.Session do
  use GenServer
  use Bunch

  alias __MODULE__.ConnectionInfo
  alias Membrane.RTSP.{Request, Response}

  defmodule State do
    # TODO enforce keys
    defstruct [:transport, :cseq, :connection_info, :transport_executor]

    @type t :: %__MODULE__{
            transport: module(),
            cseq: non_neg_integer(),
            connection_info: ConnectionInfo.t(),
            transport_executor: pid()
          }
  end

  def start_link(uri, transport) do
    # TODO: There is a lot uri as url and url as uri, that needs sorting out
    GenServer.start_link(__MODULE__, %{transport: transport, url: uri})
  end

  @spec init(%{transport: any(), url: binary() | URI.t()}) ::
          {:stop, :invalid_url} | {:ok, Membrane.RTSP.Session.State.t()}
  def init(%{transport: transport, url: url}) do
    with {:ok, info} <- ConnectionInfo.from_url(url),
         # TODO: Should it be linked or should it be supervised
         {:ok, pid} <- transport.start_transport(info) do
      {:ok, %State{transport: transport, cseq: 0, connection_info: info, transport_executor: pid}}
    end
  end

  @spec execute(pid(), Request.t()) :: {:ok, Response.t()} | {:error, atom()}
  def execute(session, request) do
    # Maybe configure timeout somehow?
    GenServer.call(session, {:execute, request})
  end

  def handle_call({:execute, request}, _from, %State{cseq: cseq} = state) do
    with {:ok, raw_response} <- perform_execution(request, state),
         {:ok, parsed_respone} <- Response.parse(raw_response) do
      state = %State{state | cseq: cseq + 1}
      {:reply, parsed_respone, state}
    end
  end

  defp perform_execution(request, state) do
    %State{cseq: cseq, transport: transport, transport_executor: executor} = state
    # TODO cseq should increment

    request
    |> Request.with_header({"cseq", cseq})
    |> to_string()
    |> IO.inspect()
    |> transport.execute(executor)
  end
end
