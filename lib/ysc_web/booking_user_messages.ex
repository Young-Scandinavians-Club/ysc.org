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
    "You will not get a refund if you change these dates"
  end

  def modification_forfeiture_body do
    trim("""
    If you change this reservation, you cannot get a refund later — even if our usual cancellation rules would have allowed one. You can still cancel, but you won't receive money back. This cannot be undone.
    """)
  end

  def modification_forfeiture_acknowledgment do
    "I understand that if I change this reservation, I will not receive a refund — even if our usual cancellation policy would have allowed one."
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
    "Enter the name of every guest who will stay in your room(s)"
  end

  def checkout_guest_info_step_continue_payment do
    "Continue to payment — your hold on these dates expires soon, so please finish checkout"
  end

  def checkout_guest_info_step_continue_complimentary do
    "Continue to confirm your booking — your hold on these dates expires soon, so please finish checkout"
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

  def checkout_payment_step_pay do
    "Enter your payment details in the payment section to complete your booking"
  end

  def checkout_payment_step_confirm_complimentary do
    "Review the booking details and confirm your reservation"
  end

  defp trim(string), do: String.trim(string)
end
