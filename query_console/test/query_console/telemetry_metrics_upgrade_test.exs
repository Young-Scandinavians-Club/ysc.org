defmodule QueryConsole.TelemetryMetricsUpgradeTest do
  @moduledoc """
  Guards the telemetry_metrics 1.1.0 → 1.2.0 upgrade.

  1.2.0 is a minor: `:tags` may be a 1-arity function (docs say this
  supersedes `:tag_values`) plus internal optimizations. `:tag_values` is
  documented as deprecated but does **not** emit a warning. We keep
  list tags (`[:route]`, `[:event]`) because `QueryConsoleWeb.Telemetry`
  is Phoenix-generated LiveDashboard-style metrics. We do not pass
  `tag_values` or a tags function. `ConsoleReporter` is commented out.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import Telemetry.Metrics

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/telemetry_metrics/CHANGELOG.md", __DIR__)
  @telemetry_src Path.expand(
                   "../../lib/query_console_web/telemetry.ex",
                   __DIR__
                 )

  setup_all do
    {:ok, _} = Application.ensure_all_started(:telemetry_metrics)
    {:module, Telemetry.Metrics} = Code.ensure_loaded(Telemetry.Metrics)

    {:module, Telemetry.Metrics.ConsoleReporter} =
      Code.ensure_loaded(Telemetry.Metrics.ConsoleReporter)

    :ok
  end

  describe "1.2.0 Hex lock and public APIs" do
    test "locks the Hex package to 1.2.0" do
      assert to_string(Application.spec(:telemetry_metrics, :vsn)) == "1.2.0"
    end

    test "mix.exs pins the 1.2 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:telemetry_metrics, "~> 1.2"})
    end

    test "companion lock is 1.2.0 and dns_cluster stays put" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"telemetry_metrics": {:hex, :telemetry_metrics, "1.2.0"|
      refute lock =~ ~s|"telemetry_metrics": {:hex, :telemetry_metrics, "1.1.0"|
      assert lock =~ ~s|"finch": {:hex, :finch, "0.24.0"|
      assert lock =~ ~s|"dns_cluster": {:hex, :dns_cluster, "0.3.1"|
    end

    test "counter, summary, last_value, distribution, and sum still exist" do
      assert {:module, _} = Code.ensure_loaded(Telemetry.Metrics)
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

  describe "1.2.0 changelog" do
    test "documents tags functions without breaking changes" do
      changelog = File.read!(@changelog)

      v120 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[1.2.0]"))

      assert v120
      assert v120 =~ "Add support for functions in `tags`"
      assert v120 =~ "this supersedes `tag_values`"
      assert v120 =~ "Assorted optimizations"
      refute v120 =~ "Breaking"
    end
  end

  describe "1.2.0 tag_values remains supported" do
    test "does not emit a deprecation warning when tag_values is set" do
      stderr =
        capture_io(:stderr, fn ->
          _metric =
            counter("query_console.upgrade.probe.total",
              event_name: [:query_console, :upgrade, :probe],
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
        counter("query_console.upgrade.probe.total",
          event_name: [:query_console, :upgrade, :probe],
          tags: [:status],
          tag_values: fn metadata -> %{status: to_string(metadata.status)} end
        )

      assert metric.tags == [:status]
      assert is_function(metric.tag_values, 1)
      assert metric.tag_values.(%{status: :ok}) == %{status: "ok"}
    end

    test "also accepts a 1-arity tags function without dropping tag_values" do
      metric =
        counter("query_console.upgrade.tags_fun.total",
          event_name: [:query_console, :upgrade, :tags_fun],
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
        counter("query_console.upgrade.console.total",
          event_name: [:query_console, :upgrade, :console],
          tags: [:status],
          tag_values: fn metadata -> %{status: to_string(metadata.status)} end
        )

      {:ok, io} = StringIO.open("")

      start_supervised!({Telemetry.Metrics.ConsoleReporter, metrics: [metric], device: io})

      :telemetry.execute([:query_console, :upgrade, :console], %{total: 1}, %{
        status: :ok
      })

      output = StringIO.flush(io)
      assert output =~ "query_console.upgrade.console"
      assert output =~ ~s(%{status: "ok"})
    end
  end

  describe "app metrics keep list tags" do
    test "telemetry.ex still uses list tags, not tag_values or a tags function" do
      source = File.read!(@telemetry_src)
      assert source =~ "tags: [:route]"
      assert source =~ "tags: [:event]"
      refute source =~ "tag_values:"
      refute source =~ "tags: fn"
    end

    test "every QueryConsoleWeb.Telemetry metric keeps tags as a list" do
      Enum.each(QueryConsoleWeb.Telemetry.metrics(), fn metric ->
        assert is_list(metric.tags),
               "#{inspect(metric.name)} expected list tags, got #{inspect(metric.tags)}"

        assert is_function(metric.tag_values, 1)
      end)
    end

    test "router and channel metrics still tag by :route and :event" do
      metrics = QueryConsoleWeb.Telemetry.metrics()

      route =
        Enum.find(
          metrics,
          &(&1.name == [:phoenix, :router_dispatch, :stop, :duration])
        )

      event =
        Enum.find(
          metrics,
          &(&1.name == [:phoenix, :channel_handled_in, :duration])
        )

      assert %Telemetry.Metrics.Summary{} = route
      assert route.tags == [:route]

      assert %Telemetry.Metrics.Summary{} = event
      assert event.tags == [:event]
    end
  end
end
