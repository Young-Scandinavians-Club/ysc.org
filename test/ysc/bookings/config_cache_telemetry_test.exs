defmodule Ysc.Bookings.ConfigCacheTelemetryTest do
  use ExUnit.Case, async: false

  alias Ysc.Bookings.{
    AvailabilityCache,
    ConfigCacheTelemetry,
    PricingRuleCache,
    RoomsListCache,
    SeasonCache
  }

  setup do
    test_pid = self()
    handler_id = "config-cache-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:ysc, :bookings, :config_cache, :invalidated],
        [:ysc, :bookings, :config_cache, :live_rebuild]
      ],
      fn event_name, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event_name, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "cache invalidate emits config_cache.invalidated telemetry" do
    SeasonCache.invalidate()

    assert_receive {:telemetry_event,
                    [:ysc, :bookings, :config_cache, :invalidated], %{count: 1},
                    %{cache: :season}}

    PricingRuleCache.invalidate()

    assert_receive {:telemetry_event,
                    [:ysc, :bookings, :config_cache, :invalidated], %{count: 1},
                    %{cache: :pricing_rule}}

    RoomsListCache.invalidate()

    assert_receive {:telemetry_event,
                    [:ysc, :bookings, :config_cache, :invalidated], %{count: 1},
                    %{cache: :rooms}}

    AvailabilityCache.invalidate()

    assert_receive {:telemetry_event,
                    [:ysc, :bookings, :config_cache, :invalidated], %{count: 1},
                    %{cache: :availability}}
  end

  test "live_rebuild helper emits tagged telemetry" do
    ConfigCacheTelemetry.live_rebuild(:tahoe_booking, :rooms)

    assert_receive {:telemetry_event,
                    [:ysc, :bookings, :config_cache, :live_rebuild],
                    %{count: 1}, %{live_view: :tahoe_booking, cache: :rooms}}
  end
end
