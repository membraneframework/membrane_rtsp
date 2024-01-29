defmodule Membrane.RTSP.Server.Handler do
  @moduledoc """
  Behaviour describing client request handling for Real Time Streaming Protocol
  """

  alias Membrane.RTSP.Request

  @type state :: term()
  @type ssrc :: integer() | binary()

  @doc """
  Callback for initializing state.

  The state will be passed on the subsequent callbacks as the first argument
  """
  @callback init() :: state()

  @doc """
  Callback for handling OPTIONS client request.

  The result of this callback is ignored.
  """
  @callback handle_options(state(), Request.t()) :: state()

  @doc """
  Callback for handling DESCRIBE client request.

  `{return_value, new_state}` is the result from calling this callback, the `new_state` will be sent to the subsequent callbacks and
  the `return_value` is used by the server to set the right status code:
    - `{:ok, sdp or binary}` - The server will send a 200 status code with the returned binary or SDP as the body.
    - `{:error, :unauthorized}` - The server will send a 401 status code.
    - `{:error, :forbidden}` - The server will send a 403 status code.
    - `{:error, :not_found}` - The server will send a 404 status code.
    - `{:error, other}` - The server will send a 400 status code.
  """
  @callback handle_describe(state(), Request.t()) ::
              {{:ok, ExSDP.t() | binary()}, state()} | {{:error, term()}, state()}

  @doc """
  Callback for handling SETUP client request.

  The handler is responsible for checking the validity of the requested URI (`path` field of the `Request` struct )
  and return an error in case the same URI is setup more than once.

  It should return the `ssrc` that'll be used in the RTP paylad. The server will set the proper status code
  depending on the response. Check `handle_describe` for details.
  """
  @callback handle_setup(state(), Request.t()) ::
              {{:ok, ssrc}, state()} | {{:error, term()}, state()}

  @doc """
  Callback for handling PLAY client request.

  The implementer should start sending media data to the client. Since the
  client will use the same connection as the RTSP session, a `socket` will passed
  as a second argument to this callback. Be careful to not to try reading from the
  socket as this may cause issues with the RTSP session.
  """
  @callback handle_play(state(), :inet.socket()) :: {:ok, state()} | {{:error, term()}, state()}

  @doc """
  Callback for handling TEARDOWN client request.
  """
  @callback handle_teardown(state()) :: :ok
end
