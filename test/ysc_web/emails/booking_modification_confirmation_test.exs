defmodule YscWeb.Emails.BookingModificationConfirmationTest do
  use Ysc.DataCase, async: true

  import Ysc.BookingsFixtures

  alias Ysc.Repo
  alias YscWeb.Emails.BookingModificationConfirmation

  defp booking_with_user(attrs \\ %{}) do
    booking_fixture(attrs) |> Repo.preload(:user)
  end

  describe "prepare_email_data/2" do
    test "builds data with date and guest change flags" do
      booking = booking_with_user(%{guests_count: 4, children_count: 1})

      previous_checkin = Date.add(booking.checkin_date, -7)
      previous_checkout = Date.add(booking.checkout_date, -7)

      previous = %{
        checkin_date: previous_checkin,
        checkout_date: previous_checkout,
        guests_count: 2,
        children_count: 0,
        total_price: Money.new(150_00, :USD)
      }

      data =
        BookingModificationConfirmation.prepare_email_data(booking, previous)

      assert data.first_name == booking.user.first_name
      assert data.dates_changed
      assert data.guests_changed
      assert data.additional_payment == nil
      assert data.booking.reference_id == booking.reference_id
      assert data.booking.property == "Tahoe"

      assert data.previous.checkin_date ==
               Calendar.strftime(previous_checkin, "%B %d, %Y")

      assert data.booking_url =~ "/bookings/#{booking.id}/receipt"
    end

    test "omits additional_payment when zero or absent" do
      booking = booking_with_user()

      previous = %{
        checkin_date: booking.checkin_date,
        checkout_date: booking.checkout_date,
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0,
        total_price: booking.total_price
      }

      data =
        BookingModificationConfirmation.prepare_email_data(booking, previous)

      refute data.dates_changed
      refute data.guests_changed
      assert data.additional_payment == nil
    end

    test "raises when booking is nil" do
      assert_raise ArgumentError, ~r/Booking with user is required/, fn ->
        BookingModificationConfirmation.prepare_email_data(nil, %{})
      end
    end
  end

  describe "render/1" do
    test "includes refund policy warning and change summary when dates changed" do
      booking = booking_with_user()

      previous = %{
        checkin_date: Date.add(booking.checkin_date, -3),
        checkout_date: Date.add(booking.checkout_date, -3),
        guests_count: booking.guests_count,
        children_count: 0,
        total_price: booking.total_price
      }

      data =
        BookingModificationConfirmation.prepare_email_data(booking, previous)

      html = BookingModificationConfirmation.render(data)

      assert html =~ "Reservation Updated"
      assert html =~ "yellow-alert-box"
      assert html =~ "#FEF3C7"
      assert html =~ "#F59E0B"
      assert html =~ "cancellation refunds no longer apply"
      assert html =~ "What Changed"
      assert html =~ "View Updated Reservation"
    end
  end

  describe "metadata" do
    test "get_subject/0, get_template_name/0, and booking_url/1" do
      booking = booking_with_user()

      assert BookingModificationConfirmation.get_subject() ==
               "Your reservation has been updated"

      assert BookingModificationConfirmation.get_template_name() ==
               "booking_modification_confirmation"

      assert BookingModificationConfirmation.booking_url(booking.id) =~
               "/bookings/#{booking.id}/receipt"
    end
  end
end
