defmodule Ysc.Bookings.ConfigCacheTelemetry do
  @moduledoc """
  Telemetry helpers for booking config caches (seasons, rooms, pricing, etc.).

  Used to observe admin-driven cache busts and LiveView rebuilds that keep
  open booking sessions in sync.
  """

  @doc """
  Emits when a booking config cache is invalidated.

  `cache` should be one of:
  `:season | :rooms | :pricing_rule | :refund_policy | :blackout | :availability`
  """
  def invalidated(cache) when is_atom(cache) do
    :telemetry.execute(
      [:ysc, :bookings, :config_cache, :invalidated],
      %{count: 1},
      %{cache: cache}
    )
  end

  @doc """
  Emits when a LiveView rebuilds assigns after a config-cache invalidation.

  `live_view` should be one of:
  `:tahoe_booking | :clear_lake_booking | :booking_change`
  """
  def live_rebuild(live_view, cache)
      when is_atom(live_view) and is_atom(cache) do
    :telemetry.execute(
      [:ysc, :bookings, :config_cache, :live_rebuild],
      %{count: 1},
      %{live_view: live_view, cache: cache}
    )
  end
end
