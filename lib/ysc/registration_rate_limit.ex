defmodule Ysc.RegistrationRateLimit do
  @moduledoc """
  Rate limiting for membership applications.

  Each accepted application creates a user, sends a confirmation email,
  queues Stripe customer creation, and emails the board. The route-level
  `YscWeb.Plugs.AuthRateLimitPlug` only covers the initial page load, so
  `YscWeb.UserRegistrationLive` reserves a slot here on every `save` event.

  `reserve_application/1` takes a slot atomically before the application is
  saved, so simultaneous submits can't all slip under the limit, and
  `release_application/1` gives it back if the application isn't created.
  So only successful applications count: a person applies once, and submits
  that fail validation (e.g. a typo or an email already in use) don't use up
  the limit.

  Two counters per IP and hour, both only ever incremented: reservations and
  releases. A reservation is allowed while `reserved - released` stays within
  the limit; each reservation gets a unique count from the atomic increment,
  so the check holds under concurrency. Windows are fixed clock hours; a
  reservation remembers its window, and releasing it after the window ended
  does nothing (the slot expired with it) rather than freeing a slot in the
  next hour.

  Keyed by the client IP from `YscWeb.ClientIP.from_socket/2`. Counts are kept
  in ETS per app instance, like the other limiters. Override the limit with
  `config :ysc, Ysc.RegistrationRateLimit, ip_limit: n`.
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
  Reserves one application slot for `ip`. Call before saving the application,
  and `release_application/1` with the returned reservation if it isn't
  created.

  Returns `{:ok, reservation}`, or `{:error, :rate_limited, retry_after_seconds}`
  if the IP already has `ip_limit/0` applications this hour.
  """
  def reserve_application(ip) when is_tuple(ip) or is_binary(ip) do
    limit = ip_limit()
    # Taken before the increment: if the hour rolls over in between, a later
    # release finds a different window and skips, which errs on the safe side.
    reservation = {RateLimit.normalize_ip(ip), current_window()}
    reserved = inc(reserved_key(ip), @ip_scale_ms)

    if reserved - get(released_key(ip), @ip_scale_ms) <= limit do
      {:ok, reservation}
    else
      # Denied attempts don't hold a slot.
      release_application(reservation)

      Ysc.Logging.warning("Membership application rate limit exceeded by IP",
        ip: RateLimit.normalize_ip(ip),
        limit: limit
      )

      {:error, :rate_limited, retry_after_seconds(ip)}
    end
  end

  @doc """
  Gives back a slot taken by `reserve_application/1` when the application
  wasn't created (e.g. it failed validation). A no-op once the reservation's
  hour has ended.
  """
  def release_application({ip, window}) when is_binary(ip) do
    if window == current_window() do
      inc(released_key(ip), @ip_scale_ms)
    end

    :ok
  end

  # Same window numbering as Hammer's :fix_window algorithm.
  defp current_window, do: div(System.system_time(:millisecond), @ip_scale_ms)

  defp reserved_key(ip),
    do: "registration:reserved:" <> RateLimit.normalize_ip(ip)

  defp released_key(ip),
    do: "registration:released:" <> RateLimit.normalize_ip(ip)

  defp retry_after_seconds(ip) do
    remaining_ms =
      expires_at(reserved_key(ip), @ip_scale_ms) -
        System.system_time(:millisecond)

    max(1, div(remaining_ms + 999, 1000))
  end
end
