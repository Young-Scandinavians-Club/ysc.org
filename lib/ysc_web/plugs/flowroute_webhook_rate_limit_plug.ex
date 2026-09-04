defmodule YscWeb.Plugs.FlowrouteWebhookRateLimitPlug do
  @moduledoc """
  IP-based rate limiting for the FlowRoute webhook routes (before token auth).
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    YscWeb.Plugs.IpRateLimit.call(conn,
      limiter: Ysc.FlowrouteWebhookRateLimit,
      format: :text
    )
  end
end
