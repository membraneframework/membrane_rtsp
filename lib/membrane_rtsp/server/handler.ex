defmodule Membrane.RTSP.Server.Handler do
  @moduledoc """
  Behaviour describing client request handling for Real Time Streaming Protocol.
  """

  alias Membrane.RTSP.{Request, Response}

  @typedoc """
  Any term that will be used to keep state between the callbacks.
  """
  @type state :: term()
  @type control_path :: binary()
  @type ssrc :: integer()
  @type conn :: :inet.socket()
  @type request :: Request.t()

  @typedoc """
  A type representing the setupped tracks.

  The type is a map from a control path to the setup details. Each track contains the
  following information:
    * `ssrc` - The synchronisation source to use in the `RTP` packets.
    * `transport` - The transport used for carrying the media packets.
    * `tcp_socket` - An already open socket to use to send muxed `RTP` and `RTCP` packets. Available only when transport is `TCP`.
    * `channels` - A pair of channel numbers to include in the `RTP` and `RTCP` packets. Available only when transport is `TCP`
    * `rtp_socket` - An already open socket to use to send `RTP` packets. Available only when transport is `UDP`.
    * `rtcp_socket` - An already open socket to use to send `RTCP` packets. Available only when transport is `UDP`.
    * `client_port` - A pair of ports to use to send `RTP` and `RTCP` packets respectively. Available only when transport is `UDP`
    * `address` - An ip address where to send `RTP` and `RTCP` packets. Available only when transport is `UDP`

  """
  @type setupped_tracks :: %{
          control_path() => %{
            :ssrc => ssrc(),
            :transport => :UDP | :TCP,
            optional(:tcp_socket) => conn(),
            optional(:channels) => {non_neg_integer(), non_neg_integer()},
            optional(:rtp_socket) => conn(),
            optional(:rtcp_socket) => conn(),
            optional(:address) => :inet.ip_address(),
            optional(:client_port) => {:inet.port_number(), :inet.port_number()}
          }
        }

  @doc """
  Callback called when a new connection is established.

  The returned value is used as a state and is passed as the last argument to
  the subsequent callbacks
  """
  @callback handle_open_connection(conn()) :: state()

  @doc """
  Callback called when receiving a DESCRIBE request.

  The return value is the response to be sent back to the client. The implementing
  module need at least set the status of the response.
  """
  @callback handle_describe(state(), request()) :: {Response.t(), state()}

  @doc """
  Callback called when receiving a SETUP request.

  The handler should check for the validity of the requested track (`path` field of the `Request` struct).
  """
  @callback handle_setup(request(), state()) :: {Response.t(), state()}

  @doc """
  Callback called when receiving a PLAY request.

  `setupped_tracks` contains the needed information to start sending media packets.
  Refer to the type documentation for more details
  """
  @callback handle_play(setupped_tracks(), state()) :: {Response.t(), state()}

  @doc """
  Callback called when receiving TEARDOWN request.

  The implementer should stop sending media packets and free resources used by
  the session.
  """
  @callback handle_teardown(state()) :: {Response.t(), state()}
end
