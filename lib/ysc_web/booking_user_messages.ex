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
    "Important: changing your dates affects refunds"
  end

  def clear_lake_blackout_date(date_str) do
    "The cabin isn't open for bookings on #{date_str}. This date may be reserved for maintenance or a club event. Please choose different dates, or contact info@ysc.org if you have questions."
  end

  def checkout_guest_info_step_enter_guests do
    "Enter the name of every guest who will stay in your room(s)"
  end

  def checkout_guest_info_step_continue_payment do
    "Continue to payment and complete checkout before the timer runs out"
  end

  def checkout_guest_info_step_continue_complimentary do
    "Continue to confirm your booking before the timer runs out"
  end

  def checkout_payment_step_pay do
    "Complete your secure payment above"
  end

  def checkout_payment_step_confirm_complimentary do
    "Confirm your booking above"
  end

  defp trim(string), do: String.trim(string)
end
