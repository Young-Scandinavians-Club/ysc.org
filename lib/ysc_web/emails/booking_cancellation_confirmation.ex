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
      absolute_url: 1,
      member_greeting_name: 1,
      format_date: 1,
      format_datetime: 1,
      format_money: 1
    ]

  alias Ysc.Repo
  alias Ysc.Bookings.Booking
  alias Ysc.Bookings.PropertyDisplay

  def get_template_name() do
    "booking_cancellation_confirmation"
  end

  def get_subject() do
    "Booking Cancellation Confirmed"
  end

  def booking_url(booking_id) do
    absolute_url("/bookings/#{booking_id}/receipt")
  end

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
    booking = validate_and_load_booking(booking)
    formatted_dates = format_booking_dates(booking)
    formatted_amounts = format_payment_amounts(payment, refund_amount)
    property_name = PropertyDisplay.short_name(booking.property)

    build_email_data(
      booking,
      formatted_dates,
      formatted_amounts,
      property_name,
      payment,
      is_pending_refund,
      reason
    )
  end

  defp validate_and_load_booking(booking) do
    if is_nil(booking) do
      raise ArgumentError, "Booking cannot be nil"
    end

    booking = ensure_user_loaded(booking)

    if is_nil(booking.user) do
      raise ArgumentError, "Booking missing user association: #{booking.id}"
    end

    booking
  end

  defp ensure_user_loaded(booking) do
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
  end

  defp format_booking_dates(booking) do
    %{
      checkin_date: format_date(booking.checkin_date),
      checkout_date: format_date(booking.checkout_date),
      cancellation_date: format_datetime(DateTime.utc_now())
    }
  end

  defp format_payment_amounts(payment, refund_amount) do
    %{
      original_amount:
        if(payment, do: format_money(payment.amount), else: "N/A"),
      refund_amount:
        if(refund_amount && Money.positive?(refund_amount),
          do: format_money(refund_amount),
          else: nil
        )
    }
  end

  defp build_email_data(
         booking,
         formatted_dates,
         formatted_amounts,
         property_name,
         payment,
         is_pending_refund,
         reason
       ) do
    %{
      first_name: member_greeting_name(booking.user),
      booking: %{
        reference_id: booking.reference_id,
        property: property_name,
        checkin_date: formatted_dates.checkin_date,
        checkout_date: formatted_dates.checkout_date,
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0
      },
      cancellation: %{
        date: formatted_dates.cancellation_date,
        reason: reason || "No reason provided"
      },
      payment: %{
        reference_id: if(payment, do: payment.reference_id, else: "N/A"),
        amount: formatted_amounts.original_amount
      },
      refund: %{
        amount: formatted_amounts.refund_amount,
        is_pending: is_pending_refund
      },
      booking_url: booking_url(booking.id)
    }
  end
end
