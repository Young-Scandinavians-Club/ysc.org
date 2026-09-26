defmodule Ysc.RegistrationRateLimit do
  @moduledoc """
  Rate limiting for membership application submits.

  Each accepted application creates a user, sends a confirmation email,
  queues Stripe customer creation, and emails the board. The route-level
  `YscWeb.Plugs.AuthRateLimitPlug` only covers the initial page load, so
  `YscWeb.UserRegistrationLive` checks this limiter on every `save` event.

  Keyed by the client IP from `YscWeb.ClientIP.from_socket/2`. The limit is
  generous (real applicants retry after validation errors, and a household
  can share an IP) and can be overridden with
  `config :ysc, Ysc.RegistrationRateLimit, ip_limit: n`.
  """
  use Hammer, backend: :ets

  require Ysc.Logging

  alias Ysc.RateLimit

  # Per IP: 10 application submits per hour
  @default_ip_limit 10
  @ip_scale_ms :timer.hours(1)

  @doc """
  Current per-IP limit (application submits per hour).
  """
  def ip_limit do
    Application.get_env(:ysc, __MODULE__, [])[:ip_limit] || @default_ip_limit
  end

  @doc """
  Checks the rate limit for an application submit from `ip`.

  Returns `:ok` if allowed, or `{:error, :rate_limited, retry_after_seconds}`
  if over limit.
  """
  def check_ip(ip) when is_tuple(ip) or is_binary(ip) do
    limit = ip_limit()

    case RateLimit.check_ip(&hit/3, "registration:ip:", ip, @ip_scale_ms, limit) do
      :ok ->
        :ok

      {:error, :rate_limited, _} = error ->
        Ysc.Logging.warning("Membership application rate limit exceeded by IP",
          ip: RateLimit.normalize_ip(ip),
          limit: limit
        )

        error
    end
  end
end
