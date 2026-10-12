defmodule YscWeb.Emails.BookingCancellationConfirmation do
  @moduledoc """
  Email template for booking cancellation confirmation to users.

  Sends a confirmation email to users when they cancel a booking.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_cancellation_confirmation.mjml.eex",
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
    "booking_cancellation_confirmation"
  end

  def get_subject() do
    "Your booking is cancelled"
  end

  def booking_url(booking_id), do: booking_receipt_url(booking_id)

  @doc """
  Prepares booking cancellation confirmation email data.

  ## Parameters:
  - `booking`: The cancelled booking with preloaded associations
  - `payment`: The original payment (optional)
  - `refund_amount`: The refund amount if applicable (optional)
  - `is_pending_refund`: Whether the refund is pending review (optional)
  - `reason`: The cancellation reason (optional)

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(
        booking,
        payment \\ nil,
        refund_amount \\ nil,
        is_pending_refund \\ false,
        reason \\ nil
      ) do
    booking = ensure_booking(booking)

    booking
    |> BookingHelpers.member_links()
    |> Map.merge(%{
      booking: BookingHelpers.booking_summary(booking),
      cancellation: %{
        date: format_datetime(DateTime.utc_now()),
        reason: reason || "No reason provided"
      },
      payment: BookingHelpers.payment_summary(payment),
      refund: %{
        amount: positive_refund_amount(refund_amount),
        is_pending: is_pending_refund
      }
    })
  end

  defp positive_refund_amount(refund_amount) do
    if refund_amount && Money.positive?(refund_amount) do
      format_money(refund_amount)
    else
      nil
    end
  end
end
