defmodule Ysc.PromEx.Plugins.Oban do
  @moduledoc """
  PromEx Oban plugin wrapper that keeps queue-length polling resilient.

  Upstream `PromEx.Plugins.Oban.execute_queue_metrics/1` queries the DB every
  poll interval. Transient `DBConnection.ConnectionError`s (idle disconnects,
  proxy blips) would otherwise raise into `telemetry_poller`, which logs at
  error level and permanently drops the measurement. This wrapper swallows
  those connection errors so metrics keep polling and Sentry stays quiet.
  """

  use PromEx.Plugin

  require Ysc.Logging

  @impl true
  def event_metrics(opts), do: PromEx.Plugins.Oban.event_metrics(opts)

  @impl true
  def polling_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    metric_prefix =
      Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :oban))

    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    oban_supervisors =
      opts
      |> Keyword.get(:oban_supervisors, [Oban])
      |> MapSet.new()

    polling_opts = Keyword.get(opts, :opts, [])

    Polling.build(
      :oban_queue_poll_metrics,
      poll_rate,
      {__MODULE__, :execute_queue_metrics, [oban_supervisors]},
      [
        last_value(
          metric_prefix ++ [:queue, :length, :count],
          event_name: [:prom_ex, :plugin, :oban, :queue, :length, :count],
          description:
            "The total number jobs that are in the queue in the designated state",
          measurement: :count,
          tags: [:name, :queue, :state]
        )
      ],
      polling_opts
    )
  end

  @doc false
  def execute_queue_metrics(
        oban_supervisors,
        runner \\ &PromEx.Plugins.Oban.execute_queue_metrics/1
      ) do
    runner.(oban_supervisors)
  rescue
    exception in [DBConnection.ConnectionError] ->
      Ysc.Logging.warning(
        "PromEx Oban queue metrics skipped (transient DB connection error)",
        error: exception
      )

      :ok
  end
end
