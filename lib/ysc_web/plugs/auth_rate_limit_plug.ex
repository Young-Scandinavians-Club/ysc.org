defmodule YscWeb.Plugs.AuthRateLimitPlug do
  @moduledoc """
  Plug that enforces IP-based rate limiting on authentication endpoints
  to slow down credential stuffing. Use on routes that handle login,
  OAuth callback, passkey login, and similar.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    YscWeb.Plugs.IpRateLimit.call(conn,
      limiter: Ysc.AuthRateLimit,
      format: :html
    )
  end
end
