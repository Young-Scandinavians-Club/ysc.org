defmodule YscWeb.Emails.BookingCancellationCabinMasterNotification do
  @moduledoc """
  Email template for booking cancellation notification to Cabin Master.

  Sends an internal notification email to the Cabin Master when a booking is cancelled at their property.
  """
  use MjmlEEx,
    mjml_template:
      "templates/booking_cancellation_cabin_master_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      admin_booking_url: 1,
      admin_pending_refunds_url: 1,
      ensure_booking: 1,
      format_date: 1,
      format_datetime: 1,
      format_money: 1,
      member_full_name: 1
    ]

  alias Ysc.Bookings.PropertyDisplay

  def get_template_name() do
    "booking_cancellation_cabin_master_notification"
  end

  def get_subject(requires_review \\ true) do
    if requires_review do
      "Booking Cancellation - Action Required"
    else
      "Booking Cancellation Notification"
    end
  end

  def admin_bookings_url(property), do: admin_pending_refunds_url(property)

  @doc """
  Prepares booking cancellation cabin master notification email data.

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
    booking = ensure_booking(booking)

    # Format dates
    checkin_date = format_date(booking.checkin_date)
    checkout_date = format_date(booking.checkout_date)
    cancellation_date = format_datetime(DateTime.utc_now())

    # Format money amounts
    original_amount = if payment, do: format_money(payment.amount), else: "N/A"

    refund_amount =
      if pending_refund && pending_refund.policy_refund_amount,
        do: format_money(pending_refund.policy_refund_amount),
        else: nil

    # Get property name
    property_name = PropertyDisplay.short_name(booking.property)

    # Determine if review is required
    requires_review = not is_nil(pending_refund)

    review_url =
      if requires_review, do: admin_bookings_url(booking.property), else: nil

    %{
      booking: %{
        reference_id: booking.reference_id,
        property: property_name,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0
      },
      user: %{
        name: member_full_name(booking.user),
        email: booking.user.email
      },
      cancellation: %{
        date: cancellation_date,
        reason:
          reason ||
            if(pending_refund,
              do: pending_refund.cancellation_reason,
              else: nil
            ) ||
            "No reason provided"
      },
      payment: %{
        reference_id: if(payment, do: payment.reference_id, else: "N/A"),
        amount: original_amount
      },
      pending_refund:
        if(pending_refund,
          do: %{
            policy_refund_amount: refund_amount,
            applied_rule_days_before_checkin:
              pending_refund.applied_rule_days_before_checkin,
            applied_rule_refund_percentage:
              if(pending_refund.applied_rule_refund_percentage,
                do:
                  Decimal.to_float(
                    pending_refund.applied_rule_refund_percentage
                  ),
                else: nil
              )
          },
          else: nil
        ),
      requires_review: requires_review,
      review_url: review_url,
      booking_url: admin_booking_url(booking.id)
    }
  end
end
