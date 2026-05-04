defmodule Ysc.Bookings.EntitlementsTest do
  use Ysc.DataCase, async: false

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
end
