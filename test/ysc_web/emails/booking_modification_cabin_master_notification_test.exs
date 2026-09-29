defmodule YscWeb.Emails.BookingModificationCabinMasterNotificationTest do
  use Ysc.DataCase, async: true

  import Ysc.BookingsFixtures

  alias Ysc.Repo
  alias YscWeb.Emails.BookingModificationCabinMasterNotification

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
        children_count: 0
      }

      data =
        BookingModificationCabinMasterNotification.prepare_email_data(
          booking,
          previous
        )

      assert data.dates_changed
      assert data.guests_changed
      assert data.booking.reference_id == booking.reference_id
      assert data.booking.property == "Tahoe"
      assert data.user.email == booking.user.email

      assert data.previous.checkin_date ==
               Calendar.strftime(previous_checkin, "%B %d, %Y")

      assert data.booking_url =~ "/admin/bookings/#{booking.id}"
    end

    test "no change flags when details are unchanged" do
      booking = booking_with_user()

      previous = %{
        checkin_date: booking.checkin_date,
        checkout_date: booking.checkout_date,
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0
      }

      data =
        BookingModificationCabinMasterNotification.prepare_email_data(
          booking,
          previous
        )

      refute data.dates_changed
      refute data.guests_changed
    end

    test "raises when booking is nil" do
      assert_raise ArgumentError, ~r/Booking cannot be nil/, fn ->
        Ysc.Test.Invoke.call(
          BookingModificationCabinMasterNotification,
          :prepare_email_data,
          [nil, %{}]
        )
      end
    end
  end

  describe "render/1" do
    test "includes what-changed section when dates changed" do
      booking = booking_with_user()

      previous = %{
        checkin_date: Date.add(booking.checkin_date, -3),
        checkout_date: Date.add(booking.checkout_date, -3),
        guests_count: booking.guests_count,
        children_count: 0
      }

      data =
        BookingModificationCabinMasterNotification.prepare_email_data(
          booking,
          previous
        )

      html = BookingModificationCabinMasterNotification.render(data)
      text = html |> LazyHTML.from_document() |> LazyHTML.text()

      assert text =~ "Booking Modification Notification"
      assert text =~ "What Changed"
      assert text =~ "Processed Automatically"
      assert text =~ booking.reference_id
    end
  end

  describe "metadata" do
    test "get_subject/0 and get_template_name/0" do
      assert BookingModificationCabinMasterNotification.get_subject() ==
               "Booking Modification Notification"

      assert BookingModificationCabinMasterNotification.get_template_name() ==
               "booking_modification_cabin_master_notification"
    end
  end
end
