defmodule YscWeb.Sms.BookingCheckinReminderTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Repo
  alias YscWeb.Sms.BookingCheckinReminder

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "get_template_name/0" do
    test "returns the SMS template name" do
      assert BookingCheckinReminder.get_template_name() ==
               "booking_checkin_reminder"
    end
  end

  describe "render/1" do
    test "uses defaults when keys are missing" do
      body = BookingCheckinReminder.render(%{})
      assert body =~ "[YSC]"
      assert body =~ "Valued Member"
      assert body =~ "Property"
      assert body =~ "Not Available"
      assert body =~ "3:00 PM"
    end

    test "interpolates provided variables and normalizes whitespace" do
      body =
        BookingCheckinReminder.render(%{
          first_name: "Astrid",
          property_name: "Tahoe",
          checkin_date: "May 01, 2026",
          door_code: "1234",
          checkin_time: "4:00 PM"
        })

      assert body =~ "Astrid"
      assert body =~ "Tahoe"
      assert body =~ "May 01, 2026"
      assert body =~ "1234"
      assert body =~ "4:00 PM"
      refute body =~ "\n\n"
    end
  end

  describe "prepare_sms_data/1" do
    test "raises when booking is nil" do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        Ysc.Test.Invoke.call(BookingCheckinReminder, :prepare_sms_data, [nil])
      end
    end

    test "raises when booking has no id" do
      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(BookingCheckinReminder, :prepare_sms_data, [
          %Ysc.Bookings.Booking{}
        ])
      end
    end

    test "builds data for a preloaded booking" do
      user = user_fixture(%{first_name: "Bjorn"})

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :tahoe
        })

      booking = Repo.preload(booking, :user)

      data = BookingCheckinReminder.prepare_sms_data(booking)

      assert data.first_name == "Bjorn"
      assert data.property_name == "Tahoe"
      assert data.checkin_time == "3:00 PM"
      assert is_binary(data.checkin_date)

      assert data.door_code == "Not Available" or is_binary(data.door_code)
    end

    test "uses Clear Lake property label" do
      user = user_fixture()

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :complete,
          property: :clear_lake
        })

      booking = Repo.preload(booking, :user)

      data = BookingCheckinReminder.prepare_sms_data(booking)
      assert data.property_name == "Clear Lake"
    end
  end
end
