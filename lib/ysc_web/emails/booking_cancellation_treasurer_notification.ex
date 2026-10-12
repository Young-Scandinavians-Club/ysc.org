defmodule YscWeb.Emails.BookingCancellationTreasurerNotification do
  @moduledoc """
  Email template for booking cancellation notification to Treasurer.

  Sends an internal notification email to the Treasurer when a booking is cancelled at any property.
  """
  use MjmlEEx,
    mjml_template:
      "templates/booking_cancellation_treasurer_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [admin_pending_refunds_url: 1]

  alias YscWeb.Emails.BookingHelpers

  def get_template_name() do
    "booking_cancellation_treasurer_notification"
  end

  def get_subject(requires_review \\ false) do
    if requires_review do
      "Booking Cancellation - Action Required"
    else
      "Booking Cancellation - Financial Notification"
    end
  end

  def admin_bookings_url(property), do: admin_pending_refunds_url(property)

  @doc """
  Prepares booking cancellation treasurer notification email data.

  ## Parameters:
  - `booking`: The cancelled booking with preloaded associations
  - `payment`: The original payment (optional)
  - `pending_refund`: The pending refund if review is required (optional)
  - `reason`: The cancellation reason (optional)

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(
        booking,
        payment \\ nil,
        pending_refund \\ nil,
        reason \\ nil
      ) do
    BookingHelpers.staff_cancellation_email_data(
      booking,
      payment,
      pending_refund,
      reason
    )
  end
end
