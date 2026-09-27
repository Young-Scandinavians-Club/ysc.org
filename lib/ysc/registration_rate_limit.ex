defmodule Ysc.RegistrationRateLimit do
  @moduledoc """
  Rate limiting for membership applications.

  Each accepted application creates a user, sends a confirmation email,
  queues Stripe customer creation, and emails the board. The route-level
  `YscWeb.Plugs.AuthRateLimitPlug` only covers the initial page load, so
  `YscWeb.UserRegistrationLive` reserves a slot here on every `save` event.

  `reserve_application/1` takes a slot before the application is saved, and
  `release_application/1` gives it back if the application isn't created.
  So only successful applications count: a person applies once, and submits
  that fail validation (e.g. a typo or an email already in use) don't use up
  the limit.

  One counter per IP and clock hour holds the number of slots taken. A
  reservation reads and increments it in a single atomic ETS update that
  never takes it above the limit, and succeeds only if the increment went
  through. So simultaneous submits can't slip past the limit, and a denied
  attempt never touches the counter, so it has nothing to give back. A
  release decrements it, never below zero. The hour is part of the
  counter's key and a reservation carries it, so a release always updates
  its own hour's counter. One that arrives after the hour ended touches a
  counter nothing reads anymore; it can't free a slot in the next hour.

  Keyed by the client IP from `YscWeb.ClientIP.from_socket/2`. Counts are kept
  in ETS per app instance, like the other limiters, in this module's Hammer
  table so its cleanup removes expired hours. Override the limit with
  `config :ysc, Ysc.RegistrationRateLimit, ip_limit: n`.
  """
  use Hammer, backend: :ets

  require Ysc.Logging

  alias Ysc.RateLimit

  # Per IP: 3 successful applications per hour
  @default_ip_limit 3
  @ip_scale_ms :timer.hours(1)

  # Position of the count in Hammer's `{{key, window}, count, expires_at}` rows.
  @count_pos 2

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

    # Reads the count, then adds one unless that would exceed the limit, in
    # one atomic update. The count went up only if a slot was free.
    [before, after_inc] =
      update_count(ip, window, [{@count_pos, 0}, {@count_pos, 1, limit, limit}])

    cond do
      # The hour rolled over around the update, which then landed in a
      # counter nothing reads; take the slot in the new hour instead.
      current_window() != window ->
        reserve(ip, limit)

      after_inc > before ->
        {:ok, {ip, window}}

      true ->
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
    update_count(ip, window, {@count_pos, -1, 0, 0})
    :ok
  end

  defp update_count(ip, window, ops) do
    Hammer.ETS.update_counter(
      __MODULE__,
      {"registration:#{ip}", window},
      ops,
      window_end_ms(window)
    )
  end

  # Same window numbering as Hammer's :fix_window algorithm.
  defp current_window, do: div(System.system_time(:millisecond), @ip_scale_ms)

  defp window_end_ms(window), do: (window + 1) * @ip_scale_ms

  defp retry_after_seconds(window) do
    remaining_ms = window_end_ms(window) - System.system_time(:millisecond)

    max(1, div(remaining_ms + 999, 1000))
  end
end
