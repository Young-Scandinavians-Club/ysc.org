defmodule YscWeb.Plugs.PrintfulWebhookRateLimitPlug do
  @moduledoc """
  IP-based rate limiting for the Printful webhook route (before token auth).
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    YscWeb.Plugs.IpRateLimit.call(conn,
      limiter: Ysc.PrintfulWebhookRateLimit,
      format: :text
    )
  end
end
