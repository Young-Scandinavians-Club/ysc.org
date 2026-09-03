defmodule Ysc.TelemetryMetricsUpgradeTest do
  @moduledoc """
  Guards the telemetry_metrics 1.1.0 → 1.2.0 upgrade.

  1.2.0 is a minor: `:tags` may be a 1-arity function (docs say this
  supersedes `:tag_values`) plus internal optimizations. `:tag_values` is
  documented as deprecated but does **not** emit a warning. We keep
  `tag_values` because PromEx/Peep, LiveDashboard, and
  telemetry_metrics_prometheus_core still treat `metric.tags` as a list of
  keys and call `metric.tag_values/1`.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import Telemetry.Metrics

  alias Ysc.PromEx

  describe "1.2.0 Hex lock and public APIs" do
    test "locks the Hex package to 1.2.0" do
      assert to_string(Application.spec(:telemetry_metrics, :vsn)) == "1.2.0"
    end

    test "counter, summary, last_value, distribution, and sum still exist" do
      assert function_exported?(Telemetry.Metrics, :counter, 1)
      assert function_exported?(Telemetry.Metrics, :counter, 2)
      assert function_exported?(Telemetry.Metrics, :summary, 2)
      assert function_exported?(Telemetry.Metrics, :last_value, 2)
      assert function_exported?(Telemetry.Metrics, :distribution, 2)
      assert function_exported?(Telemetry.Metrics, :sum, 2)

      assert {:module, Telemetry.Metrics.ConsoleReporter} =
               Code.ensure_loaded(Telemetry.Metrics.ConsoleReporter)
    end
  end

  describe "1.2.0 tag_values remains supported" do
    test "does not emit a deprecation warning when tag_values is set" do
      stderr =
        capture_io(:stderr, fn ->
          _metric =
            counter("ysc.upgrade.probe.total",
              event_name: [:ysc, :upgrade, :probe],
              tags: [:status],
              tag_values: fn metadata ->
                %{status: to_string(metadata.status)}
              end
            )
        end)

      refute stderr =~ "deprecated"
      refute stderr =~ "tag_values"
    end

    test "stores tags as a key list and tag_values as a 1-arity function" do
      metric =
        counter("ysc.upgrade.probe.total",
          event_name: [:ysc, :upgrade, :probe],
          tags: [:status],
          tag_values: fn metadata -> %{status: to_string(metadata.status)} end
        )

      assert metric.tags == [:status]
      assert is_function(metric.tag_values, 1)
      assert metric.tag_values.(%{status: :ok}) == %{status: "ok"}
    end

    test "also accepts a 1-arity tags function without dropping tag_values" do
      metric =
        counter("ysc.upgrade.tags_fun.total",
          event_name: [:ysc, :upgrade, :tags_fun],
          tags: fn metadata -> %{status: to_string(metadata.status)} end
        )

      assert is_function(metric.tags, 1)
      assert is_function(metric.tag_values, 1)
      assert metric.tags.(%{status: :ok}) == %{status: "ok"}
    end
  end

  describe "1.2.0 ConsoleReporter still extracts tag_values" do
    test "prints transformed tags for a counter event" do
      metric =
        counter("ysc.upgrade.console.total",
          event_name: [:ysc, :upgrade, :console],
          tags: [:status],
          tag_values: fn metadata -> %{status: to_string(metadata.status)} end
        )

      {:ok, io} = StringIO.open("")

      start_supervised!(
        {Telemetry.Metrics.ConsoleReporter, metrics: [metric], device: io}
      )

      :telemetry.execute([:ysc, :upgrade, :console], %{total: 1}, %{status: :ok})

      output = StringIO.flush(io)
      assert output =~ "ysc.upgrade.console"
      assert output =~ ~s(%{status: "ok"})
    end
  end

  describe "1.2.0 application metrics keep list tags plus tag_values" do
    test "PromEx custom metrics still use tag_values with a tags key list" do
      metric =
        Enum.find(
          PromEx.metrics(),
          &(&1.name == [:ysc, :tickets, :order_created, :total])
        )

      assert %Telemetry.Metrics.Counter{} = metric
      assert metric.tags == [:event_id, :user_id]
      assert is_function(metric.tag_values, 1)

      assert metric.tag_values.(%{
               ticket_order_id: 1,
               event_id: 42,
               user_id: 7
             }) == %{event_id: "42", user_id: "7"}

      assert metric.tag_values.(%{unexpected: true}) == %{
               event_id: "unknown",
               user_id: "unknown"
             }
    end

    test "every tagged PromEx metric keeps tags as a list for Peep and PromEx" do
      tagged =
        Enum.filter(PromEx.metrics(), fn metric -> metric.tags != [] end)

      assert tagged != []

      Enum.each(tagged, fn metric ->
        assert is_list(metric.tags),
               "#{inspect(metric.name)} expected list tags, got #{inspect(metric.tags)}"

        assert is_function(metric.tag_values, 1)
      end)
    end

    test "LiveDashboard metrics keep tags as a list" do
      Enum.each(YscWeb.Telemetry.metrics(), fn metric ->
        assert is_list(metric.tags),
               "#{inspect(metric.name)} expected list tags for LiveDashboard, got #{inspect(metric.tags)}"

        assert is_function(metric.tag_values, 1)
      end)
    end
  end
end
