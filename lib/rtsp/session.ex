defmodule Membrane.Protocol.RTSP.Session do
  @moduledoc """
  This module is responsible for managing RTSP Session.

  Handles request resolution and tracking of Session ID and CSeq.
  """
  use GenServer

  alias Membrane.Protocol.RTSP.{Request, Response, Transport}

  @user_agent "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Client)"

  defmodule State do
    @moduledoc false
    @enforce_keys [:transport, :uri, :transport_executor]
    defstruct @enforce_keys ++ [{:cseq, 0}, :session_id, {:execution_options, []}]

    @type t :: %__MODULE__{
            transport: module(),
            cseq: non_neg_integer(),
            uri: URI.t(),
            transport_executor: binary(),
            session_id: binary() | nil,
            execution_options: Keyword.t()
          }
  end

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, args}
    }
  end

  @doc """
  Starts and links session process.

  Sets following properties of Session:
    * transport - module that is responsible for executing request
    * transport_executor - a reference (`Registry` key) that will be used
    when executing request
    * url - a base path for requests
    * options - a keyword list that shall be passed when executing request over transport
  """
  @spec start_link(module(), binary(), binary(), Keyword.t()) :: GenServer.on_start()
  def start_link(transport, transport_executor, url, options) do
    GenServer.start_link(__MODULE__, %{
      transport: transport,
      url: url,
      transport_executor: transport_executor,
      options: options
    })
  end

  @doc """
  Executes the request on a given session.

  Before execution populates with default headers setting `Session`
  and `User-Agent` header. If URI contains credentials they will also
  be added unless `Authorization` header is present in request.
  """
  @spec execute(pid(), Request.t(), non_neg_integer()) :: {:ok, Response.t()} | {:error, atom()}
  def execute(session, request, timeout \\ 5000) do
    GenServer.call(session, {:execute, request}, timeout)
  end

  @impl true
  def init(%{transport: transport, url: url, transport_executor: ref, options: options}) do
    state = %State{
      transport: transport,
      transport_executor: ref,
      uri: url,
      execution_options: options
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:execute, request}, _from, %State{cseq: cseq} = state) do
    with {:ok, raw_response} <- perform_execution(request, state),
         {:ok, parsed_response} <- Response.parse(raw_response),
         {:ok, state} <- handle_session_id(parsed_response, state) do
      state = %State{state | cseq: cseq + 1}
      {:reply, {:ok, parsed_response}, state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp perform_execution(request, %State{uri: uri, execution_options: options} = state) do
    %State{cseq: cseq, transport: transport, transport_executor: executor} = state
    transport_ref = Transport.transport_name(executor)

    request
    |> Request.with_header("CSeq", cseq)
    |> Request.with_header("User-Agent", @user_agent)
    |> apply_credentials(uri)
    |> Request.stringify(uri)
    |> transport.execute(transport_ref, options)
  end

  defp apply_credentials(request, %URI{userinfo: nil}), do: request

  defp apply_credentials(%Request{headers: headers} = request, %URI{userinfo: info}) do
    case List.keyfind(headers, "Authorization", 0) do
      {"Authorization", _} ->
        request

      _ ->
        encoded = Base.encode64(info)
        Request.with_header(request, "Authorization", "Basic " <> encoded)
    end
  end

  # Some responses does not have to return Session ID
  # If it does return one it needs to match one stored in state
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
end
