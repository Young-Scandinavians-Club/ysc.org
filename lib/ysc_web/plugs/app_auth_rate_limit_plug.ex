defmodule YscWeb.Plugs.AppAuthRateLimitPlug do
  @moduledoc """
  IP-based rate limiting for the admin/volunteer mobile app's auth
  endpoints (`/api/v1/app/auth/*`). Reuses the same limiter as the web
  login/OAuth/passkey flows (`Ysc.AuthRateLimit`), but responds with JSON
  since these are API clients, not browsers.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    YscWeb.Plugs.IpRateLimit.call(conn,
      limiter: Ysc.AuthRateLimit,
      format: :json
    )
  end
end
