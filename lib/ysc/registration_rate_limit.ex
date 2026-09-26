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

  Two counters per IP and clock hour, both only ever incremented:
  reservations and releases. A reservation is allowed while
  `reserved - released` stays within the limit; each reservation gets a
  unique count from the atomic increment, so the check holds under
  concurrency. The hour is part of each counter's key and a reservation
  carries it, so a release always updates its own hour's counter. One that
  arrives after the hour ended touches a counter nothing reads anymore; it
  can't free a slot in the next hour.

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
    reserve(RateLimit.normalize_ip(ip), ip_limit())
  end

  defp reserve(ip, limit) do
    window = current_window()
    reserved = inc(reserved_key(ip, window), @ip_scale_ms)

    cond do
      # The hour rolled over around the increment, which then landed in a
      # counter nothing reads; take the slot in the new hour instead.
      current_window() != window ->
        reserve(ip, limit)

      reserved - get(released_key(ip, window), @ip_scale_ms) <= limit ->
        {:ok, {ip, window}}

      true ->
        # Denied attempts don't hold a slot.
        release_application({ip, window})

        Ysc.Logging.warning("Membership application rate limit exceeded by IP",
          ip: ip,
          limit: limit
        )

        {:error, :rate_limited, retry_after_seconds(window)}
    end
  end

  @doc """
  Gives back a slot taken by `reserve_application/1` when the application
  wasn't created (e.g. it failed validation). Has no effect once the
  reservation's hour has ended.
  """
  def release_application({ip, window})
      when is_binary(ip) and is_integer(window) do
    inc(released_key(ip, window), @ip_scale_ms)
    :ok
  end

  # Same window numbering as Hammer's :fix_window algorithm.
  defp current_window, do: div(System.system_time(:millisecond), @ip_scale_ms)

  defp reserved_key(ip, window), do: "registration:reserved:#{ip}:#{window}"
  defp released_key(ip, window), do: "registration:released:#{ip}:#{window}"

  defp retry_after_seconds(window) do
    remaining_ms =
      (window + 1) * @ip_scale_ms - System.system_time(:millisecond)

    max(1, div(remaining_ms + 999, 1000))
  end
end
