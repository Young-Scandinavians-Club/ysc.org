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

    test "does nothing when hold has no guest params and counts are unchanged" do
      booking = %Booking{
        id: Ecto.ULID.generate(),
        guests_count: 2,
        children_count: 0,
        booking_guests: []
      }

      updated_booking = %{booking | guests_count: 2, children_count: 0}

      assert :ok =
               BookingGuestForm.sync_guests_after_modification_apply(
                 updated_booking,
                 %{},
                 booking
               )
    end

    test "accepts guest_params via opts even when hold_attrs has none" do
      user = user_fixture()

      {:ok, inserted} =
        %Booking{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :room,
          status: :complete,
          checkin_date: ~D[2026-08-01],
          checkout_date: ~D[2026-08-05],
          guests_count: 1,
          children_count: 0,
          reference_id: "TEST-#{System.unique_integer([:positive])}",
          total_price: Money.new(100, :USD)
        }
        |> Booking.changeset(%{}, skip_validation: true)
        |> Repo.insert()

      updated_booking = %{inserted | guests_count: 1, children_count: 0}

      guest_params = %{
        "0" => %{
          "first_name" => "Ada",
          "last_name" => "Member",
          "is_child" => false,
          "is_booking_user" => true,
          "order_index" => 0
        }
      }

      assert :ok =
               BookingGuestForm.sync_guests_after_modification_apply(
                 updated_booking,
                 %{},
                 inserted,
                 guest_params: guest_params
               )

      guests =
        Repo.all(from g in BookingGuest, where: g.booking_id == ^inserted.id)

      assert length(guests) == 1
      assert hd(guests).first_name == "Ada"
    end
  end

  describe "initialize_guest_forms/2" do
    test "builds a form with the booking user pre-filled and blank additional guests" do
      user = user_fixture()

      booking = %Booking{guests_count: 2, children_count: 1}

      form = BookingGuestForm.initialize_guest_forms(booking, user)

      assert map_size(form.source) == 3
      assert form.source["0"]["first_name"] == user.first_name
      assert form.source["0"]["is_booking_user"] == true
      assert form.source["1"]["first_name"] == ""
      assert form.source["1"]["is_child"] == false
      assert form.source["2"]["is_child"] == true
    end

    test "handles string guests_count/children_count and defaults" do
      user = user_fixture()

      booking = %Booking{guests_count: "3", children_count: "2"}
      form = BookingGuestForm.initialize_guest_forms(booking, user)
      assert map_size(form.source) == 5

      booking_defaults = %Booking{guests_count: nil, children_count: nil}
      form2 = BookingGuestForm.initialize_guest_forms(booking_defaults, user)
      # defaults to 1 guest, 0 children
      assert map_size(form2.source) == 1
    end

    test "handles a single guest with no additional adults" do
      user = user_fixture()
      booking = %Booking{guests_count: 1, children_count: 0}

      form = BookingGuestForm.initialize_guest_forms(booking, user)

      assert map_size(form.source) == 1
      assert form.source["0"]["is_booking_user"] == true
    end
  end

  describe "preview_booking/3" do
    test "returns a booking with updated counts" do
      booking = %Booking{guests_count: 1, children_count: 0}
      preview = BookingGuestForm.preview_booking(booking, 4, 2)

      assert preview.guests_count == 4
      assert preview.children_count == 2
    end
  end

  describe "merge_guest_params/4" do
    test "creates a default form when guest_info_form is nil" do
      result = BookingGuestForm.merge_guest_params(nil, %{}, %{}, [])

      assert result == %{}
    end

    test "merges submitted params over source data and normalizes fields" do
      guest_info_form =
        Phoenix.Component.to_form(
          %{
            "0" => %{
              "first_name" => "Old",
              "last_name" => "Name",
              "is_child" => false,
              "is_booking_user" => true,
              "order_index" => 0
            }
          },
          as: "guests"
        )

      guest_params = %{
        "0" => %{
          "first_name" => "New",
          "is_child" => "true",
          "is_booking_user" => "false",
          "order_index" => "5"
        }
      }

      merged =
        BookingGuestForm.merge_guest_params(guest_info_form, guest_params, %{}, [])

      assert merged["0"]["first_name"] == "New"
      assert merged["0"]["is_child"] == true
      assert merged["0"]["is_booking_user"] == false
      assert merged["0"]["order_index"] == 5
    end

    test "applies family member selections before merging" do
      other = user_fixture()

      guest_info_form =
        Phoenix.Component.to_form(
          %{
            "1" => %{
              "first_name" => "",
              "last_name" => "",
              "is_child" => false,
              "is_booking_user" => false,
              "order_index" => 1
            }
          },
          as: "guests"
        )

      guest_params = %{
        "1" => %{
          "first_name" => "",
          "last_name" => "",
          "is_child" => false,
          "is_booking_user" => false,
          "order_index" => 1
        }
      }

      merged =
        BookingGuestForm.merge_guest_params(
          guest_info_form,
          guest_params,
          %{"1" => other.id},
          [other]
        )

      assert merged["1"]["first_name"] == other.first_name
      assert merged["1"]["last_name"] == other.last_name
    end

    test "leaves guest data unchanged when the selected family member is not found" do
      guest_info_form =
        Phoenix.Component.to_form(
          %{
            "0" => %{
              "first_name" => "Kept",
              "last_name" => "Name",
              "is_child" => false,
              "is_booking_user" => false,
              "order_index" => 0
            }
          },
          as: "guests"
        )

      guest_params = %{
        "0" => %{
          "first_name" => "Kept",
          "last_name" => "Name",
          "is_child" => false,
          "is_booking_user" => false,
          "order_index" => 0
        }
      }

      merged =
        BookingGuestForm.merge_guest_params(
          guest_info_form,
          guest_params,
          %{"0" => "missing-id"},
          []
        )

      assert merged["0"]["first_name"] == "Kept"
    end

    test "leaves guest data unchanged when no family member is selected for that index" do
      guest_info_form =
        Phoenix.Component.to_form(
          %{
            "0" => %{
              "first_name" => "Same",
              "last_name" => "Name",
              "is_child" => false,
              "is_booking_user" => false,
              "order_index" => 0
            }
          },
          as: "guests"
        )

      guest_params = %{
        "0" => %{
          "first_name" => "Same",
          "last_name" => "Name",
          "is_child" => false,
          "is_booking_user" => false,
          "order_index" => 0
        }
      }

      merged =
        BookingGuestForm.merge_guest_params(guest_info_form, guest_params, nil, nil)

      assert merged["0"]["first_name"] == "Same"
    end
  end

  describe "validate_guest_params/2" do
    test "returns :ok with no errors when all guest changesets are valid" do
      booking = %Booking{id: Ecto.ULID.generate(), guests_count: 1, children_count: 0}

      guest_params = %{
        "0" => %{
          "first_name" => "Ada",
          "last_name" => "Member",
          "is_child" => false,
          "is_booking_user" => true,
          "order_index" => 0
        }
      }

      assert {:ok, _form, errors} =
               BookingGuestForm.validate_guest_params(booking, guest_params)

      assert errors == %{}
    end

    test "returns per-guest changeset errors when a guest is missing required fields" do
      booking = %Booking{id: Ecto.ULID.generate(), guests_count: 2, children_count: 0}

      guest_params = %{
        "0" => %{
          "first_name" => "Ada",
          "last_name" => "Member",
          "is_child" => false,
          "is_booking_user" => true,
          "order_index" => 0
        },
        "1" => %{
          "first_name" => "",
          "last_name" => "",
          "is_child" => false,
          "is_booking_user" => false,
          "order_index" => 1
        }
      }

      assert {:error, _form, errors} =
               BookingGuestForm.validate_guest_params(booking, guest_params)

      assert %{"1" => guest_errors} = errors
      assert guest_errors[:first_name]
      assert guest_errors[:last_name]
      refute Map.has_key?(errors, "0")
    end

    test "returns a general error when guest count does not match booking" do
      booking = %Booking{id: Ecto.ULID.generate(), guests_count: 2, children_count: 0}

      guest_params = %{
        "0" => %{
          "first_name" => "Ada",
          "last_name" => "Member",
          "is_child" => false,
          "is_booking_user" => true,
          "order_index" => 0
        }
      }

      assert {:error, _form, %{general: message}} =
               BookingGuestForm.validate_guest_params(booking, guest_params)

      assert message =~ "Expected 2 guests, got 1"
    end

    test "returns a general error when no guest is marked as the booking user" do
      booking = %Booking{id: Ecto.ULID.generate(), guests_count: 1, children_count: 0}

      guest_params = %{
        "0" => %{
          "first_name" => "Ada",
          "last_name" => "Member",
          "is_child" => false,
          "is_booking_user" => false,
          "order_index" => 0
        }
      }

      assert {:error, _form, %{general: message}} =
               BookingGuestForm.validate_guest_params(booking, guest_params)

      assert message == "Exactly one guest must be marked as the booking user"
    end

    test "returns a general error when the child count does not match" do
      booking = %Booking{id: Ecto.ULID.generate(), guests_count: 1, children_count: 1}

      guest_params = %{
        "0" => %{
          "first_name" => "Ada",
          "last_name" => "Member",
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
        }
      }

      assert {:error, _form, %{general: message}} =
               BookingGuestForm.validate_guest_params(booking, guest_params)

      assert message =~ "Expected 1 children, got 0"
    end
  end

  describe "all_guests_valid?/2" do
    test "returns false when the form is nil" do
      booking = %Booking{guests_count: 1, children_count: 0}
      refute BookingGuestForm.all_guests_valid?(nil, booking)
    end

    test "returns false when the guest count does not match the expected total" do
      booking = %Booking{guests_count: 2, children_count: 0}

      form =
        Phoenix.Component.to_form(
          %{"0" => %{"first_name" => "Ada", "last_name" => "Member"}},
          as: "guests"
        )

      refute BookingGuestForm.all_guests_valid?(form, booking)
    end

    test "returns false when a guest is missing a first or last name" do
      booking = %Booking{guests_count: 1, children_count: 0}

      form =
        Phoenix.Component.to_form(
          %{"0" => %{"first_name" => "  ", "last_name" => "Member"}},
          as: "guests"
        )

      refute BookingGuestForm.all_guests_valid?(form, booking)
    end

    test "returns true when every guest has a first and last name" do
      booking = %Booking{guests_count: 1, children_count: 1}

      form =
        Phoenix.Component.to_form(
          %{
            "0" => %{"first_name" => "Ada", "last_name" => "Member"},
            "1" => %{"first_name" => "Kid", "last_name" => "One"}
          },
          as: "guests"
        )

      assert BookingGuestForm.all_guests_valid?(form, booking)
    end
  end

  describe "save_guests/2" do
    test "replaces existing guests with new ones from valid params" do
      user = user_fixture()

      {:ok, inserted} =
        %Booking{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :room,
          status: :complete,
          checkin_date: ~D[2026-08-01],
          checkout_date: ~D[2026-08-05],
          guests_count: 1,
          children_count: 0,
          reference_id: "TEST-#{System.unique_integer([:positive])}",
          total_price: Money.new(100, :USD)
        }
        |> Booking.changeset(%{}, skip_validation: true)
        |> Repo.insert()

      guest_params = %{
        "0" => %{
          "first_name" => "Ada",
          "last_name" => "Member",
          "is_child" => false,
          "is_booking_user" => true,
          "order_index" => 0
        }
      }

      assert :ok = BookingGuestForm.save_guests(inserted, guest_params)

      guests = Repo.all(from g in BookingGuest, where: g.booking_id == ^inserted.id)
      assert length(guests) == 1
      assert hd(guests).first_name == "Ada"
    end

    test "returns an error tuple without persisting when params are invalid" do
      booking = %Booking{id: Ecto.ULID.generate(), guests_count: 1, children_count: 0}

      guest_params = %{
        "0" => %{
          "first_name" => "",
          "last_name" => "",
          "is_child" => false,
          "is_booking_user" => true,
          "order_index" => 0
        }
      }

      assert {:error, [%Ecto.Changeset{}]} =
               BookingGuestForm.save_guests(booking, guest_params)
    end
  end

  describe "trim_guests_to_counts/3" do
    test "deletes guests at or above the new total count" do
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

      assert :ok = BookingGuestForm.trim_guests_to_counts(inserted.id, 1, 0)

      guests = Repo.all(from g in BookingGuest, where: g.booking_id == ^inserted.id)
      assert length(guests) == 1
      assert hd(guests).first_name == "Ada"
    end
  end

  describe "select_guest_attendee/4" do
    test "creates a default form when guest_info_form is nil and selects 'other'" do
      {updated_form, selected_update} =
        BookingGuestForm.select_guest_attendee(nil, "0", "other", [])

      assert updated_form.source["0"]["first_name"] == ""
      assert selected_update == %{"0" => nil}
    end

    test "clears the guest row when 'other' is selected, preserving flags" do
      guest_info_form =
        Phoenix.Component.to_form(
          %{
            "1" => %{
              "first_name" => "Old",
              "last_name" => "Name",
              "is_child" => true,
              "is_booking_user" => false,
              "order_index" => 1
            }
          },
          as: "guests"
        )

      {updated_form, selected_update} =
        BookingGuestForm.select_guest_attendee(guest_info_form, "1", "other", [])

      assert updated_form.source["1"]["first_name"] == ""
      assert updated_form.source["1"]["is_child"] == true
      assert selected_update == %{"1" => nil}
    end

    test "fills the guest row with a selected family member" do
      user = user_fixture()
      other = user_fixture()

      guest_info_form =
        Phoenix.Component.to_form(
          %{
            "1" => %{
              "first_name" => "",
              "last_name" => "",
              "is_child" => false,
              "is_booking_user" => false,
              "order_index" => 1
            }
          },
          as: "guests"
        )

      {updated_form, selected_update} =
        BookingGuestForm.select_guest_attendee(
          guest_info_form,
          "1",
          "family_#{other.id}",
          [other, user]
        )

      assert updated_form.source["1"]["first_name"] == other.first_name
      assert updated_form.source["1"]["last_name"] == other.last_name
      assert selected_update == %{"1" => other.id}
    end

    test "leaves the form unchanged when the selected family member id is unknown" do
      guest_info_form =
        Phoenix.Component.to_form(
          %{
            "0" => %{
              "first_name" => "Same",
              "last_name" => "Name",
              "is_child" => false,
              "is_booking_user" => false,
              "order_index" => 0
            }
          },
          as: "guests"
        )

      {updated_form, selected_update} =
        BookingGuestForm.select_guest_attendee(
          guest_info_form,
          "0",
          "family_unknown-id",
          []
        )

      assert updated_form == guest_info_form
      assert selected_update == %{}
    end

    test "leaves the form unchanged for an unrecognized selected value" do
      guest_info_form =
        Phoenix.Component.to_form(%{}, as: "guests")

      {updated_form, selected_update} =
        BookingGuestForm.select_guest_attendee(guest_info_form, "0", nil, [])

      assert updated_form == guest_info_form
      assert selected_update == %{}
    end
  end

  describe "load_family_members/1" do
    test "returns family members excluding the given user" do
      user = user_fixture()

      {family_members, other_family_members} =
        BookingGuestForm.load_family_members(user)

      assert user in family_members
      refute user.id in Enum.map(other_family_members, & &1.id)
    end
  end
end
