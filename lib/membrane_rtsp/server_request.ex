defmodule Membrane.RTSP.ServerRequest do
  @moduledoc false
  # Requests that the server sends on the client's connection. OPTIONS, GET_PARAMETER
  # and SET_PARAMETER are confirmed with 200, any other request is answered with 501.

  require Logger

  alias Membrane.RTSP.Response

  @methods ~w(OPTIONS GET_PARAMETER SET_PARAMETER ANNOUNCE REDIRECT PLAY_NOTIFY
              DESCRIBE SETUP PLAY PAUSE RECORD TEARDOWN)
  @confirmed_methods ~w(OPTIONS GET_PARAMETER SET_PARAMETER)
  @echoed_headers ["CSeq", "Session"]
  @line_ending ["\r\n", "\r", "\n"]

  @spec request?(binary()) :: boolean()
  def request?(data) do
    case String.split(data, [" ", "\t"], parts: 2) do
      [method, _rest] -> method in @methods
      [_data] -> false
    end
  end

  @spec reply(binary()) :: binary()
  def reply(request) do
    [method | _rest] = String.split(request, [" ", "\t"], parts: 2)

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

    status
    |> Response.new()
    |> Map.put(:headers, echoed_headers(request))
    |> Response.stringify()
  end

  defp echoed_headers(request) do
    headers = parse_headers(request)

    @echoed_headers
    |> Enum.map(fn name -> {name, headers[String.downcase(name)]} end)
    |> Enum.filter(fn {_name, value} -> value != nil end)
  end

  defp parse_headers(request) do
    [start_line_and_headers | _body] =
      String.split(request, ["\r\n\r\n", "\n\n", "\r\r"], parts: 2)

    start_line_and_headers
    |> String.split(@line_ending)
    |> Enum.map(fn line -> String.split(line, ":", parts: 2) end)
    |> Enum.filter(fn parts -> length(parts) == 2 end)
    |> Map.new(fn [name, value] ->
      {name |> String.trim() |> String.downcase(), String.trim(value)}
    end)
  end
end
