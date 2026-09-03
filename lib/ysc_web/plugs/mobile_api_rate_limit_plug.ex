defmodule YscWeb.Plugs.MobileAPIRateLimitPlug do
  @moduledoc """
  IP-based rate limiting for the kiosk mobile JSON API (before bearer auth).
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    YscWeb.Plugs.IpRateLimit.call(conn,
      limiter: Ysc.MobileAPIRateLimit,
      format: :json
    )
  end
end
