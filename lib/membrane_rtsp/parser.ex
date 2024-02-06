defmodule Membrane.RTSP.Parser do
  @moduledoc false

  alias __MODULE__.{Request, Transport}
  alias Membrane.RTSP

  @type transport_header :: [
          transport: :TCP | :UDP,
          mode: :unicast | :multicast,
          parameters: map()
        ]

  @spec parse_request(binary()) :: {:ok, RTSP.Request.t()} | {:error, term()}
  def parse_request(request) do
    case Request.parse_request(request) do
      {:ok, args, _rest, _context, _line, _byte_offset} ->
        {method, uri, headers, body} =
          case args do
            [method, uri] -> {method, uri, [], nil}
            [method, uri, headers] -> {method, uri, headers, nil}
            [method, uri, headers, body] -> {method, uri, headers, body}
          end

        {:ok,
         %RTSP.Request{
           method: method,
           path: uri,
           headers: headers,
           body: body
         }}

      {:error, reason, _rest, _context, _line, _byte_offset} ->
        {:error, reason}
    end
  end

  @spec parse_transport_header(binary()) ::
          {:ok, transport_header()} | {:error, :invalid_header}
  def parse_transport_header(header) do
    case Transport.parse_transport_header(header) do
      {:ok, args, _rest, _context, _line, _byte_offset} ->
        {transport, mode, parameters} =
          case args do
            [transport, mode | parameters] when transport in ["UDP", "TCP"] ->
              {transport, mode, parameters}

            [mode | parameters] when mode in ["unicast", "multicast"] ->
              {"UDP", mode, parameters}
          end

        {:ok,
         [
           transport: String.to_atom(transport),
           mode: String.to_atom(mode),
           parameters: Map.new(parameters)
         ]}

      {:error, _reason, _rest, _context, _line, _byte_offset} ->
        {:error, :invalid_header}
    end
  end
end
