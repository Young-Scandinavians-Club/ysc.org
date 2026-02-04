defmodule YscWeb.Emails.BookingRefundPending do
  @moduledoc """
  Email template for booking refunds that are pending approval.

  Sends a notification email to users when their booking refund request is pending admin review.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_refund_pending.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "booking_refund_pending"
  end

  def get_subject() do
    "Your booking refund request is under review"
  end

  def booking_url(booking_id) do
    YscWeb.Endpoint.url() <> "/bookings/#{booking_id}/receipt"
  end

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
    # Validate input
    if is_nil(pending_refund) do
      raise ArgumentError, "Pending refund cannot be nil"
    end

    if is_nil(booking) do
      raise ArgumentError, "Booking cannot be nil"
    end

    # Ensure we have all necessary preloaded data
    # Reload booking with user association if not already loaded
    booking =
      if Ecto.assoc_loaded?(booking.user) do
        booking
      else
        case Ysc.Repo.get(Ysc.Bookings.Booking, booking.id)
             |> Ysc.Repo.preload(:user) do
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
    request_date = format_datetime(pending_refund.inserted_at)

    # Format money amounts
    policy_refund_amount = format_money(pending_refund.policy_refund_amount)
    original_amount = if payment, do: format_money(payment.amount), else: "N/A"

    # Get property name
    property_name = get_property_name(booking.property)

    # Calculate refund percentage
    refund_percentage =
      if payment && Money.positive?(payment.amount) &&
           Money.positive?(pending_refund.policy_refund_amount) do
        case Money.div(pending_refund.policy_refund_amount, payment.amount) do
          {:ok, ratio} ->
            Decimal.mult(ratio, Decimal.new(100))
            |> Decimal.round(1)
            |> Decimal.to_float()

          _ ->
            nil
        end
      else
        nil
      end

    %{
      first_name: booking.user.first_name || "Valued Member",
      booking: %{
        reference_id: booking.reference_id,
        property: property_name,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0
      },
      pending_refund: %{
        policy_refund_amount: policy_refund_amount,
        cancellation_reason:
          pending_refund.cancellation_reason || "Booking cancelled",
        request_date: request_date,
        refund_percentage: refund_percentage
      },
      payment: %{
        reference_id: if(payment, do: payment.reference_id, else: "N/A"),
        amount: original_amount
      },
      request_date: request_date,
      policy_refund_amount: policy_refund_amount,
      booking_url: booking_url(booking.id)
    }
  end

  defp get_property_name(:clear_lake), do: "Clear Lake"
  defp get_property_name(:tahoe), do: "Tahoe"

  defp get_property_name(property) when is_atom(property),
    do: String.capitalize(to_string(property))

  defp get_property_name(property), do: to_string(property)

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_datetime(nil), do: "N/A"

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
