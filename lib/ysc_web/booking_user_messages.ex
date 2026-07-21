defmodule YscWeb.BookingUserMessages do
  @moduledoc false

  def reservation_not_found do
    trim("""
    We couldn't find this reservation. It may have expired, already been completed, or belong to a different account. Contact info@ysc.org if you need help.
    """)
  end

  def checkout_not_found do
    trim("""
    We couldn't find this reservation. It may have expired, already been completed, or belong to a different account. If you were checking out, start a new booking from the cabin page. Contact info@ysc.org if you need help.
    """)
  end

  def modification_acknowledgment_required do
    "Please check the box at the bottom of the form confirming you understand that changing this reservation means you won't receive a refund, even if our usual cancellation policy would allow one."
  end

  def modification_forfeiture_title do
    "No refunds for changed dates"
  end

  def modification_forfeiture_body do
    trim("""
    If you change this reservation, you cannot get a refund later — even if our usual cancellation rules would have allowed one.
    """)
  end

  def modification_forfeiture_acknowledgment do
    "I understand and accept that this change makes my booking non-refundable."
  end

  def clear_lake_blackout_date(date_str) do
    "The cabin isn't open for bookings on #{date_str}. This date may be reserved for maintenance or a club event. Please choose different dates, or contact info@ysc.org if you have questions."
  end

  def unavailable_blackout_dates do
    trim("""
    These dates aren't available for booking. They may be reserved for maintenance or a club event. Please choose different dates, or contact info@ysc.org if you have questions.
    """)
  end

  def checkout_guest_info_step_enter_guests do
    "Enter the names of everyone else staying with you (you're already counted as a guest)"
  end

  def checkout_guest_info_step_continue_payment do
    "Continue to payment — these dates are held temporarily, not confirmed yet. Finish checkout soon or they'll go back on the calendar."
  end

  def checkout_guest_info_step_continue_complimentary do
    "Continue to confirm your booking — these dates are held temporarily, not confirmed yet. Finish checkout soon or they'll go back on the calendar."
  end

  def insufficient_capacity_error(opts \\ []) do
    if Keyword.get(opts, :include_guest_count, false) do
      "There aren't enough open spots at the cabin for your dates and group size. Try fewer guests, different dates, or reserve the whole cabin."
    else
      "There aren't enough open spots at the cabin for your dates. Try different dates, fewer guests, or reserve the whole cabin."
    end
  end

  def insufficient_capacity_summary do
    "Not enough space available"
  end

  def property_unavailable_error do
    "The cabin isn't available for those dates. Try different dates or reserve the whole cabin."
  end

  def property_unavailable_summary do
    "Cabin unavailable"
  end

  def membership_required_link_text do
    "Membership page"
  end

  def membership_required_message_html(membership_path) do
    link =
      ~s(<a href="#{membership_path}" class="font-semibold text-amber-900 hover:text-amber-950 underline">#{membership_required_link_text()}</a>)

    "You need an active YSC membership to book the cabin. Go to your #{link} to pay or renew."
  end

  def membership_required_plain_message do
    "You need an active YSC membership to book the cabin. Visit your membership page to pay or renew."
  end

  def application_pending_approval_message do
    "Your membership application is still being reviewed by the board. You'll be able to make bookings after your application is approved and your membership is active."
  end

  def checkout_payment_step_pay do
    "Enter your payment details in the payment section to complete your booking"
  end

  def checkout_payment_step_confirm_complimentary do
    "Review the booking details below, then click Confirm booking to secure these dates"
  end

  def checkout_confirmation_email_step do
    "You'll get a confirmation email right away with your booking details"
  end

  def checkout_cabin_access_step do
    "You'll receive cabin access details (door code or key instructions) by email before check-in"
  end

  def checkout_manage_booking_step do
    "View or change your reservation anytime from My Bookings & Tickets in your account menu, or use the link in your confirmation email"
  end

  def checkout_pricing_load_failed do
    trim("""
    We couldn't load the pricing for this booking. Please go back and try again, or email info@ysc.org if this keeps happening.
    """)
  end

  def checkout_payment_setup_failed do
    trim("""
    We couldn't set up payment. Please try again, or email info@ysc.org for help.
    """)
  end

  def checkout_payment_confirmation_failed do
    trim("""
    Something went wrong while confirming your booking. If you see a charge on your card, email info@ysc.org with the date and amount before trying to pay again — we'll make sure you're not charged twice.
    """)
  end

  def checkout_booking_confirmation_failed do
    trim("""
    We couldn't confirm your booking. Please try again, or email info@ysc.org for help.
    """)
  end

  def checkout_cancel_failed do
    trim("""
    We couldn't cancel this booking from here. Please try again, or email info@ysc.org if you need help.
    """)
  end

  def checkout_hold_expired do
    trim("""
    Your hold on these dates has expired and they've been released. Go back to the cabin page and start a new booking.
    """)
  end

  def checkout_hold_expired_toast do
    "Your hold on these dates has expired. Start a new booking from the cabin page."
  end

  def booking_creation_failed do
    trim("""
    We couldn't complete your booking. Your card has not been charged. Please try again, or choose different dates. If the problem continues, email info@ysc.org with your dates and guest count.
    """)
  end

  def booking_creation_failed_sidebar do
    "Couldn't complete booking. Your card wasn't charged — try again."
  end

  def modification_redirect_hold_expired do
    trim("""
    Your payment went through, but we couldn't save your new dates in time. Your original reservation is unchanged. Try changing your dates again from this booking page. If you were charged twice or your dates look wrong, email info@ysc.org with #{booking_reference_support_phrase()}.
    """)
  end

  def modification_redirect_ledger_payment_failed do
    trim("""
    Your payment went through, but we couldn't record it for your updated reservation. #{modification_after_payment_recovery_body()}
    """)
  end

  def modification_redirect_update_failed do
    trim("""
    Your payment went through, but we couldn't update your reservation. #{modification_after_payment_recovery_body()}
    """)
  end

  def modification_finalize_failed do
    trim("""
    Your payment went through, but we couldn't save your new dates. #{modification_after_payment_recovery_body()}
    """)
  end

  def modification_after_payment_recovery_suffix do
    " #{modification_after_payment_recovery_body()}"
  end

  def cancel_refund_error(reason) do
    support = "Email info@ysc.org with #{booking_reference_support_phrase()}"

    case reason do
      {:payment_not_found, _} ->
        "We cancelled your reservation, but we couldn't find your payment record to process a refund. #{support} and we'll help."

      {:calculation_failed, _} ->
        "We cancelled your reservation, but we couldn't calculate your refund right now. #{support} and we'll follow up."

      {:refund_failed, _} ->
        "We cancelled your reservation, but your refund couldn't be processed automatically. #{support} and we'll help."

      {:pending_refund_failed, _} ->
        "We cancelled your reservation, but we couldn't submit your refund for review. #{support} and we'll follow up."

      {:cancellation_failed, _} ->
        "We couldn't cancel your reservation. Please try again, or email info@ysc.org if the problem continues."
    end
  end

  def booking_reference_support_phrase do
    "your booking reference (shown on your receipt as Booking Reference)"
  end

  defp modification_after_payment_recovery_body do
    "Open this booking from My Bookings & Tickets (under your account menu) and check whether the dates updated. If they didn't, email info@ysc.org with #{booking_reference_support_phrase()}."
  end

  defp trim(string), do: String.trim(string)
end
