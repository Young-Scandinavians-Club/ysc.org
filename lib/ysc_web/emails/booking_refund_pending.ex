defmodule YscWeb.Emails.BookingRefundPending do
  @moduledoc """
  Email template for booking refunds that are pending approval.

  Sends a notification email to users when their cancelled booking's refund
  is waiting for Cabin Master review.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_refund_pending.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      booking_receipt_url: 1,
      ensure_booking: 1,
      format_datetime: 1,
      format_money: 1
    ]

  alias YscWeb.Emails.BookingHelpers

  def get_template_name() do
    "booking_refund_pending"
  end

  def get_subject() do
    "We're reviewing your cabin booking refund"
  end

  def booking_url(booking_id), do: booking_receipt_url(booking_id)

  @doc """
  Prepares booking refund pending email data.

  ## Parameters:
  - `pending_refund`: The pending refund record with preloaded associations
  - `booking`: The booking that was cancelled
  - `payment`: The original payment

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(pending_refund, booking, payment) do
    if is_nil(pending_refund) do
      raise ArgumentError, "Pending refund cannot be nil"
    end

    booking = ensure_booking(booking)
    request_date = format_datetime(pending_refund.inserted_at)
    policy_refund_amount = format_money(pending_refund.policy_refund_amount)

    booking
    |> BookingHelpers.member_links()
    |> Map.merge(%{
      booking: BookingHelpers.booking_summary(booking),
      pending_refund: %{
        policy_refund_amount: policy_refund_amount,
        cancellation_reason:
          pending_refund.cancellation_reason || "Booking cancelled",
        request_date: request_date,
        refund_percentage: refund_percentage(pending_refund, payment)
      },
      payment: BookingHelpers.payment_summary(payment),
      request_date: request_date,
      policy_refund_amount: policy_refund_amount
    })
  end

  defp refund_percentage(_pending_refund, nil), do: nil

  defp refund_percentage(pending_refund, payment) do
    if Money.positive?(payment.amount) &&
         Money.positive?(pending_refund.policy_refund_amount) do
      pending_refund.policy_refund_amount.amount
      |> Decimal.div(payment.amount.amount)
      |> Decimal.mult(Decimal.new(100))
      |> Decimal.round(1)
      |> Decimal.to_float()
    else
      nil
    end
  end
end
