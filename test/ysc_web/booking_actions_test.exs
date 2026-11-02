defmodule YscWeb.BookingActionsTest do
  @moduledoc """
  Member cancel/change gates share Pacific "today" with refund preview.

  #1782 switched `UserBookingDetailLive` confirm-cancel from `Date.utc_today/0`
  to `get_today_pst/0` so the charged refund matches the preview after 5pm PT.
  """
  use ExUnit.Case, async: true

  alias Ysc.Bookings
  alias Ysc.Bookings.Booking
  alias Ysc.ReportingPeriods
  alias YscWeb.BookingActions
  alias YscWeb.TimeZone

  defp booking(attrs) do
    struct(
      Booking,
      Map.merge(
        %{
          status: :complete,
          checkin_date: Date.add(BookingActions.get_today_pst(), 7)
        },
        attrs
      )
    )
  end

  describe "get_today_pst/0" do
    test "is the Pacific calendar date, matching TimeZone and ReportingPeriods" do
      pacific =
        DateTime.utc_now()
        |> DateTime.shift_zone!("America/Los_Angeles")
        |> DateTime.to_date()

      assert BookingActions.get_today_pst() == pacific
      assert BookingActions.get_today_pst() == TimeZone.today()
      assert BookingActions.get_today_pst() == ReportingPeriods.today()
    end
  end

  describe "can_cancel_booking?/1" do
    test "allows complete and hold bookings with a future check-in" do
      future = Date.add(BookingActions.get_today_pst(), 3)

      assert BookingActions.can_cancel_booking?(
               booking(%{status: :complete, checkin_date: future})
             )

      assert BookingActions.can_cancel_booking?(
               booking(%{status: :hold, checkin_date: future})
             )
    end

    test "rejects canceled, draft, and other non-cancellable statuses" do
      future = Date.add(BookingActions.get_today_pst(), 3)

      refute BookingActions.can_cancel_booking?(
               booking(%{status: :canceled, checkin_date: future})
             )

      refute BookingActions.can_cancel_booking?(
               booking(%{status: :draft, checkin_date: future})
             )

      refute BookingActions.can_cancel_booking?(
               booking(%{status: :refunded, checkin_date: future})
             )
    end

    test "rejects bookings whose check-in date is already in the past" do
      yesterday = Date.add(BookingActions.get_today_pst(), -1)

      refute BookingActions.can_cancel_booking?(
               booking(%{status: :complete, checkin_date: yesterday})
             )
    end

    test "on the Pacific check-in day, allows cancel only before check-in time" do
      today = BookingActions.get_today_pst()
      now = TimeZone.now()
      cutoff = TimeZone.at(today, Bookings.checkin_time())
      same_day = booking(%{status: :complete, checkin_date: today})

      if DateTime.compare(now, cutoff) == :lt do
        assert BookingActions.can_cancel_booking?(same_day)
      else
        refute BookingActions.can_cancel_booking?(same_day)
      end
    end
  end

  describe "can_change_booking?/1" do
    test "allows complete future bookings that can still be cancelled" do
      future = Date.add(BookingActions.get_today_pst(), 3)

      assert BookingActions.can_change_booking?(
               booking(%{status: :complete, checkin_date: future})
             )
    end

    test "rejects holds even when cancel is still allowed" do
      future = Date.add(BookingActions.get_today_pst(), 3)

      refute BookingActions.can_change_booking?(
               booking(%{status: :hold, checkin_date: future})
             )
    end

    test "rejects complete bookings whose check-in has already passed" do
      yesterday = Date.add(BookingActions.get_today_pst(), -1)

      refute BookingActions.can_change_booking?(
               booking(%{status: :complete, checkin_date: yesterday})
             )
    end
  end

  describe "refund_forfeited?/1" do
    test "is true only when a prior modification stamped refund_forfeited_at" do
      refute BookingActions.refund_forfeited?(
               booking(%{refund_forfeited_at: nil})
             )

      assert BookingActions.refund_forfeited?(
               booking(%{refund_forfeited_at: ~U[2026-10-01 12:00:00Z]})
             )
    end
  end
end
