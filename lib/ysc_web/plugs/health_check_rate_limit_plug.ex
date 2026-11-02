defmodule YscWeb.Plugs.HealthCheckRateLimitPlug do
  @moduledoc """
  IP-based rate limiting for the database health check route.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    YscWeb.Plugs.IpRateLimit.call(conn,
      limiter: Ysc.HealthCheckRateLimit,
      format: :text
    )
  end
end
