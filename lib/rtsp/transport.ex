defmodule Membrane.RTSP.Transport do
  alias Membrane.RTSP.Session.ConnectionInfo

  # TODO: Change me
  @callback start_transport(ConnectionInfo.t()) :: :ignore | {:error, atom()} | {:ok, pid()}
  @callback execute(binary(), pid(), [tuple()]) :: binary()
end
