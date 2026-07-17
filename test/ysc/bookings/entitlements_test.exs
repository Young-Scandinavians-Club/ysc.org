defmodule Ysc.Bookings.EntitlementsTest do
  use Ysc.DataCase, async: false

  alias Money
  alias Ysc.Bookings
  alias Ysc.Bookings.{BookingLocker, Entitlements}
  alias Ysc.Repo
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    stub(Stripe.PaymentIntentMock, :list, fn _params ->
      {:ok,
       %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         url: "/v1/payment_intents"
       }}
    end)

    %{user: user_fixture(), admin: user_fixture()}
  end

  describe "lock_entitlement_for_consume/1 and consume_for_booking!/2" do
    test "serializes concurrent consume so only one booking can consume the entitlement",
         %{user: user, admin: admin} do
      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Ent lock category #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      assert {:ok, _} =
               Bookings.create_pricing_rule(%{
                 amount: Money.new(:USD, 100),
                 booking_mode: :room,
                 price_unit: :per_person_per_night,
                 property: :tahoe,
                 season_id: nil,
                 room_id: nil,
                 room_category_id: category.id
               })

      {:ok, room_a} =
        Bookings.create_room(%{
          name: "Ent lock room A",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {:ok, room_b} =
        Bookings.create_room(%{
          name: "Ent lock room B",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      assert {:ok, entitlement} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 25)
                 },
                 send_notification: false
               )

      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

      assert {:ok, booking_a} =
               BookingLocker.create_room_booking(
                 user.id,
                 room_a.id,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, booking_b} =
               BookingLocker.create_room_booking(
                 user.id,
                 room_b.id,
                 checkin,
                 checkout,
                 2
               )

      assert entitlement.id == booking_a.applied_booking_entitlement_id
      refute booking_b.applied_booking_entitlement_id

      assert {:ok, _} = BookingLocker.release_hold(booking_b.id)

      booking_b =
        booking_b
        |> Ecto.Changeset.change(%{
          applied_booking_entitlement_id: entitlement.id
        })
        |> Repo.update!()

      owner = self()

      task_a =
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)

          Repo.transaction(fn ->
            Entitlements.lock_entitlement_for_consume(entitlement.id)
            send(owner, {:entitlement_lock_held, self()})

            receive do
              :consume_entitlement -> :ok
            end

            case Entitlements.consume_for_booking!(entitlement.id, booking_a.id) do
              :ok -> :a_won
              {:error, reason} -> Repo.rollback({:consume_failed, reason})
            end
          end)
        end)

      assert_receive {:entitlement_lock_held, a_pid}, 5_000

      task_b =
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)

          Repo.transaction(fn ->
            Entitlements.lock_entitlement_for_consume(entitlement.id)

            case Entitlements.consume_for_booking!(entitlement.id, booking_b.id) do
              :ok -> :b_won
              {:error, reason} -> Repo.rollback({:consume_failed, reason})
            end
          end)
        end)

      assert Task.yield(task_b, 500) == nil

      send(a_pid, :consume_entitlement)

      results = [Task.await(task_a, 5_000), Task.await(task_b, 5_000)]

      wins =
        Enum.count(results, fn
          {:ok, :a_won} -> true
          {:ok, :b_won} -> true
          _ -> false
        end)

      fails =
        Enum.count(results, fn
          {:error, :entitlement_consume_failed} -> true
          {:error, {:consume_failed, :entitlement_consume_failed}} -> true
          _ -> false
        end)

      assert wins == 1
      assert fails == 1

      ent = Entitlements.get_entitlement!(entitlement.id)
      assert ent.status == :consumed
      assert ent.consumed_booking_id in [booking_a.id, booking_b.id]
    end

    test "consume_for_booking! rejects expired entitlements", %{
      user: user,
      admin: admin
    } do
      past =
        DateTime.add(DateTime.utc_now(), -86_400, :second)
        |> DateTime.truncate(:second)

      assert {:ok, entitlement} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 25),
                   expires_at: past
                 },
                 send_notification: false
               )

      booking = booking_fixture(%{user_id: user.id, status: :hold})

      assert {:error, :entitlement_consume_failed} =
               Entitlements.consume_for_booking!(entitlement.id, booking.id)
    end
  end

  describe "active hold entitlement reservation" do
    test "only the first active hold can lock an entitlement", %{
      user: user,
      admin: admin
    } do
      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Ent reserve category #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      assert {:ok, _} =
               Bookings.create_pricing_rule(%{
                 amount: Money.new(:USD, 100),
                 booking_mode: :room,
                 price_unit: :per_person_per_night,
                 property: :tahoe,
                 season_id: nil,
                 room_id: nil,
                 room_category_id: category.id
               })

      {:ok, room_a} =
        Bookings.create_room(%{
          name: "Ent reserve room A",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {:ok, room_b} =
        Bookings.create_room(%{
          name: "Ent reserve room B",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      assert {:ok, entitlement} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 25)
                 },
                 send_notification: false
               )

      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

      assert {:ok, booking_a} =
               BookingLocker.create_room_booking(
                 user.id,
                 room_a.id,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, booking_b} =
               BookingLocker.create_room_booking(
                 user.id,
                 room_b.id,
                 checkin,
                 checkout,
                 2
               )

      assert booking_a.applied_booking_entitlement_id == entitlement.id
      refute booking_b.applied_booking_entitlement_id

      assert [reserved_id] =
               Entitlements.entitlement_ids_reserved_on_active_holds()

      assert reserved_id == entitlement.id

      assert Entitlements.entitlement_reserved_on_active_hold?(entitlement.id)

      refute Entitlements.entitlement_reserved_on_active_hold?(
               entitlement.id,
               booking_a.id
             )

      assert Entitlements.entitlement_reserved_on_active_hold?(
               entitlement.id,
               booking_b.id
             )

      assert {:error, changeset} =
               booking_b
               |> Ecto.Changeset.change(%{
                 applied_booking_entitlement_id: entitlement.id
               })
               |> Ecto.Changeset.unique_constraint(
                 :applied_booking_entitlement_id,
                 name: :bookings_one_hold_per_entitlement_idx
               )
               |> Repo.update()

      assert "has already been taken" in errors_on(changeset).applied_booking_entitlement_id

      refute Entitlements.entitlement_reserved_on_active_hold?(nil)

      booking_b_with_entitlement = %{
        booking_b
        | applied_booking_entitlement_id: entitlement.id
      }

      assert {:error, :entitlement_no_longer_valid} =
               Entitlements.price_with_locked_entitlement(
                 booking_b_with_entitlement,
                 Money.new(:USD, 200),
                 :room,
                 guests_count: 2,
                 children_count: 0,
                 room_ids: [room_b.id]
               )
    end
  end

  describe "expire_passed_entitlements/1" do
    test "sets active entitlements with past expires_at to expired", %{
      user: user,
      admin: admin
    } do
      past =
        DateTime.add(DateTime.utc_now(), -86_400, :second)
        |> DateTime.truncate(:second)

      assert {:ok, ent} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 25),
                   expires_at: past
                 },
                 send_notification: false
               )

      assert {:ok, %{expired: 1, failed: 0}} =
               Entitlements.expire_passed_entitlements()

      assert Repo.get!(Ysc.Bookings.BookingEntitlement, ent.id).status ==
               :expired
    end

    test "skips active entitlements with nil expires_at", %{
      user: user,
      admin: admin
    } do
      assert {:ok, _} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 10)
                 },
                 send_notification: false
               )

      assert {:ok, %{expired: 0, failed: 0}} =
               Entitlements.expire_passed_entitlements()
    end

    test "skips entitlements that are still before expires_at", %{
      user: user,
      admin: admin
    } do
      future =
        DateTime.add(DateTime.utc_now(), 86_400, :second)
        |> DateTime.truncate(:second)

      assert {:ok, _} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 10),
                   expires_at: future
                 },
                 send_notification: false
               )

      assert {:ok, %{expired: 0, failed: 0}} =
               Entitlements.expire_passed_entitlements()
    end

    test "expire_passed_entitlements/1 respects :limit and oldest expires_at first",
         %{
           user: user,
           admin: admin
         } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      oldest = DateTime.add(now, -10 * 86_400, :second)
      middle = DateTime.add(now, -5 * 86_400, :second)
      newest = DateTime.add(now, -1 * 86_400, :second)

      for expires_at <- [newest, middle, oldest] do
        assert {:ok, _} =
                 Entitlements.create_entitlement(
                   %{
                     user_id: user.id,
                     issued_by_user_id: admin.id,
                     benefit_kind: :fixed_amount_off,
                     amount_off: Money.new(:USD, 1),
                     expires_at: expires_at
                   },
                   send_notification: false
                 )
      end

      assert {:ok, %{expired: 2, failed: 0}} =
               Entitlements.expire_passed_entitlements(limit: 2)

      active_count =
        from(e in Ysc.Bookings.BookingEntitlement,
          where: e.user_id == ^user.id,
          where: e.status == :active,
          select: count(e.id)
        )
        |> Ysc.Repo.one()

      assert active_count == 1

      assert {:ok, %{expired: 1, failed: 0}} =
               Entitlements.expire_passed_entitlements(limit: 2)

      assert {:ok, %{expired: 0, failed: 0}} =
               Entitlements.expire_passed_entitlements(limit: 2)
    end

    test "revoke_entitlement only succeeds for active rows", %{
      user: user,
      admin: admin
    } do
      past =
        DateTime.add(DateTime.utc_now(), -86_400, :second)
        |> DateTime.truncate(:second)

      assert {:ok, ent} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 3),
                   expires_at: past
                 },
                 send_notification: false
               )

      assert {:ok, %{expired: 1, failed: 0}} =
               Entitlements.expire_passed_entitlements()

      expired = Repo.get!(Ysc.Bookings.BookingEntitlement, ent.id)
      assert {:error, :not_revocable} = Entitlements.revoke_entitlement(expired)
    end
  end

  describe "list_usable_for_user/1" do
    test "excludes expired-by-date entitlements while returning usable ones", %{
      user: user,
      admin: admin
    } do
      assert {:ok, good} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 10)
                 },
                 send_notification: false
               )

      past =
        DateTime.add(DateTime.utc_now(), -86_400, :second)
        |> DateTime.truncate(:second)

      assert {:ok, bad} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 2),
                   expires_at: past
                 },
                 send_notification: false
               )

      usable = Entitlements.list_usable_for_user(user.id)
      ids = Enum.map(usable, & &1.id)

      assert good.id in ids
      refute bad.id in ids

      ent = Enum.find(usable, &(&1.id == good.id))
      assert match?(%Ecto.Association.NotLoaded{}, ent.issued_by_user)
    end
  end

  describe "BookingEntitlementExpiryWorker" do
    test "perform/1 runs expiry", %{user: user, admin: admin} do
      past =
        DateTime.add(DateTime.utc_now(), -86_400, :second)
        |> DateTime.truncate(:second)

      assert {:ok, _} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 5),
                   expires_at: past
                 },
                 send_notification: false
               )

      assert {:ok, msg} =
               Ysc.Bookings.BookingEntitlementExpiryWorker.perform(%Oban.Job{
                 args: %{}
               })

      assert msg =~ "Expired 1"
    end
  end

  describe "price_with_locked_entitlement/4 entitlement summary" do
    test "fixed_amount_off summary includes formatted discount amount", %{
      user: user,
      admin: admin
    } do
      for prop <- [:tahoe, :clear_lake] do
        case Bookings.create_pricing_rule(%{
               amount: Money.new(430, :USD),
               booking_mode: :buyout,
               price_unit: :buyout_fixed,
               property: prop,
               season_id: nil,
               room_id: nil,
               room_category_id: nil
             }) do
          {:ok, _} -> :ok
          {:error, %Ecto.Changeset{} = cs} -> assert duplicate_pricing_rule?(cs)
          {:error, other} -> flunk("unexpected pricing rule: #{inspect(other)}")
        end
      end

      {checkin, checkout} =
        Date.utc_today()
        |> then(fn today ->
          base = Date.add(today, 40)

          checkin =
            case Date.day_of_week(base, :monday) do
              1 -> base
              n -> Date.add(base, 8 - n)
            end

          {checkin, Date.add(checkin, 3)}
        end)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, entitlement} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: admin.id,
            benefit_kind: :fixed_amount_off,
            property: :tahoe,
            amount_off: Money.new(:USD, 25),
            max_guests: 10
          },
          send_notification: false
        )

      booking =
        booking
        |> Ecto.Changeset.change(%{
          applied_booking_entitlement_id: entitlement.id
        })
        |> Repo.update!()

      subtotal = Money.new(:USD, 430)

      assert {:ok, priced} =
               Entitlements.price_with_locked_entitlement(
                 booking,
                 subtotal,
                 :buyout
               )

      assert priced.breakdown_additions.entitlement_summary == "$25.00 off stay"
    end

    test "price_with_locked_entitlement formats free night entitlement summary" do
      user = user_fixture()
      admin = user_fixture()

      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, entitlement} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: admin.id,
            benefit_kind: :free_nights,
            property: :tahoe,
            free_nights: 2,
            buyout_max_discount: Money.new(500_000, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      booking =
        booking
        |> Ecto.Changeset.change(%{
          applied_booking_entitlement_id: entitlement.id
        })
        |> Repo.update!()

      subtotal = Money.new(:USD, 430)

      assert {:ok, priced} =
               Entitlements.price_with_locked_entitlement(
                 booking,
                 subtotal,
                 :buyout
               )

      assert priced.breakdown_additions.entitlement_summary == "2 free nights"
    end
  end

  describe "apply_best_entitlement/7" do
    test "skips entitlements reserved on another active hold and picks the next best",
         %{user: user, admin: admin} do
      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Apply best category #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      assert {:ok, _} =
               Bookings.create_pricing_rule(%{
                 amount: Money.new(:USD, 100),
                 booking_mode: :room,
                 price_unit: :per_person_per_night,
                 property: :tahoe,
                 season_id: nil,
                 room_id: nil,
                 room_category_id: category.id
               })

      {:ok, room_a} =
        Bookings.create_room(%{
          name: "Apply best room A",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {:ok, room_b} =
        Bookings.create_room(%{
          name: "Apply best room B",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      assert {:ok, larger_entitlement} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 50)
                 },
                 send_notification: false
               )

      assert {:ok, smaller_entitlement} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 25)
                 },
                 send_notification: false
               )

      {checkin, checkout} = tahoe_room_booking_dates(7, 2)
      subtotal = Money.new(:USD, 200)

      assert {:ok, booking_a} =
               BookingLocker.create_room_booking(
                 user.id,
                 room_a.id,
                 checkin,
                 checkout,
                 2
               )

      assert booking_a.applied_booking_entitlement_id == larger_entitlement.id

      {final_total, items, ^subtotal, discount, ent_id} =
        Entitlements.apply_best_entitlement(
          user.id,
          :tahoe,
          :room,
          checkin,
          checkout,
          subtotal,
          %{"type" => "room", "nights" => 2},
          guests_count: 2,
          children_count: 0,
          room_ids: [room_b.id]
        )

      assert ent_id == smaller_entitlement.id
      assert ent_id != larger_entitlement.id
      assert Money.cmp(discount, Money.new(:USD, 25)) == 0
      assert Money.cmp(final_total, Money.new(:USD, 175)) == 0
      assert [%{"entitlement_id" => ent_id_str}] = Map.get(items, "discounts")
      assert ent_id_str == smaller_entitlement.id
    end
  end

  describe "pricing_context/2" do
    test "builds reserved ids and eligible entitlements for preview", %{
      user: user,
      admin: admin
    } do
      assert {:ok, entitlement} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 25)
                 },
                 send_notification: false
               )

      context = Entitlements.pricing_context(user.id)

      assert context.user_id == user.id
      assert context.exclude_booking_id == nil
      assert entitlement.id in Enum.map(context.active_entitlements, & &1.id)

      assert MapSet.member?(context.reserved_entitlement_ids, entitlement.id) ==
               false
    end

    test "apply_best_entitlement/7 accepts pricing_context without extra queries",
         %{
           user: user,
           admin: admin
         } do
      assert {:ok, _} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 25)
                 },
                 send_notification: false
               )

      context = Entitlements.pricing_context(user.id)
      {checkin, checkout} = tahoe_room_booking_dates(7, 2)
      subtotal = Money.new(:USD, 200)

      entitlement_query? =
        ~r/(FROM "booking_entitlements"|applied_booking_entitlement_id)/

      {uncached, uncached_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            Entitlements.apply_best_entitlement(
              user.id,
              :tahoe,
              :buyout,
              checkin,
              checkout,
              subtotal,
              %{},
              []
            )
          end,
          pattern: entitlement_query?
        )

      {cached, cached_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            Entitlements.apply_best_entitlement(
              user.id,
              :tahoe,
              :buyout,
              checkin,
              checkout,
              subtotal,
              %{},
              pricing_context: context
            )
          end,
          pattern: entitlement_query?
        )

      assert uncached_queries == 2
      assert cached_queries == 0
      assert elem(uncached, 3) == elem(cached, 3)
    end

    test "exclude_booking_id keeps the hold's entitlement available for repricing",
         %{
           user: user,
           admin: admin
         } do
      {:ok, category} =
        %Ysc.Bookings.RoomCategory{}
        |> Ysc.Bookings.RoomCategory.changeset(%{
          name: "Pricing ctx category #{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      assert {:ok, _} =
               Bookings.create_pricing_rule(%{
                 amount: Money.new(:USD, 100),
                 booking_mode: :room,
                 price_unit: :per_person_per_night,
                 property: :tahoe,
                 season_id: nil,
                 room_id: nil,
                 room_category_id: category.id
               })

      {:ok, room} =
        Bookings.create_room(%{
          name: "Pricing ctx room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      assert {:ok, entitlement} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 25)
                 },
                 send_notification: false
               )

      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

      assert {:ok, booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 2
               )

      assert booking.applied_booking_entitlement_id == entitlement.id

      without_exclude = Entitlements.pricing_context(user.id)

      with_exclude =
        Entitlements.pricing_context(user.id, exclude_booking_id: booking.id)

      refute entitlement.id in Enum.map(
               without_exclude.active_entitlements,
               & &1.id
             )

      assert entitlement.id in Enum.map(
               with_exclude.active_entitlements,
               & &1.id
             )

      assert with_exclude.exclude_booking_id == booking.id
    end

    test "apply_best_entitlement/7 ignores pricing_context for a different user",
         %{
           user: user,
           admin: admin
         } do
      other_user = user_fixture()

      assert {:ok, _} =
               Entitlements.create_entitlement(
                 %{
                   user_id: user.id,
                   issued_by_user_id: admin.id,
                   benefit_kind: :fixed_amount_off,
                   amount_off: Money.new(:USD, 25)
                 },
                 send_notification: false
               )

      stale_context = Entitlements.pricing_context(other_user.id)
      {checkin, checkout} = tahoe_room_booking_dates(7, 2)
      subtotal = Money.new(:USD, 200)

      {_final_total, _items, _subtotal, discount, ent_id} =
        Entitlements.apply_best_entitlement(
          user.id,
          :tahoe,
          :buyout,
          checkin,
          checkout,
          subtotal,
          %{},
          pricing_context: stale_context
        )

      assert ent_id != nil
      assert Money.cmp(discount, Money.new(:USD, 25)) == 0
    end
  end

  defp duplicate_pricing_rule?(%Ecto.Changeset{} = cs) do
    Enum.any?(cs.errors, fn {_field, {_msg, meta}} ->
      meta[:constraint] == :unique
    end)
  end
end
