defmodule YscWeb.BookingActions do
  @moduledoc """
  Shared helpers for member booking actions (cancel, change reservation).
  """

  alias Ysc.Bookings
  alias Ysc.Bookings.Booking

  @doc """
  Returns true when a member may cancel or change a booking.
  """
  def can_cancel_booking?(%Booking{} = booking) do
    today_pst = get_today_pst()

    booking.status in [:complete, :hold] &&
      (Date.compare(booking.checkin_date, today_pst) == :gt ||
         (Date.compare(booking.checkin_date, today_pst) == :eq &&
            before_checkin_time_today?()))
  end

  @doc """
  Returns true when a member may change a completed booking's dates or guest counts.
  """
  def can_change_booking?(%Booking{} = booking) do
    booking.status == :complete && can_cancel_booking?(booking)
  end

  @doc """
  Returns true when refund eligibility was forfeited by a prior modification.
  """
  def refund_forfeited?(%Booking{} = booking),
    do: not is_nil(booking.refund_forfeited_at)

  def get_today_pst do
    DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
  end

  defp before_checkin_time_today? do
    now_pst = DateTime.now!("America/Los_Angeles")
    today_pst = DateTime.to_date(now_pst)

    checkin_datetime_today =
      DateTime.new!(today_pst, Bookings.checkin_time(), "America/Los_Angeles")

    DateTime.compare(now_pst, checkin_datetime_today) == :lt
  end
end
