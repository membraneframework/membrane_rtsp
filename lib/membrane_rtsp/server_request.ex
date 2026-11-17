defmodule Membrane.RTSP.ServerRequest do
  @moduledoc false
  # Requests that the server sends on the client's connection.
  #
  # RFC 2326 allows OPTIONS, GET_PARAMETER, SET_PARAMETER, ANNOUNCE and REDIRECT in
  # that direction, and some servers use the first three to check that the client is
  # still there. Those are confirmed, the way GStreamer does; libavformat confirms the
  # first two. The session does not act on any other request and says so with 501.

  require Logger

  alias Membrane.RTSP.Response

  @methods ~w(OPTIONS GET_PARAMETER SET_PARAMETER ANNOUNCE REDIRECT PLAY_NOTIFY
              DESCRIBE SETUP PLAY PAUSE RECORD TEARDOWN)
  @confirmed_methods ~w(OPTIONS GET_PARAMETER SET_PARAMETER)

  @doc """
  Tells whether the data starts with the request line of an RTSP request.
  """
  @spec request?(binary()) :: boolean()
  for method <- @methods do
    def request?(<<unquote(method), separator, _rest::binary>>) when separator in [?\s, ?\t],
      do: true
  end

  def request?(_data), do: false

  @doc """
  Renders the response to a complete request received from the server.
  """
  @spec reply(binary()) :: binary()
  def reply(request) do
    [method | _rest] = String.split(request, [" ", "\t"], parts: 2)
    {headers, _body} = split_headers(request)

    status =
      if method in @confirmed_methods do
        Logger.debug("Confirming the #{method} request sent by the RTSP server")
        200
      else
        Logger.warning(
          "The RTSP server sent a #{method} request, which is not supported, answering 501"
        )

        501
      end

    # The server matches the reply by CSeq and, if it sent one, by Session.
    echoed =
      for name <- ["CSeq", "Session"],
          value = header(headers, name),
          do: {name, value}

    Response.stringify(%Response{Response.new(status) | headers: echoed})
  end

  defp split_headers(request) do
    case String.split(request, ["\r\n\r\n", "\n\n", "\r\r"], parts: 2) do
      [headers, body] -> {headers, body}
      [headers] -> {headers, ""}
    end
  end

  defp header(headers, name) do
    case Regex.run(~r/^#{name}[ \t]*:[ \t]*([^\r\n]*)/mi, headers) do
      [_match, value] -> String.trim(value)
      nil -> nil
    end
  end
end
