defmodule Membrane.RTSP.Server.Handler do
  @moduledoc """
  Behaviour describing client request handling for Real Time Streaming Protocol.

  In a typical RTSP session where the client requests a media stream from a server, the
  interactions goes as follows:

  ```mermaid
  sequenceDiagram
      participant C as Client
      participant S as RTSP Server

      C->>+S: connect to the server (rtsp://server_host:554/stream)
      S->>-C: connection accepted

      note right of C: Get supported methods
      C->>+S: OPTIONS rtsp://server_host:554/stream
      S->>-C: List of allowed methods

      note right of C: Get the media description
      C->>+S: DESCRIBE rtsp://server_host:554/stream
      S->>-C: Media description (usually as an SDP)

      note right of C: Setup the video
      C->>+S: SETUP rtsp://server_host:554/stream/video
      S->>-C: Video track setup (returns also a session id)

      note right of C: Setup the audio
      C->>+S: SETUP rtsp://server_host:554/stream/audio
      S->>-C: Audio track setup

      note right of C: Start playing the media
      C->>+S: PLAY rtsp://server_host:554/stream/audio
      S->>-C: Video/audio data are sent to the client via UDP, TCP or Multicast

      note right of C: Stop and free the resources
      C->>+S: TEARDOWN rtsp://server_host:554/stream/audio
      S->>-C: Media streaming stopped and resources are freed
  ```

  We omitted other methods for brevity such as `GET_PARAMETER` where the client wants to keep the
  session alive and `PAUSE` to pause streaming without freeing the resources used by the session.

  ## Response
  The handler is responsible for returning the right response and managing the media resources
  while the server will be responsible for parsing client request, calling the handler callbacks
  and forwarding the response to the client.

  Except for `c:handle_describe/2` where the handler should return the media description (usually as an SDP),
  the handler need only to set the response status using `Membrane.RTSP.Response.new/1`. In most cases
  the handler should not try to set the headers itself except for `WWW-Authenticate` in case authentication
  using `basic` or `digest` is required.

  ## State
  The handler may need to keep some state between the callback calls. To achieve this, the returned value from
  `c:init/1` callback will be used as a state and will be the last argument for the other callbacks.

  > #### `Missing callbacks in the handler` {: .info}
  >
  > You may notice that some methods have no corresponding callback, the reason for this is:
  >
  > `OPTIONS` apply to the server itself, not to individual presentation or resources
  >
  > `GET_PARAMETER` is used to keep the session alive and the server is responsible for setting session timeout
  >
  > The other methods are not yet implemented.

  ## `use Membrane.RTSP.Server.Handler` {: .info}
  When you `use Membrane.RTSP.Server.Handler`, the module will set `@behaviour Membrane.RTSP.Server.Handler` and
  define the default implementation for `init/1` callback.
  """

  alias Membrane.RTSP.{Request, Response}

  @typedoc """
  Any term that will be used to keep state between the callbacks.
  """
  @type state :: term()
  @type config :: term()
  @type control_path :: binary()
  @type ssrc :: non_neg_integer()
  @type conn :: :inet.socket()
  @type request :: Request.t()

  @typedoc """
  A type representing the configured media context.

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
  @type configured_media_context :: %{
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
  Optional callback called when the server is initialized.

  The argument is a term passed to the server as the `handler_config` option.
  The returned value will be used as a state and passed as the last
  argument to the subsequent callbacks.

  Default behavior is to return the argument unchanged.
  """
  @callback init(config()) :: state()

  @doc """
  Callback called when a new connection is established.
  """
  @callback handle_open_connection(conn(), state()) :: state()

  @doc """
  Callback called when a connection is closed.

  A handler may not receive a `TEARDOWN` request to free resources, so it
  can use this callback to do it.
  """
  @callback handle_closed_connection(state()) :: :ok

  @doc """
  Callback called when receiving a DESCRIBE request.

  The return value is the response to be sent back to the client. The implementing
  module need at least set the status of the response.
  """
  @callback handle_describe(request(), state()) :: {Response.t(), state()}

  @doc """
  Callback called when receiving an ANNOUNCE request.

  An announce request contains media description (`body` field of the request) of
  the tracks that a client wish to publish to the server.
  """
  @callback handle_announce(request(), state()) :: {Response.t(), state()}

  @doc """
  Callback called when receiving a SETUP request.

  The handler should check for the validity of the requested track (`path` field of the `Request` struct).

  The `mode` argument provides the context of the setup, it's either `:play` or `:record`.
  """
  @callback handle_setup(request(), mode :: :play | :record, state()) :: {Response.t(), state()}

  @doc """
  Callback called when receiving a PLAY request.

  `configured_media_context` contains the needed information to start sending media packets.
  Refer to the type documentation for more details
  """
  @callback handle_play(configured_media_context(), state()) :: {Response.t(), state()}

  @doc """
  Callback called when receiving a RECORD request.

  `configured_media_context` contains the needed information to start receving media packets.
  Refer to the type documentation for more details
  """
  @callback handle_record(configured_media_context(), state()) :: {Response.t(), state()}

  @doc """
  Callback called when receiving a PAUSE request.

  Upon receiving a PAUSE request, the server should stop sending media data, however
  the resources should not be freed. If the stream cannot be stopped (e.g. live view), this callback
  should return `501` (Not Implemented) response.
  """
  @callback handle_pause(state()) :: {Response.t(), state()}

  @doc """
  Callback called when receiving TEARDOWN request.

  The implementer should stop sending media packets and free resources used by
  the session.
  """
  @callback handle_teardown(state()) :: {Response.t(), state()}

  @optional_callbacks init: 1, handle_announce: 2, handle_record: 2

  defmacro __using__(_options) do
    quote do
      @behaviour unquote(__MODULE__)

      @impl true
      def init(config), do: config

      @impl true
      def handle_open_connection(_conn, state), do: state

      @impl true
      def handle_announce(_req, state), do: {Response.new(501), state}

      @impl true
      def handle_record(_req, state), do: {Response.new(501), state}

      @impl true
      def handle_pause(state), do: {Response.new(501), state}

      @impl true
      def handle_closed_connection(_state), do: :ok

      defoverridable init: 1,
                     handle_open_connection: 2,
                     handle_announce: 2,
                     handle_record: 2,
                     handle_pause: 1,
                     handle_closed_connection: 1
    end
  end
end
