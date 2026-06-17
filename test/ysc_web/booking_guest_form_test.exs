defmodule YscWeb.BookingGuestFormTest do
  use Ysc.DataCase, async: true

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Bookings.Booking
  alias Ysc.Bookings.BookingGuest
  alias Ysc.Repo
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

  describe "sync_guests_after_modification_apply/4" do
    test "saves guests from hold attrs after modification apply" do
      user = user_fixture()

      booking =
        %Booking{
          id: Ecto.ULID.generate(),
          guests_count: 2,
          children_count: 0,
          booking_guests: []
        }

      updated_booking = %{booking | guests_count: 3, children_count: 0}

      hold_attrs = %{
        "guest_params" => %{
          "0" => %{
            "first_name" => user.first_name || "Ada",
            "last_name" => user.last_name || "Member",
            "is_child" => false,
            "is_booking_user" => true,
            "order_index" => 0
          },
          "1" => %{
            "first_name" => "Bob",
            "last_name" => "Guest",
            "is_child" => false,
            "is_booking_user" => false,
            "order_index" => 1
          },
          "2" => %{
            "first_name" => "Cara",
            "last_name" => "Guest",
            "is_child" => false,
            "is_booking_user" => false,
            "order_index" => 2
          }
        }
      }

      {:ok, inserted} =
        %Booking{
          id: booking.id,
          user_id: user.id,
          property: :tahoe,
          booking_mode: :room,
          status: :complete,
          checkin_date: ~D[2026-08-01],
          checkout_date: ~D[2026-08-05],
          guests_count: 2,
          children_count: 0,
          reference_id: "TEST-#{System.unique_integer([:positive])}",
          total_price: Money.new(100, :USD)
        }
        |> Booking.changeset(%{}, skip_validation: true)
        |> Repo.insert()

      assert :ok =
               BookingGuestForm.sync_guests_after_modification_apply(
                 %{updated_booking | id: inserted.id},
                 hold_attrs,
                 inserted
               )

      guests =
        Ysc.Repo.all(
          from g in BookingGuest,
            where: g.booking_id == ^inserted.id,
            order_by: g.order_index
        )

      assert length(guests) == 3
      assert Enum.at(guests, 2).first_name == "Cara"
    end

    test "trims excess guests when modification decreases counts without hold guest params" do
      user = user_fixture()

      {:ok, inserted} =
        %Booking{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :room,
          status: :complete,
          checkin_date: ~D[2026-08-01],
          checkout_date: ~D[2026-08-05],
          guests_count: 3,
          children_count: 0,
          reference_id: "TEST-#{System.unique_integer([:positive])}",
          total_price: Money.new(100, :USD)
        }
        |> Booking.changeset(%{}, skip_validation: true)
        |> Repo.insert()

      for {first_name, order_index} <- [{"Ada", 0}, {"Bob", 1}, {"Cara", 2}] do
        %BookingGuest{}
        |> BookingGuest.changeset(%{
          booking_id: inserted.id,
          first_name: first_name,
          last_name: "Guest",
          is_child: false,
          is_booking_user: order_index == 0,
          order_index: order_index
        })
        |> Repo.insert!()
      end

      original_booking = Repo.preload(inserted, :booking_guests)
      updated_booking = %{original_booking | guests_count: 2}

      assert :ok =
               BookingGuestForm.sync_guests_after_modification_apply(
                 updated_booking,
                 %{},
                 original_booking
               )

      guests =
        Repo.all(
          from g in BookingGuest,
            where: g.booking_id == ^inserted.id,
            order_by: g.order_index
        )

      assert length(guests) == 2
      assert Enum.map(guests, & &1.first_name) == ["Ada", "Bob"]
    end
  end
end
