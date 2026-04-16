defmodule YscWeb.Plugs.CacheRawBody do
  @moduledoc """
  Custom body reader for Plug.Parsers that caches the raw request body in
  `conn.private[:raw_body]` before it is consumed by the parser.

  This allows downstream controllers (e.g. QuickBooks webhook controller) to
  perform HMAC-SHA256 signature verification against the original raw body,
  which would otherwise be unavailable after parsing.

  Usage in endpoint.ex:

      plug Plug.Parsers,
        ...,
        body_reader: {YscWeb.Plugs.CacheRawBody, :read_body, []}
  """

  @doc """
  Reads the request body and stores it in `conn.private[:raw_body]`.
  Concatenates all chunks in the `:more` case.
  """
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = update_raw_body(conn, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = update_raw_body(conn, body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_raw_body(conn, chunk) do
    existing = conn.private[:raw_body] || ""
    Plug.Conn.put_private(conn, :raw_body, existing <> chunk)
  end
end
