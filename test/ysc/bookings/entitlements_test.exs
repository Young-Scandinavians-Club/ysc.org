defmodule Ysc.Bookings.EntitlementsTest do
  use Ysc.DataCase, async: false

  alias Money
  alias Ysc.Bookings
  alias Ysc.Bookings.{BookingLocker, Entitlements}
  alias Ysc.Repo
  import Ysc.AccountsFixtures

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

      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

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
      assert entitlement.id == booking_b.applied_booking_entitlement_id

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
end
