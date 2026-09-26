defmodule Ysc.RegistrationRateLimit do
  @moduledoc """
  Rate limiting for membership applications.

  Each accepted application creates a user, sends a confirmation email,
  queues Stripe customer creation, and emails the board. The route-level
  `YscWeb.Plugs.AuthRateLimitPlug` only covers the initial page load, so
  `YscWeb.UserRegistrationLive` checks this limiter on every `save` event.

  Only successful applications count: `check_ip/1` reads the count and
  `record_application/1` adds to it after the account is created. A person
  applies once, so the limit is low, but submits that fail validation (e.g.
  a typo or an email already in use) don't use it up.

  Keyed by the client IP from `YscWeb.ClientIP.from_socket/2`. Override the
  limit with `config :ysc, Ysc.RegistrationRateLimit, ip_limit: n`.
  """
  use Hammer, backend: :ets

  require Ysc.Logging

  alias Ysc.RateLimit

  # Per IP: 3 successful applications per hour
  @default_ip_limit 3
  @ip_scale_ms :timer.hours(1)

  @doc """
  Current per-IP limit (successful applications per hour).
  """
  def ip_limit do
    Application.get_env(:ysc, __MODULE__, [])[:ip_limit] || @default_ip_limit
  end

  @doc """
  Checks whether `ip` may submit another application. Doesn't count the
  attempt; call `record_application/1` once the application is saved.

  Returns `:ok` if allowed, or `{:error, :rate_limited, retry_after_seconds}`
  if the IP already has `ip_limit/0` applications this hour.
  """
  def check_ip(ip) when is_tuple(ip) or is_binary(ip) do
    key = key(ip)
    limit = ip_limit()

    if get(key, @ip_scale_ms) < limit do
      :ok
    else
      Ysc.Logging.warning("Membership application rate limit exceeded by IP",
        ip: RateLimit.normalize_ip(ip),
        limit: limit
      )

      {:error, :rate_limited, retry_after_seconds(key)}
    end
  end

  @doc """
  Counts a successful application from `ip` against its limit.
  """
  def record_application(ip) when is_tuple(ip) or is_binary(ip) do
    inc(key(ip), @ip_scale_ms)
    :ok
  end

  defp key(ip), do: "registration:ip:" <> RateLimit.normalize_ip(ip)

  defp retry_after_seconds(key) do
    remaining_ms =
      expires_at(key, @ip_scale_ms) - System.system_time(:millisecond)

    max(1, div(remaining_ms + 999, 1000))
  end
end
