defmodule Ysc.PromExTest do
  use ExUnit.Case, async: true

  alias PromEx.Plugins
  alias Ysc.PromEx

  describe "plugins/0" do
    test "includes Phoenix, LiveView, Ecto, BEAM, Oban, and YSC plugins" do
      plugins = PromEx.plugins()

      assert {Plugins.Phoenix, _} =
               Enum.find(plugins, &match?({Plugins.Phoenix, _}, &1))

      assert Plugins.PhoenixLiveView in plugins
      assert Plugins.Ecto in plugins
      assert Plugins.Beam in plugins
      assert Ysc.PromEx.Plugins.Oban in plugins
      assert Ysc.PromEx.Plugins.Ysc in plugins
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
      assert [:ysc, :email, :ses_webhook, :events, :total] in metric_names

      assert [
               :ysc,
               :email,
               :ses_webhook,
               :processing,
               :duration,
               :milliseconds
             ] in metric_names
    end

    test "exposes duration metrics as Prometheus distributions" do
      duration_metrics =
        PromEx.metrics()
        |> Enum.filter(&match?(%Telemetry.Metrics.Distribution{}, &1))

      assert Enum.any?(duration_metrics, fn metric ->
               metric.name == [
                 :ysc,
                 :email,
                 :ses_webhook,
                 :processing,
                 :duration,
                 :milliseconds
               ]
             end)
    end
  end

  describe "Ysc.PromEx.Plugins.Ysc" do
    test "publishes application metrics through PromEx event groups" do
      event_group = Ysc.PromEx.Plugins.Ysc.event_metrics([])

      assert event_group.group_name == :ysc_application_event_metrics

      metric_names = Enum.map(event_group.metrics, & &1.name)
      assert [:ysc, :email, :sent, :total] in metric_names
      assert [:ysc, :email, :ses_webhook, :events, :total] in metric_names
    end
  end

  describe "Ysc.PromEx.Plugins.Oban" do
    test "polling metrics use the resilient queue metrics MFA" do
      polling = Ysc.PromEx.Plugins.Oban.polling_metrics(otp_app: :ysc)

      assert polling.group_name == :oban_queue_poll_metrics

      assert {Ysc.PromEx.Plugins.Oban, :execute_queue_metrics, [_supervisors]} =
               polling.measurements_mfa
    end

    test "execute_queue_metrics swallows transient DB connection errors" do
      runner = fn _supervisors ->
        raise DBConnection.ConnectionError, message: "tcp recv (idle): closed"
      end

      assert :ok =
               Ysc.PromEx.Plugins.Oban.execute_queue_metrics(
                 MapSet.new([Oban]),
                 runner
               )
    end

    test "execute_queue_metrics re-raises unexpected errors" do
      runner = fn _supervisors -> raise "boom" end

      assert_raise RuntimeError, "boom", fn ->
        Ysc.PromEx.Plugins.Oban.execute_queue_metrics(
          MapSet.new([Oban]),
          runner
        )
      end
    end
  end
end
