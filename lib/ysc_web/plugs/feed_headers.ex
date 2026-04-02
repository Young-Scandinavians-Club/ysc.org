defmodule YscWeb.Plugs.FeedHeaders do
  @moduledoc """
  Minimal response headers for Atom/XML feed endpoints.

  Avoids the full `SecurityHeaders` plug (heavy CSP, S3 lookups, COOP/CORP, etc.).

  The router still runs `put_secure_browser_headers` after this plug so default
  secure headers (minimal CSP, `x-permitted-cross-domain-policies`) satisfy policy
  scanners; duplicate keys such as `referrer-policy` and `x-content-type-options`
  are not re-added by Phoenix.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_hsts_header()
  end

  defp put_hsts_header(conn) do
    if Ysc.Env.dev?() do
      conn
    else
      is_https =
        case get_req_header(conn, "x-forwarded-proto") do
          ["https"] -> true
          _ -> conn.scheme == :https
        end

      if is_https do
        put_resp_header(
          conn,
          "strict-transport-security",
          "max-age=31536000; includeSubDomains; preload"
        )
      else
        conn
      end
    end
  end
end
