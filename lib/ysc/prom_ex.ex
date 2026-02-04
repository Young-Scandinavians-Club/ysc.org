defmodule Ysc.PromEx do
  @moduledoc """
  PromEx is a Prometheus metrics exporter for Elixir applications.

  This module configures PromEx to collect and expose metrics for:
  - Phoenix (router, endpoint)
  - Phoenix LiveView (mount, handle_event, render)
  - Ecto (database queries)
  - BEAM VM (memory, processes, etc.)
  - Oban (background jobs)
  - Custom application metrics (tickets, bookings, payments, ledger)
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
