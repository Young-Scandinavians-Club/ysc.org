defmodule YscWeb.Emails.BookingHelpers do
  @moduledoc """
  Shared booking payload maps for member and staff booking emails.

  Confirmation, modification, cancellation, and refund templates all render
  the same stay summary (property, dates, guest counts) and the same payment
  reference/amount pair. Call `booking_summary/1` and `payment_summary/1`
  instead of rebuilding those maps in each template module.

  Cabin-master and treasurer cancellation emails share the full staff
  payload — call `staff_cancellation_email_data/4`.

  ## Examples

      booking_summary(booking)
      payment_summary(payment)

      staff_cancellation_email_data(booking, payment, pending_refund, reason)
  """

  import YscWeb.Emails.Helpers,
    only: [
      admin_booking_url: 1,
      admin_pending_refunds_url: 1,
      booking_receipt_url: 1,
      ensure_booking: 1,
      format_date: 1,
      format_datetime: 1,
      format_money: 1,
      member_full_name: 1,
      member_greeting_name: 1
    ]

  alias Ysc.Bookings.PropertyDisplay

  @no_reason "No reason provided"
  @na "N/A"

  @doc """
  Formats the stay fields shared by member and staff booking emails.

  `property` is the short display name (`"Tahoe"`, `"Clear Lake"`). Dates are
  formatted with `format_date/1`. Nil `children_count` becomes `0`.
  """
  def booking_summary(%{} = booking) do
    %{
      reference_id: booking.reference_id,
      property: PropertyDisplay.short_name(booking.property),
      checkin_date: format_date(booking.checkin_date),
      checkout_date: format_date(booking.checkout_date),
      guests_count: booking.guests_count,
      children_count: booking.children_count || 0
    }
  end

  @doc """
  Formats a payment's reference and amount, or `"N/A"` when payment is nil.
  """
  def payment_summary(nil), do: %{reference_id: @na, amount: @na}

  def payment_summary(%{reference_id: reference_id, amount: amount}) do
    %{reference_id: reference_id, amount: format_money(amount)}
  end

  @doc """
  Member greeting plus receipt URL and property reply-to.

  Merge extra template assigns onto this map in member-facing emails.
  """
  def member_links(%{} = booking) do
    %{
      first_name: member_greeting_name(booking.user),
      booking_url: booking_receipt_url(booking.id),
      cabin_email: Ysc.EmailConfig.booking_reply_to(booking.property)
    }
  end

  @doc """
  Guest name and email for staff-facing booking emails.
  """
  def staff_user_summary(%{} = user) do
    %{
      name: member_full_name(user),
      email: user.email
    }
  end

  @doc """
  Normalizes previous stay details from atom- or string-keyed maps.

  Missing `children_count` becomes `0`. `total_price` and `additional_payment`
  are included when present so member modification emails can reuse the same
  helper as staff notifications.
  """
  def normalize_previous_details(details) when is_map(details) do
    %{
      checkin_date: map_get(details, :checkin_date),
      checkout_date: map_get(details, :checkout_date),
      guests_count: map_get(details, :guests_count),
      children_count: map_get(details, :children_count) || 0,
      total_price: map_get(details, :total_price),
      additional_payment: map_get(details, :additional_payment)
    }
  end

  @doc """
  Formats previous stay dates and guest counts for modification emails.
  """
  def previous_stay_summary(%{} = previous) do
    %{
      checkin_date: format_date(previous.checkin_date),
      checkout_date: format_date(previous.checkout_date),
      guests_count: previous.guests_count,
      children_count: previous.children_count
    }
  end

  @doc """
  Flags whether dates or guest counts changed versus `previous`.

  `previous` should already be passed through `normalize_previous_details/1`
  so `children_count` is an integer.
  """
  def stay_changes(%{} = booking, %{} = previous) do
    %{
      dates_changed:
        previous.checkin_date != booking.checkin_date or
          previous.checkout_date != booking.checkout_date,
      guests_changed:
        previous.guests_count != booking.guests_count or
          previous.children_count != (booking.children_count || 0)
    }
  end

  @doc """
  Shared assign map for cabin-master and treasurer cancellation emails.

  Loads `:user` via `ensure_booking/1`. `pending_refund` is optional; when
  present, `requires_review` is true and `review_url` points at the pending
  refunds list for the booking's property.
  """
  def staff_cancellation_email_data(
        booking,
        payment \\ nil,
        pending_refund \\ nil,
        reason \\ nil
      ) do
    booking = ensure_booking(booking)
    requires_review? = not is_nil(pending_refund)

    %{
      booking: booking_summary(booking),
      user: staff_user_summary(booking.user),
      cancellation: %{
        date: format_datetime(DateTime.utc_now()),
        reason: cancellation_reason(reason, pending_refund)
      },
      payment: payment_summary(payment),
      pending_refund: pending_refund_fields(pending_refund),
      requires_review: requires_review?,
      review_url: review_url(requires_review?, booking.property),
      booking_url: admin_booking_url(booking.id)
    }
  end

  defp cancellation_reason(reason, pending_refund) do
    reason || pending_refund_reason(pending_refund) || @no_reason
  end

  defp pending_refund_reason(nil), do: nil
  defp pending_refund_reason(%{cancellation_reason: reason}), do: reason

  defp pending_refund_fields(nil), do: nil

  defp pending_refund_fields(%{} = pending_refund) do
    %{
      policy_refund_amount: policy_refund_amount_str(pending_refund),
      applied_rule_days_before_checkin:
        pending_refund.applied_rule_days_before_checkin,
      applied_rule_refund_percentage: applied_refund_percentage(pending_refund)
    }
  end

  defp policy_refund_amount_str(%{policy_refund_amount: nil}), do: nil

  defp policy_refund_amount_str(%{policy_refund_amount: amount}),
    do: format_money(amount)

  defp applied_refund_percentage(%{applied_rule_refund_percentage: nil}),
    do: nil

  defp applied_refund_percentage(%{applied_rule_refund_percentage: percentage}) do
    Decimal.to_float(percentage)
  end

  defp review_url(false, _property), do: nil

  defp review_url(true, property), do: admin_pending_refunds_url(property)

  defp map_get(details, key) do
    Map.get(details, key) || Map.get(details, Atom.to_string(key))
  end
end
