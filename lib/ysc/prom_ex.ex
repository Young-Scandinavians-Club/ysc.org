defmodule Ysc.PromEx do
  @moduledoc """
  PromEx is a Prometheus metrics exporter for Elixir applications.

  This module configures PromEx to collect and expose metrics for:
  - Phoenix (router, endpoint)
  - Phoenix LiveView (mount, handle_event, render)
  - Ecto (database queries)
  - BEAM VM (memory, processes, etc.)
  - Oban (background jobs)
  - Custom application metrics (tickets, bookings, booking config caches, payments, ledger)
  """

  use PromEx, otp_app: :ysc

  import Telemetry.Metrics

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # Phoenix metrics
      {Plugins.Phoenix, router: YscWeb.Router, endpoint: YscWeb.Endpoint},
      # LiveView metrics
      Plugins.PhoenixLiveView,
      # Ecto metrics
      Plugins.Ecto,
      # BEAM VM metrics
      Plugins.Beam,
      # Oban metrics
      Plugins.Oban
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      otp_app: :ysc,
      datasource_id: "prometheus"
    ]
  end

  @dialyzer {:nowarn_function, dashboards: 0}
  @impl true
  def dashboards do
    [
      # PromEx built-in dashboards
      :prom_ex,
      :phoenix,
      :ecto,
      :oban
    ]
  end

  @dialyzer {:nowarn_function, metrics: 0}
  def metrics do
    [
      # Ticket Order Metrics
      counter("ysc.tickets.order_created.total",
        event_name: [:ysc, :tickets, :order_created],
        description: "Total number of ticket orders created",
        tags: [:event_id, :user_id],
        tag_values: &extract_ticket_order_tags/1
      ),
      counter("ysc.tickets.payment_processed.total",
        event_name: [:ysc, :tickets, :payment_processed],
        description: "Total number of ticket order payments processed",
        tags: [:event_id, :status],
        tag_values: &extract_payment_tags/1,
        measurement: :count
      ),
      summary("ysc.tickets.payment_processed.duration.milliseconds",
        event_name: [:ysc, :tickets, :payment_processed],
        description:
          "Duration of ticket order payment processing in milliseconds",
        buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000],
        tags: [:event_id, :status],
        tag_values: &extract_payment_tags/1,
        measurement: :duration
      ),
      counter("ysc.tickets.timeout_expired.total",
        event_name: [:ysc, :tickets, :timeout_expired],
        description: "Total number of ticket orders expired due to timeout",
        measurement: :count
      ),
      counter("ysc.tickets.overbooking_attempt.total",
        event_name: [:ysc, :tickets, :overbooking_attempt],
        description: "Total number of overbooking attempts",
        tags: [:event_id, :reason],
        tag_values: &extract_overbooking_tags/1
      ),

      # Booking Metrics
      counter("ysc.bookings.booking_created.total",
        event_name: [:ysc, :bookings, :booking_created],
        description: "Total number of bookings created",
        tags: [:property, :booking_mode],
        tag_values: &extract_booking_tags/1
      ),
      counter("ysc.bookings.payment_processed.total",
        event_name: [:ysc, :bookings, :payment_processed],
        description: "Total number of booking payments processed",
        tags: [:property, :booking_mode, :status],
        tag_values: &extract_booking_payment_tags/1
      ),
      counter("ysc.bookings.hold_expired.total",
        event_name: [:ysc, :bookings, :hold_expired],
        description: "Total number of booking holds expired",
        tags: [:property, :booking_mode],
        tag_values: &extract_booking_tags/1
      ),
      counter("ysc.bookings.hold_expired_batch.total",
        event_name: [:ysc, :bookings, :hold_expired_batch],
        description: "Total number of booking holds expired in batch",
        measurement: :count
      ),

      # Booking config-cache metrics (admin settings → open booking sessions)
      counter("ysc.bookings.config_cache.invalidated.total",
        event_name: [:ysc, :bookings, :config_cache, :invalidated],
        description:
          "Total booking config cache invalidations (season, rooms, pricing, etc.)",
        tags: [:cache],
        tag_values: &extract_config_cache_tags/1,
        measurement: :count
      ),
      counter("ysc.bookings.config_cache.live_rebuild.total",
        event_name: [:ysc, :bookings, :config_cache, :live_rebuild],
        description:
          "Total LiveView rebuilds after booking config cache invalidation",
        tags: [:live_view, :cache],
        tag_values: &extract_config_cache_live_rebuild_tags/1,
        measurement: :count
      ),

      # Payment Metrics
      counter("ysc.payments.stripe_webhook_received.total",
        event_name: [:ysc, :payments, :stripe_webhook_received],
        description: "Total number of Stripe webhooks received",
        tags: [:event_type],
        tag_values: &extract_webhook_tags/1
      ),
      summary("ysc.payments.stripe_webhook_processing.duration.milliseconds",
        event_name: [:ysc, :payments, :stripe_webhook_processing_duration],
        description: "Duration of Stripe webhook processing in milliseconds",
        buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000, 10_000],
        tags: [:event_type, :status],
        tag_values: &extract_webhook_processing_tags/1,
        measurement: :duration
      ),

      # Ledger Metrics
      counter("ysc.ledgers.payment_recorded.total",
        event_name: [:ysc, :ledgers, :payment_recorded],
        description: "Total number of payments recorded in ledger",
        tags: [:entity_type],
        tag_values: &extract_ledger_payment_tags/1
      ),
      counter("ysc.ledgers.refund_recorded.total",
        event_name: [:ysc, :ledgers, :refund_recorded],
        description: "Total number of refunds recorded in ledger",
        measurement: :count
      ),
      counter("ysc.ledgers.reconciliation_completed.total",
        event_name: [:ysc, :ledgers, :reconciliation_completed],
        description: "Total number of reconciliation checks completed",
        tags: [:status],
        tag_values: &extract_reconciliation_tags/1
      ),
      summary("ysc.ledgers.reconciliation.duration.milliseconds",
        event_name: [:ysc, :ledgers, :reconciliation_completed],
        description: "Duration of reconciliation checks in milliseconds",
        buckets: [100, 500, 1000, 2500, 5000, 10_000, 30_000, 60_000],
        tags: [:status],
        tag_values: &extract_reconciliation_tags/1,
        measurement: :duration
      ),
      counter("ysc.ledgers.reconciliation_errors.total",
        event_name: [:ysc, :ledgers, :reconciliation_errors],
        description: "Total number of reconciliation errors",
        measurement: :count
      ),
      counter("ysc.email.accepted.total",
        event_name: [:ysc, :email, :accepted],
        description: "Email requests accepted by SES",
        tags: [:template],
        tag_values: &extract_email_tags/1
      ),
      counter("ysc.email.sent.total",
        event_name: [:ysc, :email, :sent],
        description: "Emails successfully delivered to the configured mailer",
        tags: [:template],
        tag_values: &extract_email_tags/1
      ),
      counter("ysc.email.send_failed.total",
        event_name: [:ysc, :email, :send_failed],
        description: "Email delivery attempts that failed",
        tags: [:template],
        tag_values: &extract_email_tags/1
      ),
      counter("ysc.email.rate_limited.total",
        event_name: [:ysc, :email, :rate_limited],
        description: "Email requests delayed by the shared SES limiter",
        tags: [:template],
        tag_values: &extract_email_tags/1
      ),
      counter("ysc.email.ses_throttled.total",
        event_name: [:ysc, :email, :ses_throttled],
        description: "SES throttle responses",
        tags: [:template],
        tag_values: &extract_email_tags/1
      ),
      counter("ysc.email.terminal_failed.total",
        event_name: [:ysc, :email, :terminal_failed],
        description: "Email deliveries that require manual action",
        tags: [:template, :category],
        tag_values: &extract_email_terminal_tags/1
      ),
      counter("ysc.email.hard_bounce.total",
        event_name: [:ysc, :email, :hard_bounce],
        description: "Permanent SES bounces handled by outcome",
        tags: [:outcome],
        tag_values: &extract_email_hard_bounce_tags/1
      ),
      counter("ysc.email.suppressed.total",
        event_name: [:ysc, :email, :suppressed],
        description: "Email deliveries skipped due to recipient suppression",
        tags: [:reason, :template, :category],
        tag_values: &extract_email_suppression_tags/1
      ),
      counter("ysc.email.ses_webhook.events.total",
        event_name: [:ysc, :email, :ses_webhook],
        description: "SES webhook events handled by event type and outcome",
        tags: [:event_type, :outcome],
        tag_values: &extract_ses_webhook_tags/1,
        measurement: :count
      ),
      summary("ysc.email.ses_webhook.processing.duration.milliseconds",
        event_name: [:ysc, :email, :ses_webhook],
        description: "SES webhook processing duration in milliseconds",
        tags: [:event_type, :outcome],
        tag_values: &extract_ses_webhook_tags/1,
        measurement: :duration
      )
    ]
  end

  # Helper functions to extract tag values from telemetry metadata
  defp extract_ticket_order_tags(%{
         ticket_order_id: _id,
         event_id: event_id,
         user_id: user_id
       }) do
    %{event_id: to_string(event_id), user_id: to_string(user_id)}
  end

  defp extract_ticket_order_tags(_),
    do: %{event_id: "unknown", user_id: "unknown"}

  defp extract_payment_tags(%{event_id: event_id, status: status}) do
    %{event_id: to_string(event_id), status: to_string(status)}
  end

  defp extract_payment_tags(_), do: %{event_id: "unknown", status: "unknown"}

  defp extract_overbooking_tags(%{event_id: event_id, reason: reason}) do
    %{event_id: to_string(event_id), reason: to_string(reason)}
  end

  defp extract_overbooking_tags(%{reason: reason}) do
    %{event_id: "unknown", reason: to_string(reason)}
  end

  defp extract_overbooking_tags(_),
    do: %{event_id: "unknown", reason: "unknown"}

  defp extract_booking_tags(%{property: property, booking_mode: booking_mode}) do
    %{property: to_string(property), booking_mode: to_string(booking_mode)}
  end

  defp extract_booking_tags(_),
    do: %{property: "unknown", booking_mode: "unknown"}

  defp extract_booking_payment_tags(%{
         property: property,
         booking_mode: booking_mode,
         status: status
       }) do
    %{
      property: to_string(property),
      booking_mode: to_string(booking_mode),
      status: to_string(status)
    }
  end

  defp extract_booking_payment_tags(_),
    do: %{property: "unknown", booking_mode: "unknown", status: "unknown"}

  defp extract_config_cache_tags(%{cache: cache}) do
    %{cache: to_string(cache)}
  end

  defp extract_config_cache_tags(_), do: %{cache: "unknown"}

  defp extract_config_cache_live_rebuild_tags(%{
         live_view: live_view,
         cache: cache
       }) do
    %{live_view: to_string(live_view), cache: to_string(cache)}
  end

  defp extract_config_cache_live_rebuild_tags(_),
    do: %{live_view: "unknown", cache: "unknown"}

  defp email_tag(nil), do: "unknown"
  defp email_tag(value), do: to_string(value)

  defp extract_email_tags(%{template: template}),
    do: %{template: email_tag(template)}

  defp extract_email_tags(_), do: %{template: "unknown"}

  defp extract_email_terminal_tags(%{template: template, category: category}),
    do: %{template: email_tag(template), category: email_tag(category)}

  defp extract_email_terminal_tags(metadata),
    do: Map.put(extract_email_tags(metadata), :category, "unknown")

  defp extract_email_hard_bounce_tags(%{outcome: outcome}),
    do: %{outcome: email_tag(outcome)}

  defp extract_email_hard_bounce_tags(_), do: %{outcome: "unknown"}

  defp extract_email_suppression_tags(metadata) do
    %{
      reason: metadata |> Map.get(:reason, :unknown) |> email_tag(),
      template: metadata |> Map.get(:template, :unknown) |> email_tag(),
      category: metadata |> Map.get(:category, :unknown) |> email_tag()
    }
  end

  defp extract_ses_webhook_tags(metadata) do
    %{
      event_type: metadata |> Map.get(:event_type, :unknown) |> to_string(),
      outcome: metadata |> Map.get(:outcome, :unknown) |> to_string()
    }
  end

  defp extract_webhook_tags(%{event_type: event_type}) do
    %{event_type: to_string(event_type)}
  end

  defp extract_webhook_tags(_), do: %{event_type: "unknown"}

  defp extract_webhook_processing_tags(%{
         event_type: event_type,
         status: status
       }) do
    %{event_type: to_string(event_type), status: to_string(status)}
  end

  defp extract_webhook_processing_tags(_),
    do: %{event_type: "unknown", status: "unknown"}

  defp extract_ledger_payment_tags(%{entity_type: entity_type}) do
    %{entity_type: to_string(entity_type)}
  end

  defp extract_ledger_payment_tags(_), do: %{entity_type: "unknown"}

  defp extract_reconciliation_tags(%{status: status}) do
    %{status: to_string(status)}
  end

  defp extract_reconciliation_tags(_), do: %{status: "unknown"}
end
