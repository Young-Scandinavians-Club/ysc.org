defmodule YscWeb.Plugs.AuthRateLimitPlug do
  @moduledoc """
  Plug that enforces IP-based rate limiting on authentication endpoints
  to slow down credential stuffing. Use on routes that handle login,
  OAuth callback, passkey login, and similar.
  """
  import Plug.Conn

  def init(opts), do: opts

  # sobelow_skip ["XSS.SendResp"]
  def call(conn, _opts) do
    ip = conn.remote_ip

    case Ysc.AuthRateLimit.check_ip(ip) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after_sec} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_sec))
        |> put_resp_content_type("text/html")
        |> send_resp(429, rate_limited_body(retry_after_sec))
        |> halt()
    end
  end

  defp rate_limited_body(retry_after_sec) do
    """
    <!DOCTYPE html>
    <html>
    <head><title>Too Many Requests</title></head>
    <body>
    <h1>Too many attempts</h1>
    <p>Please try again in #{retry_after_sec} seconds.</p>
    </body>
    </html>
    """
  end
end
