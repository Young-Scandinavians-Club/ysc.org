defmodule YscWeb.Emails.BookingRefundProcessed do
  @moduledoc """
  Email template for booking refunds that have been processed.

  Sends a confirmation email to users after their booking refund has been processed.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_refund_processed.mjml.eex",
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
    "booking_refund_processed"
  end

  def get_subject() do
    "Your booking refund is on the way"
  end

  def booking_url(booking_id), do: booking_receipt_url(booking_id)

  @doc """
  Prepares booking refund processed email data.

  ## Parameters:
  - `refund`: The refund record with preloaded associations
  - `booking`: The booking that was refunded
  - `payment`: The original payment

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(refund, booking, payment) do
    if is_nil(refund) do
      raise ArgumentError, "Refund cannot be nil"
    end

    booking = ensure_booking(booking)
    refund_date = format_datetime(refund.inserted_at)
    refund_amount = format_money(refund.amount)

    booking
    |> BookingHelpers.member_links()
    |> Map.merge(%{
      booking: BookingHelpers.booking_summary(booking),
      refund: %{
        reference_id: refund.reference_id,
        amount: refund_amount,
        reason: refund.reason || "Refund issued",
        refund_date: refund_date
      },
      payment: BookingHelpers.payment_summary(payment),
      refund_date: refund_date,
      refund_amount: refund_amount
    })
  end
end
