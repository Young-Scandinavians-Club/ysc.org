defmodule Ysc.PromEx.Plugins.Postgres do
  @moduledoc """
  PromEx plugin for PostgreSQL metrics.

  Collects JIT usage statistics from pg_stat_statements when available.
  Silently skips when the extension is not installed (e.g., Fly Postgres).
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = PromEx.metric_prefix(otp_app, :postgres)

    Event.build(
      :postgres_jit_event_metrics,
      [
        last_value(
          metric_prefix ++ [:jit, :functions_total],
          event_name: [:postgres, :jit, :stats],
          measurement: :jit_functions,
          description: "Total JIT-compiled functions across all statements"
        ),
        last_value(
          metric_prefix ++ [:jit, :time_milliseconds_total],
          event_name: [:postgres, :jit, :stats],
          measurement: :jit_time_ms,
          unit: :millisecond,
          description: "Total JIT compilation time in milliseconds"
        ),
        last_value(
          metric_prefix ++ [:jit, :queries_count],
          event_name: [:postgres, :jit, :stats],
          measurement: :queries_using_jit,
          description: "Number of distinct queries that used JIT"
        )
      ]
    )
  end
end
