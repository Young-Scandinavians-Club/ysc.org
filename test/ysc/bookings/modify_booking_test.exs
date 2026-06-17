defmodule Ysc.Bookings.ModifyBookingTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker, PendingRefund, RoomCategory}
  alias Ysc.Ledgers
  alias Ysc.Repo
  import Ecto.Query

  setup do
    Ledgers.ensure_basic_accounts()

    user =
      user_fixture()
      |> Ecto.Changeset.change(state: :active)
      |> Repo.update!()

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(500, :USD),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe,
        season_id: nil
      })

    %{user: user}
  end

  defp complete_buyout_booking!(user, checkin, checkout) do
    assert {:ok, total, _} =
             Bookings.calculate_booking_price(
               :tahoe,
               checkin,
               checkout,
               :buyout,
               guests_count: 4
             )

    assert {:ok, %Booking{} = booking} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: user.id,
                 property: :tahoe,
                 checkin_date: checkin,
                 checkout_date: checkout,
                 booking_mode: :buyout,
                 guests_count: 4,
                 total_price: total
               },
               skip_email: true,
               skip_reminders: true
             )

    assert {:ok, {_payment, _, _}} =
             Ledgers.process_payment(%{
               user_id: user.id,
               amount: total,
               entity_type: :booking,
               entity_id: booking.id,
               external_payment_id:
                 "pi_modify_#{System.unique_integer([:positive])}",
               stripe_fee: Money.new(100, :USD),
               description: "Booking payment",
               property: booking.property,
               payment_method_id: nil
             })

    Repo.preload(booking, [:rooms, :user])
  end

  defp complete_room_booking!(user, room, checkin, checkout) do
    assert {:ok, total, _} =
             Bookings.calculate_booking_price(
               :tahoe,
               checkin,
               checkout,
               :room,
               room_id: room.id,
               guests_count: 2
             )

    assert {:ok, %Booking{} = booking} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: user.id,
                 property: :tahoe,
                 checkin_date: checkin,
                 checkout_date: checkout,
                 booking_mode: :room,
                 guests_count: 2,
                 total_price: total
               },
               rooms: [room],
               skip_email: true,
               skip_reminders: true
             )

    assert {:ok, _} =
             Ledgers.process_payment(%{
               user_id: user.id,
               amount: total,
               entity_type: :booking,
               entity_id: booking.id,
               external_payment_id:
                 "pi_modify_room_#{System.unique_integer([:positive])}",
               stripe_fee: Money.new(100, :USD),
               description: "Booking payment",
               property: booking.property,
               payment_method_id: nil
             })

    Repo.preload(booking, [:rooms, :user])
  end

  defp create_test_room! do
    {:ok, category} =
      %RoomCategory{}
      |> RoomCategory.changeset(%{name: "Modify test category"})
      |> Repo.insert()

    {:ok, room} =
      Bookings.create_room(%{
        name: "Modify test room #{System.unique_integer([:positive])}",
        property: :tahoe,
        room_category_id: category.id,
        capacity_max: 4
      })

    room
  end

  describe "modification_hold_form_params/1" do
    test "normalizes atom-key attrs with Date structs" do
      attrs = %{
        checkin_date: ~D[2026-07-01],
        checkout_date: ~D[2026-07-04],
        guests_count: 4,
        children_count: 0
      }

      assert %{
               "checkin_date" => "2026-07-01",
               "checkout_date" => "2026-07-04",
               "guests_count" => "4",
               "children_count" => "0"
             } = Bookings.modification_hold_form_params(attrs)
    end
  end

  describe "modify_complete_booking/3" do
    test "updates dates, sets refund_forfeited_at, and schedules modification email",
         %{
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(30)
      new_checkin = Date.add(checkin, 7)
      new_checkout = Date.add(checkout, 7)

      booking = complete_buyout_booking!(user, checkin, checkout)
      assert is_nil(booking.refund_forfeited_at)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, updated} =
                 BookingLocker.modify_complete_booking(booking, %{
                   checkin_date: new_checkin,
                   checkout_date: new_checkout,
                   guests_count: 4,
                   children_count: 0
                 })

        assert updated.checkin_date == new_checkin
        assert updated.checkout_date == new_checkout
        assert updated.refund_forfeited_at

        {:ok, priced} = Bookings.calculate_modification_pricing(updated)
        assert Money.equal?(updated.subtotal_price, priced.subtotal)
        assert Money.equal?(updated.total_price, priced.total)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "booking_modification_confirmation"}
        )
      end)
    end

    test "calculate_refund returns zero after modification", %{user: user} do
      {checkin, checkout} = tahoe_booking_dates(40)
      booking = complete_buyout_booking!(user, checkin, checkout)

      assert is_nil(booking.refund_forfeited_at)

      {:ok, before_refund, _} =
        Bookings.calculate_refund(booking, Date.utc_today())

      case before_refund do
        nil -> :ok
        %Money{} = amount -> refute Money.equal?(amount, Money.new(0, :USD))
      end

      assert {:ok, updated} =
               BookingLocker.modify_complete_booking(booking, %{
                 checkin_date: Date.add(checkin, 7),
                 checkout_date: Date.add(checkout, 7),
                 guests_count: 5,
                 children_count: 0
               })

      assert updated.refund_forfeited_at

      assert {:ok, refund, nil} =
               Bookings.calculate_refund(updated, Date.utc_today())

      assert Money.equal?(refund, Money.new(0, :USD))
    end

    test "user can cancel modified booking with no refund and no pending refund",
         %{
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(50)
      booking = complete_buyout_booking!(user, checkin, checkout)

      assert {:ok, modified} =
               BookingLocker.modify_complete_booking(booking, %{
                 checkin_date: Date.add(checkin, 7),
                 checkout_date: Date.add(checkout, 7),
                 guests_count: 4,
                 children_count: 0
               })

      assert {:ok, canceled, refund_amount, _result} =
               Bookings.cancel_booking(
                 modified,
                 Date.utc_today(),
                 "Changed plans"
               )

      assert canceled.status == :canceled
      assert Money.equal?(refund_amount, Money.new(0, :USD))

      refute Repo.exists?(
               from pr in PendingRefund, where: pr.booking_id == ^canceled.id
             )
    end
  end

  describe "prepare_modification/2" do
    test "returns preview with zero delta when price unchanged", %{user: user} do
      {checkin, checkout} = tahoe_booking_dates(60)
      booking = complete_buyout_booking!(user, checkin, checkout)

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(Date.add(checkin, 7)),
                 "checkout_date" => Date.to_string(Date.add(checkout, 7)),
                 "guests_count" => "4",
                 "children_count" => "0"
               })

      assert preview.new_total
      assert preview.amount_paid
      assert Money.equal?(preview.delta, Money.new(0, :USD))
    end

    test "accepts ISO8601 datetime strings from date picker params", %{
      user: user
    } do
      {checkin, checkout} = tahoe_booking_dates(65)
      booking = complete_buyout_booking!(user, checkin, checkout)
      new_checkin = Date.add(checkin, 7)
      new_checkout = Date.add(checkout, 7)

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_iso8601(new_checkin) <> "T00:00:00Z",
                 "checkout_date" =>
                   Date.to_iso8601(new_checkout) <> "T00:00:00Z",
                 "guests_count" => "4",
                 "children_count" => "0"
               })

      assert preview.new_total
    end

    test "returns delta as new total minus previous reservation total, not full new total",
         %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      room = create_test_room!()
      {checkin, checkout} = tahoe_booking_dates(100)
      short_checkout = Date.add(checkin, 1)

      booking = complete_room_booking!(user, room, checkin, short_checkout)

      assert Money.equal?(booking.total_price, Money.new(200, :USD))

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(checkin),
                 "checkout_date" => Date.to_string(checkout),
                 "guests_count" => "2",
                 "children_count" => "0"
               })

      assert Money.equal?(preview.previous_total, Money.new(200, :USD))
      refute Money.equal?(preview.delta, preview.new_total)
    end

    test "returns error when nothing changed", %{user: user} do
      {checkin, checkout} = tahoe_booking_dates(70)
      booking = complete_buyout_booking!(user, checkin, checkout)

      assert {:error, :no_changes} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(checkin),
                 "checkout_date" => Date.to_string(checkout),
                 "guests_count" => "4",
                 "children_count" => "0"
               })
    end

    test "returns error when modification would checkout on Saturday without Sunday",
         %{user: user} do
      {checkin, checkout} = tahoe_booking_dates(80)
      booking = complete_buyout_booking!(user, checkin, checkout)

      # Friday check-in, Saturday checkout — Saturday in range but not Sunday
      friday = first_friday_on_or_after(Date.add(checkin, 14))
      saturday = Date.add(friday, 1)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(friday),
                 "checkout_date" => Date.to_string(saturday),
                 "guests_count" => "4",
                 "children_count" => "0"
               })

      refute changeset.valid?

      assert [message] = errors_on(changeset).checkout_date
      assert message =~ "full weekend required"
    end

    test "returns error when modified dates overlap another room booking", %{
      user: user
    } do
      other_user =
        user_fixture()
        |> Ecto.Changeset.change(state: :active)
        |> Repo.update!()

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      room = create_test_room!()
      {checkin, checkout} = tahoe_booking_dates(90)

      booking = complete_room_booking!(user, room, checkin, checkout)

      # Overlapping booking on the same room starting the day before checkout
      _other_booking =
        complete_room_booking!(
          other_user,
          room,
          Date.add(checkin, 1),
          Date.add(checkout, 2)
        )

      extended_checkout = Date.add(checkout, 1)

      assert {:error, :room_unavailable} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(checkin),
                 "checkout_date" => Date.to_string(extended_checkout),
                 "guests_count" => "2",
                 "children_count" => "0"
               })
    end

    test "returns error when check-in date is in the past", %{user: user} do
      {checkin, checkout} = tahoe_booking_dates(95)
      booking = complete_buyout_booking!(user, checkin, checkout)
      past_checkin = Date.add(YscWeb.BookingActions.get_today_pst(), -1)

      assert {:error, :checkin_in_past} =
               Bookings.prepare_modification(booking, %{
                 "checkin_date" => Date.to_string(past_checkin),
                 "checkout_date" => Date.to_string(checkout),
                 "guests_count" => "4",
                 "children_count" => "0"
               })
    end
  end

  describe "modification holds" do
    test "apply_modification with payment uses hold attrs when submitted params differ",
         %{
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(117)
      extended_checkout = Date.add(checkout, 1)
      booking = complete_buyout_booking!(user, checkin, checkout)

      hold_attrs = %{
        checkin_date: checkin,
        checkout_date: extended_checkout,
        guests_count: 4,
        children_count: 0
      }

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, hold_attrs)

      assert {:ok, preview} =
               Bookings.prepare_modification(held_booking, %{
                 "checkin_date" => Date.to_string(checkin),
                 "checkout_date" => Date.to_string(extended_checkout),
                 "guests_count" => "4",
                 "children_count" => "0"
               })

      payment_intent_id =
        "pi_apply_hold_attrs_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => to_string(booking.id),
             "user_id" => to_string(user.id),
             "modification" => "true"
           },
           latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
         }}
      end)

      wrong_attrs = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests_count" => "4",
        "children_count" => "0"
      }

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:ok, updated} =
                 Bookings.apply_modification(held_booking, wrong_attrs,
                   payment_intent_id: payment_intent_id
                 )

        assert updated.checkout_date == extended_checkout
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "apply_modification after payment skips availability blocked by own hold flags",
         %{
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(118)
      extended_checkout = Date.add(checkout, 1)
      booking = complete_buyout_booking!(user, checkin, checkout)

      string_attrs = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(extended_checkout),
        "guests_count" => "4",
        "children_count" => "0"
      }

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, string_attrs)

      assert Money.positive?(preview.delta)

      hold_attrs = %{
        checkin_date: checkin,
        checkout_date: extended_checkout,
        guests_count: 4,
        children_count: 0
      }

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, hold_attrs)

      payment_intent_id =
        "pi_apply_skip_avail_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => to_string(booking.id),
             "user_id" => to_string(user.id),
             "modification" => "true"
           },
           latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
         }}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:ok, updated} =
                 Bookings.apply_modification(held_booking, string_attrs,
                   payment_intent_id: payment_intent_id
                 )

        assert updated.checkout_date == extended_checkout
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "validate_modification_dates honors active modification hold on stale snapshot",
         %{
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(115)
      extended_checkout = Date.add(checkout, 1)
      booking = complete_buyout_booking!(user, checkin, checkout)

      hold_attrs = %{
        checkin_date: checkin,
        checkout_date: extended_checkout,
        guests_count: 4,
        children_count: 0
      }

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, hold_attrs)

      calendar =
        Ysc.Bookings.ModificationDateAvailability.calendar_context(held_booking)

      snapshot =
        Ysc.Bookings.ModificationDateAvailability.build_availability_snapshot(
          held_booking,
          calendar.min_date,
          calendar.max_date,
          calendar.today,
          calendar.seasons
        )

      stale_snapshot = %{snapshot | hold: %{active: false}}

      assert :ok =
               Ysc.Bookings.ModificationDateAvailability.validate_modification_dates(
                 stale_snapshot,
                 hold_attrs.checkin_date,
                 hold_attrs.checkout_date
               )
    end

    test "place_modification_hold persists guest_params in modification_hold_attrs",
         %{
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(110)
      booking = complete_buyout_booking!(user, checkin, checkout)

      guest_params = %{
        "0" => %{
          "first_name" => "Primary",
          "last_name" => "Guest",
          "is_child" => false,
          "is_booking_user" => true,
          "order_index" => 0
        },
        "1" => %{
          "first_name" => "Extra",
          "last_name" => "Guest",
          "is_child" => false,
          "is_booking_user" => false,
          "order_index" => 1
        }
      }

      attrs = %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 4,
        children_count: 0
      }

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, attrs,
                 guest_params: guest_params
               )

      assert held_booking.modification_hold_attrs["guest_params"] ==
               guest_params
    end

    test "place_modification_hold reserves newly added calendar days", %{
      user: user
    } do
      {checkin, checkout} = tahoe_booking_dates(110)
      extended_checkout = Date.add(checkout, 2)
      booking = complete_buyout_booking!(user, checkin, checkout)

      attrs = %{
        checkin_date: checkin,
        checkout_date: extended_checkout,
        guests_count: 4,
        children_count: 0
      }

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, attrs)

      assert held_booking.modification_hold_expires_at
      assert held_booking.modification_hold_attrs

      new_days =
        checkout
        |> Date.range(Date.add(extended_checkout, -1))
        |> Enum.to_list()

      for day <- new_days do
        pi =
          Repo.get_by!(Ysc.Bookings.PropertyInventory,
            property: :tahoe,
            day: day
          )

        assert pi.buyout_held
      end

      assert {:ok, released} = Bookings.release_modification_hold(booking.id)
      assert is_nil(released.modification_hold_attrs)

      for day <- new_days do
        pi =
          Repo.get_by!(Ysc.Bookings.PropertyInventory,
            property: :tahoe,
            day: day
          )

        refute pi.buyout_held
      end
    end

    test "apply_modification with payment requires a succeeded payment intent",
         %{
           user: user
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      room = create_test_room!()
      {checkin, checkout} = tahoe_booking_dates(120)
      short_checkout = Date.add(checkin, 1)
      booking = complete_room_booking!(user, room, checkin, short_checkout)

      attrs = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests_count" => "2",
        "children_count" => "0"
      }

      assert {:ok, preview} = Bookings.prepare_modification(booking, attrs)
      assert Money.positive?(preview.delta)

      assert {:error, :payment_not_succeeded} =
               Bookings.apply_modification(booking, attrs,
                 payment_intent_id: "pi_missing_hold"
               )
    end

    test "apply_modification rejects modification payment with wrong delta amount",
         %{
           user: user
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      room = create_test_room!()
      {checkin, checkout} = tahoe_booking_dates(121)
      short_checkout = Date.add(checkin, 1)
      booking = complete_room_booking!(user, room, checkin, short_checkout)

      attrs = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests_count" => "2",
        "children_count" => "0"
      }

      assert {:ok, preview} = Bookings.prepare_modification(booking, attrs)
      assert Money.positive?(preview.delta)

      payment_intent_id =
        "pi_mod_underpaid_#{System.unique_integer([:positive])}"

      underpaid_cents = Ysc.MoneyHelper.money_to_cents(preview.delta) - 100

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: underpaid_cents,
           metadata: %{
             "booking_id" => to_string(booking.id),
             "user_id" => to_string(user.id),
             "modification" => "true"
           },
           latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
         }}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:error, :payment_amount_mismatch} =
                 Bookings.apply_modification(booking, attrs,
                   payment_intent_id: payment_intent_id
                 )
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "apply_modification rejects checkout payment intents missing modification metadata",
         %{
           user: user
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      room = create_test_room!()
      {checkin, checkout} = tahoe_booking_dates(122)
      short_checkout = Date.add(checkin, 1)
      booking = complete_room_booking!(user, room, checkin, short_checkout)

      attrs = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests_count" => "2",
        "children_count" => "0"
      }

      assert {:ok, preview} = Bookings.prepare_modification(booking, attrs)
      assert Money.positive?(preview.delta)

      payment_intent_id =
        "pi_mod_missing_flag_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => to_string(booking.id),
             "user_id" => to_string(user.id)
           },
           latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
         }}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:error, :payment_metadata_mismatch} =
                 Bookings.apply_modification(booking, attrs,
                   payment_intent_id: payment_intent_id
                 )
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "apply_modification refreshes an expired hold after payment succeeds",
         %{
           user: user
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      room = create_test_room!()
      {checkin, checkout} = tahoe_booking_dates(125)
      short_checkout = Date.add(checkin, 1)
      booking = complete_room_booking!(user, room, checkin, short_checkout)

      attrs = %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 2,
        children_count: 0
      }

      string_attrs = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests_count" => "2",
        "children_count" => "0"
      }

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, string_attrs)

      assert Money.positive?(preview.delta)

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, attrs)

      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-1, :minute)
        |> DateTime.truncate(:second)

      held_booking
      |> Ecto.Changeset.change(modification_hold_expires_at: expired_at)
      |> Repo.update!()

      payment_intent_id =
        "pi_mod_hold_refresh_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => to_string(booking.id),
             "user_id" => to_string(user.id),
             "modification" => "true"
           },
           latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
         }}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:ok, updated} =
                 Bookings.apply_modification(booking, string_attrs,
                   payment_intent_id: payment_intent_id
                 )

        assert updated.checkout_date == checkout
        refute updated.modification_hold_expires_at
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "apply_modification returns error when expired hold cannot be refreshed",
         %{
           user: user
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      room = create_test_room!()
      {checkin, checkout} = tahoe_booking_dates(126)
      short_checkout = Date.add(checkin, 1)
      booking = complete_room_booking!(user, room, checkin, short_checkout)

      attrs = %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 2,
        children_count: 0
      }

      string_attrs = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests_count" => "2",
        "children_count" => "0"
      }

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, string_attrs)

      assert Money.positive?(preview.delta)

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, attrs)

      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-1, :minute)
        |> DateTime.truncate(:second)

      held_booking
      |> Ecto.Changeset.change(modification_hold_expires_at: expired_at)
      |> Repo.update!()

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :tahoe,
                 reason: "Blocks modification refresh",
                 start_date: checkin,
                 end_date: checkout
               })

      payment_intent_id =
        "pi_mod_hold_blocked_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => to_string(booking.id),
             "user_id" => to_string(user.id),
             "modification" => "true"
           },
           latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
         }}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:error, :blackout_conflict} =
                 Bookings.apply_modification(booking, string_attrs,
                   payment_intent_id: payment_intent_id
                 )
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end
  end

  describe "modification ledger recovery" do
    test "ensure_modification_ledger_recorded records missing payment after applied modification",
         %{
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(119)
      extended_checkout = Date.add(checkout, 1)
      booking = complete_buyout_booking!(user, checkin, checkout)

      string_attrs = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(extended_checkout),
        "guests_count" => "4",
        "children_count" => "0"
      }

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, string_attrs)

      assert Money.positive?(preview.delta)

      hold_attrs = %{
        checkin_date: checkin,
        checkout_date: extended_checkout,
        guests_count: 4,
        children_count: 0
      }

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, hold_attrs)

      payment_intent_id =
        "pi_ledger_recovery_#{System.unique_integer([:positive])}"

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:ok, updated} =
                 BookingLocker.modify_complete_booking(
                   held_booking,
                   hold_attrs,
                   previous_details: %{
                     checkin_date: booking.checkin_date,
                     checkout_date: booking.checkout_date,
                     guests_count: booking.guests_count,
                     children_count: booking.children_count || 0,
                     total_price: booking.total_price
                   }
                 )

        assert updated.checkout_date == extended_checkout
        assert is_nil(Ledgers.get_payment_by_external_id(payment_intent_id))

        {:ok, balance_due} = Money.sub(updated.total_price, booking.total_price)
        amount_cents = Ysc.MoneyHelper.money_to_cents(balance_due)
        assert amount_cents == Ysc.MoneyHelper.money_to_cents(preview.delta)

        stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
          {:ok,
           %Stripe.PaymentIntent{
             id: payment_intent_id,
             status: "succeeded",
             amount: amount_cents,
             metadata: %{
               "booking_id" => to_string(booking.id),
               "user_id" => to_string(user.id),
               "modification" => "true"
             },
             latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
           }}
        end)

        assert :ok =
                 Bookings.ensure_modification_ledger_recorded(
                   updated,
                   payment_intent_id
                 )

        assert Ledgers.get_payment_by_external_id(payment_intent_id)
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "ensure_modification_ledger_recorded is idempotent when ledger already recorded",
         %{
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(121)
      extended_checkout = Date.add(checkout, 1)
      booking = complete_buyout_booking!(user, checkin, checkout)

      string_attrs = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(extended_checkout),
        "guests_count" => "4",
        "children_count" => "0"
      }

      assert {:ok, preview} =
               Bookings.prepare_modification(booking, string_attrs)

      assert {:ok, held_booking} =
               Bookings.place_modification_hold(booking, %{
                 checkin_date: checkin,
                 checkout_date: extended_checkout,
                 guests_count: 4,
                 children_count: 0
               })

      payment_intent_id =
        "pi_ledger_idempotent_#{System.unique_integer([:positive])}"

      amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => to_string(booking.id),
             "user_id" => to_string(user.id),
             "modification" => "true"
           },
           latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
         }}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:ok, updated} =
                 Bookings.apply_modification(held_booking, string_attrs,
                   payment_intent_id: payment_intent_id
                 )

        assert :ok =
                 Bookings.ensure_modification_ledger_recorded(
                   updated,
                   payment_intent_id
                 )
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "ensure_modification_ledger_recorded rejects when modification was not applied",
         %{
           user: user
         } do
      {checkin, checkout} = tahoe_booking_dates(120)
      booking = complete_buyout_booking!(user, checkin, checkout)

      payment_intent_id =
        "pi_ledger_no_mod_#{System.unique_integer([:positive])}"

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: 5_000,
           metadata: %{
             "booking_id" => to_string(booking.id),
             "user_id" => to_string(user.id),
             "modification" => "true"
           },
           latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"}
         }}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:error, :modification_not_applied} =
                 Bookings.ensure_modification_ledger_recorded(
                   booking,
                   payment_intent_id
                 )
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end
  end

  defp first_friday_on_or_after(date) do
    days_until_friday = rem(5 - Date.day_of_week(date, :monday) + 7, 7)
    Date.add(date, days_until_friday)
  end
end
