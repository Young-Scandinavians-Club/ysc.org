defmodule Ysc.PromEx.Plugins.Ysc do
  @moduledoc """
  PromEx plugin that exports YSC application/business telemetry metrics.

  PromEx only scrapes metrics declared by plugins. Custom metrics defined on
  `Ysc.PromEx` must be wrapped in a plugin or they never appear on `/metrics`
  (and therefore never on Fly Metrics / Grafana).
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :ysc_application_event_metrics,
      Ysc.PromEx.metrics()
    )
  end
end
