defmodule YscWeb.Plugs.AppAuthRateLimitPlug do
  @moduledoc """
  IP-based rate limiting for the admin/volunteer mobile app's auth
  endpoints (`/api/v1/app/auth/*`). Reuses the same limiter as the web
  login/OAuth/passkey flows (`Ysc.AuthRateLimit`), but responds with JSON
  since these are API clients, not browsers.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Ysc.AuthRateLimit.check_ip(conn.remote_ip) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after_sec} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_sec))
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "Too many requests"}))
        |> halt()
    end
  end
end
