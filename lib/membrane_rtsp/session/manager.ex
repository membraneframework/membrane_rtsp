defmodule Membrane.RTSP.Session.Manager do
  @moduledoc false
  use GenServer

  alias Membrane.RTSP.{Request, Response, Transport}
  import Membrane.RTSP.Manager.Logic
  alias Membrane.RTSP.Manager.Logic.State

  @user_agent "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Client)"

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
  def request(session, request, timeout \\ :infinity) do
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
end
