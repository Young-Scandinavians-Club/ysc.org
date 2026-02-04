defmodule YscWeb.Emails.BookingCancellationTreasurerNotification do
  @moduledoc """
  Email template for booking cancellation notification to Treasurer.

  Sends an internal notification email to the Treasurer when a booking is cancelled at any property.
  """
  use MjmlEEx,
    mjml_template:
      "templates/booking_cancellation_treasurer_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Repo
  alias Ysc.Bookings.Booking

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

  def admin_bookings_url(property) do
    property_param =
      case property do
        :tahoe -> "tahoe"
        :clear_lake -> "clear_lake"
        _ -> to_string(property)
      end

    YscWeb.Endpoint.url() <>
      "/admin/bookings?section=pending_refunds&property=#{property_param}"
  end

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
    # Validate input
    if is_nil(booking) do
      raise ArgumentError, "Booking cannot be nil"
    end

    # Ensure we have all necessary preloaded data
    booking =
      if Ecto.assoc_loaded?(booking.user) do
        booking
      else
        case Repo.get(Booking, booking.id) |> Repo.preload(:user) do
          nil ->
            raise ArgumentError, "Booking not found: #{booking.id}"

          loaded_booking ->
            loaded_booking
        end
      end

    # Validate required associations
    if is_nil(booking.user) do
      raise ArgumentError, "Booking missing user association: #{booking.id}"
    end

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
    property_name = get_property_name(booking.property)

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
        name:
          "#{booking.user.first_name || ""} #{booking.user.last_name || ""}"
          |> String.trim(),
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
      booking_url: booking_url(booking.id)
    }
  end

  defp booking_url(booking_id) do
    YscWeb.Endpoint.url() <> "/admin/bookings/#{booking_id}"
  end

  defp get_property_name(:clear_lake), do: "Clear Lake"
  defp get_property_name(:tahoe), do: "Tahoe"

  defp get_property_name(property) when is_atom(property),
    do: String.capitalize(to_string(property))

  defp get_property_name(property), do: to_string(property)

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_datetime(datetime) do
    # Convert to PST
    pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
  end

  defp format_money(%Money{} = money) do
    Money.to_string!(money,
      separator: ".",
      delimiter: ",",
      fractional_digits: 2
    )
  end

  defp format_money(_), do: "$0.00"
end
