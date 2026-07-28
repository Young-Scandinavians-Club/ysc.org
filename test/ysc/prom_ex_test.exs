defmodule Ysc.PromExTest do
  use ExUnit.Case, async: true

  alias PromEx.Plugins
  alias Ysc.PromEx

  describe "plugins/0" do
    test "includes Phoenix, LiveView, Ecto, BEAM, and Oban plugins" do
      plugins = PromEx.plugins()

      assert {Plugins.Phoenix, _} =
               Enum.find(plugins, &match?({Plugins.Phoenix, _}, &1))

      assert Plugins.PhoenixLiveView in plugins
      assert Plugins.Ecto in plugins
      assert Plugins.Beam in plugins
      assert Plugins.Oban in plugins
    end
  end

  describe "dashboards/0" do
    test "includes built-in and domain dashboards" do
      assert :prom_ex in PromEx.dashboards()
      assert :phoenix in PromEx.dashboards()
      assert :ecto in PromEx.dashboards()
      assert :oban in PromEx.dashboards()
    end
  end

  describe "metrics/0" do
    test "defines custom application telemetry metrics" do
      metrics = PromEx.metrics()
      metric_names = Enum.map(metrics, & &1.name)

      assert [:ysc, :tickets, :order_created, :total] in metric_names
      assert [:ysc, :bookings, :booking_created, :total] in metric_names

      assert [:ysc, :bookings, :config_cache, :invalidated, :total] in metric_names

      assert [:ysc, :bookings, :config_cache, :live_rebuild, :total] in metric_names

      assert [:ysc, :payments, :stripe_webhook_received, :total] in metric_names
      assert [:ysc, :ledgers, :reconciliation_completed, :total] in metric_names
      assert [:ysc, :email, :sent, :total] in metric_names
      assert [:ysc, :email, :send_failed, :total] in metric_names
      assert [:ysc, :email, :hard_bounce, :total] in metric_names
      assert [:ysc, :email, :suppressed, :total] in metric_names
    end
  end
end
