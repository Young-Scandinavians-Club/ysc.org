defmodule YscWeb.BookingGuestFormTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.Booking
  alias Ysc.Bookings.BookingGuest
  alias YscWeb.BookingGuestForm

  describe "guest_info_required_for_modification?/2" do
    test "returns true when tahoe room booking guest count increases" do
      booking = %Booking{
        property: :tahoe,
        booking_mode: :room,
        guests_count: 2,
        children_count: 0
      }

      assert BookingGuestForm.guest_info_required_for_modification?(booking, %{
               guests_count: 3,
               children_count: 0
             })
    end

    test "returns true when children are added" do
      booking = %Booking{
        property: :tahoe,
        booking_mode: :room,
        guests_count: 2,
        children_count: 0
      }

      assert BookingGuestForm.guest_info_required_for_modification?(booking, %{
               guests_count: 2,
               children_count: 1
             })
    end

    test "returns false for buyout bookings" do
      booking = %Booking{
        property: :tahoe,
        booking_mode: :buyout,
        guests_count: 2,
        children_count: 0
      }

      refute BookingGuestForm.guest_info_required_for_modification?(booking, %{
               guests_count: 4,
               children_count: 0
             })
    end
  end

  describe "initialize_modification_guest_forms/4" do
    test "pre-fills existing guests and adds empty slots for new guests" do
      user = user_fixture()

      booking = %Booking{
        guests_count: 3,
        children_count: 1,
        booking_guests: [
          %BookingGuest{
            first_name: "Ada",
            last_name: "Member",
            is_child: false,
            is_booking_user: true,
            order_index: 0
          },
          %BookingGuest{
            first_name: "Bob",
            last_name: "Guest",
            is_child: false,
            is_booking_user: false,
            order_index: 1
          },
          %BookingGuest{
            first_name: "Cara",
            last_name: "Guest",
            is_child: false,
            is_booking_user: false,
            order_index: 2
          },
          %BookingGuest{
            first_name: "Dan",
            last_name: "Kid",
            is_child: true,
            is_booking_user: false,
            order_index: 3
          }
        ]
      }

      form =
        BookingGuestForm.initialize_modification_guest_forms(
          booking,
          user,
          4,
          2
        )

      assert map_size(form.source) == 6
      assert form.source["0"]["first_name"] == "Ada"
      assert form.source["1"]["first_name"] == "Bob"
      assert form.source["2"]["first_name"] == "Cara"
      assert form.source["3"]["first_name"] == ""
      assert form.source["3"]["is_child"] == false
      assert form.source["4"]["first_name"] == "Dan"
      assert form.source["4"]["is_child"] == true
      assert form.source["5"]["first_name"] == ""
      assert form.source["5"]["is_child"] == true
    end
  end
end
