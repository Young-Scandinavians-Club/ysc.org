defmodule Ysc.HealthCheckRateLimit do
  @moduledoc """
  Per-IP rate limiting for `/up/dbs`.

  The route is public and every hit runs a query on the shared Repo pool, so
  without a limit it is a cheap way to starve real traffic of connections.
  Generous for an uptime monitor; tune with
  `config :ysc, Ysc.HealthCheckRateLimit, ip_limit: n`.
  """
  use Hammer, backend: :ets

  alias Ysc.RateLimit

  @default_ip_limit 30
  @ip_scale_ms :timer.minutes(1)

  defp ip_limit do
    Application.get_env(:ysc, __MODULE__, [])[:ip_limit] || @default_ip_limit
  end

  @doc "Returns `:ok` or `{:error, :rate_limited, retry_after_seconds}`."
  def check_ip(ip) when is_tuple(ip) or is_binary(ip) do
    RateLimit.check_ip(
      &hit/3,
      "health_check:ip:",
      ip,
      @ip_scale_ms,
      ip_limit()
    )
  end
end
