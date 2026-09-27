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
  reservation adds one to it with an atomic ETS increment and gets a slot
  only if its own result is within the limit; otherwise it takes the one
  back. Each result is unique, so simultaneous submits on a node can't slip
  past the limit, and a denied attempt never holds a slot. A release takes
  one off, never going below zero. The hour is part of the counter's key and
  a reservation carries it, so a release always updates its own hour's
  counter. One that arrives after the hour ended touches a counter nothing
  reads anymore; it can't free a slot in the next hour.

  The limit is cluster-wide. Each kept slot and each release goes out
  through `Ysc.DistributedCache` as a +1 or -1 that every other node adds
  to its own counter, so each node's counter converges on the total across
  the cluster. Within a node the limit is strict; two submits that land on
  different nodes within the few milliseconds a broadcast takes can both
  get in. A node that joins mid-hour starts that hour from zero.

  Keyed by the client IP from `YscWeb.ClientIP.from_socket/2`. Each node
  keeps its copy of the counts in this module's Hammer ETS table, so
  Hammer's cleanup removes expired hours. Override the limit with
  `config :ysc, Ysc.RegistrationRateLimit, ip_limit: n`.
  """
  use Hammer, backend: :ets

  require Ysc.Logging

  alias Ysc.DistributedCache
  alias Ysc.RateLimit

  # Per IP: 3 successful applications per hour
  @default_ip_limit 3
  @ip_scale_ms :timer.hours(1)

  # Position of the count in Hammer's `{{key, window}, count, expires_at}` rows.
  @count_pos 2
  @take_slot {@count_pos, 1}
  # Never below zero, e.g. for a counter whose hour was already cleaned up.
  @give_back_slot {@count_pos, -1, 0, 0}

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
    key = counter_key(ip, window)
    count = :ets.update_counter(__MODULE__, key, @take_slot, new_counter(key))

    cond do
      # The hour rolled over around the increment, which then landed in a
      # counter nothing reads; take the slot in the new hour instead.
      current_window() != window ->
        reserve(ip, limit)

      count <= limit ->
        # Keep the slot and count it on the other nodes too.
        DistributedCache.broadcast_counter_update(
          __MODULE__,
          key,
          @take_slot,
          new_counter(key)
        )

        {:ok, {ip, window}}

      true ->
        # Denied attempts don't hold a slot. Only this call's own increment
        # decided that, so taking it back can't let anyone else in.
        :ets.update_counter(__MODULE__, key, {@count_pos, -1}, new_counter(key))

        Ysc.Logging.warning("Membership application rate limit exceeded by IP",
          ip: ip,
          limit: limit
        )

        {:error, :rate_limited, retry_after_seconds(window)}
    end
  end

  @doc """
  Gives back a slot taken by `reserve_application/1` when the application
  wasn't created (e.g. it failed validation), on every node. Has no effect
  once the reservation's hour has ended.
  """
  def release_application({ip, window})
      when is_binary(ip) and is_integer(window) do
    key = counter_key(ip, window)

    DistributedCache.update_counter(
      __MODULE__,
      key,
      @give_back_slot,
      new_counter(key)
    )

    :ok
  end

  defp counter_key(ip, window), do: {"registration:#{ip}", window}

  # An empty counter in Hammer's `{{key, window}, count, expires_at}` row
  # format, so Hammer's cleanup removes it once its hour has ended.
  defp new_counter({_ip_key, window} = key), do: {key, 0, window_end_ms(window)}

  # Same window numbering as Hammer's :fix_window algorithm.
  defp current_window, do: div(System.system_time(:millisecond), @ip_scale_ms)

  defp window_end_ms(window), do: (window + 1) * @ip_scale_ms

  defp retry_after_seconds(window) do
    remaining_ms = window_end_ms(window) - System.system_time(:millisecond)

    max(1, div(remaining_ms + 999, 1000))
  end
end
