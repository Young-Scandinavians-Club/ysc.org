defmodule YscWeb.Emails.HelpersBookingTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings.Booking
  alias Ysc.Repo
  alias YscWeb.Emails.Helpers

  describe "ensure_booking/2" do
    test "returns the booking unchanged when associations are already loaded" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id}) |> Repo.preload([:user])

      assert Helpers.ensure_booking(booking) == booking
    end

    test "loads user when it is not loaded" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})
      refute Ecto.assoc_loaded?(booking.user)

      loaded = Helpers.ensure_booking(booking)

      assert Ecto.assoc_loaded?(loaded.user)
      assert loaded.user.id == user.id
    end

    test "loads rooms when requested" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})
      refute Ecto.assoc_loaded?(booking.rooms)

      loaded = Helpers.ensure_booking(booking, [:user, :rooms])

      assert Ecto.assoc_loaded?(loaded.user)
      assert Ecto.assoc_loaded?(loaded.rooms)
    end

    test "raises when booking is nil" do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        Ysc.Test.Invoke.call(Helpers, :ensure_booking, [nil])
      end
    end

    test "raises when booking is missing an id" do
      assert_raise ArgumentError, ~r/Booking missing id/, fn ->
        Helpers.ensure_booking(%Booking{})
      end
    end

    test "raises when the booking row no longer exists" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})
      Repo.delete!(booking)

      assert_raise ArgumentError, "Booking not found: #{booking.id}", fn ->
        Helpers.ensure_booking(booking)
      end
    end
  end
end
