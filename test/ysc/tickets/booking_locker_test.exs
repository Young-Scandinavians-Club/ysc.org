defmodule Ysc.Tickets.BookingLockerTest do
  @moduledoc """
  Tests for `Ysc.Tickets.BookingLocker` validation and availability helpers.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Tickets.BookingLocker
  alias Ysc.Events
  alias Ysc.Events.{Ticket, TicketReservation}
  import Ysc.AccountsFixtures
  import Ecto.Query

  defp with_lifetime_membership(%Ysc.Accounts.User{} = user) do
    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

  setup do
    organizer =
      user_fixture()
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

    user = user_fixture() |> with_lifetime_membership()

    {:ok, event} =
      Events.create_event(%{
        title: "Locker unit test event",
        description: "BookingLocker tests",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    {:ok, tier} =
      Events.create_ticket_tier(%{
        name: "GA",
        type: :paid,
        price: Money.new(25, :USD),
        quantity: 20,
        event_id: event.id
      })

    %{user: user, event: event, tier: tier, organizer: organizer}
  end

  describe "atomic_booking/3" do
    test "returns event_not_found for unknown event", %{user: user, tier: tier} do
      assert {:error, :event_not_found} =
               BookingLocker.atomic_booking(user.id, Ecto.ULID.generate(), %{
                 tier.id => 1
               })
    end

    test "returns event_cancelled when event is cancelled", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, _} =
        Events.update_event(event, %{
          state: :cancelled
        })

      assert {:error, :event_cancelled} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})
    end

    test "returns event_in_past when event already started", %{
      user: user,
      event: event,
      tier: tier
    } do
      past = DateTime.add(DateTime.utc_now(), -2, :day)

      {:ok, _} =
        Events.update_event(event, %{
          start_date: past
        })

      assert {:error, :event_in_past} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})
    end

    test "returns event_not_available for draft events", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, _} = Events.update_event(event, %{state: :draft})

      assert {:error, :event_not_available} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})
    end

    test "returns event_not_available for scheduled events", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, _} = Events.update_event(event, %{state: :scheduled})

      assert {:error, :event_not_available} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})
    end

    test "returns tier_validation_failed for unknown tier id", %{
      user: user,
      event: event
    } do
      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(user.id, event.id, %{
                 Ecto.ULID.generate() => 1
               })
    end
  end

  describe "check_availability_with_lock/1" do
    test "returns capacity info for tiers", %{event: event, tier: tier} do
      assert {:ok, %{event_capacity: ec, tiers: tiers}} =
               BookingLocker.check_availability_with_lock(event.id)

      assert ec.max_attendees == 100
      assert is_integer(ec.current_attendees)
      assert Enum.any?(tiers, &(&1.tier_id == tier.id))
    end

    test "reports unlimited event capacity when max_attendees is nil", %{} do
      organizer =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      {:ok, event} =
        Events.create_event(%{
          title: "Unlimited cap event",
          description: "No max",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              40,
              :day
            ),
          max_attendees: nil,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, _} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 5,
          event_id: event.id
        })

      assert {:ok, %{event_capacity: ec}} =
               BookingLocker.check_availability_with_lock(event.id)

      assert ec.max_attendees == nil
      assert ec.available == :unlimited
      assert ec.at_capacity == false
    end
  end

  describe "atomic_booking/3 tier and capacity validation" do
    test "returns tier_validation_failed when quantity is zero", %{
      user: user,
      event: event,
      tier: tier
    } do
      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 0})
    end

    test "returns tier_validation_failed when tier is not on sale yet", %{
      user: user,
      event: event,
      tier: tier
    } do
      future =
        DateTime.add(DateTime.utc_now(), 2, :day) |> DateTime.truncate(:second)

      {:ok, _} = Events.update_ticket_tier(tier, %{start_date: future})

      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})
    end

    test "returns tier_validation_failed when quantity exceeds tier capacity",
         %{
           user: user,
           event: event,
           tier: tier
         } do
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 2})

      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 3})
    end

    test "returns event_capacity_exceeded when event max_attendees would be exceeded",
         %{} do
      organizer =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      buyer = user_fixture()

      {:ok, event} =
        Events.create_event(%{
          title: "Small venue",
          description: "capacity test",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              35,
              :day
            ),
          max_attendees: 3,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(10, :USD),
          quantity: 50,
          event_id: event.id
        })

      assert {:error, :event_capacity_exceeded} =
               BookingLocker.atomic_booking(buyer.id, event.id, %{tier.id => 4})
    end

    test "emits overbooking telemetry when tier capacity is insufficient",
         %{
           user: user,
           event: event,
           tier: tier
         } do
      tier_id = tier.id
      parent = self()

      ref =
        :telemetry.attach(
          "booking-locker-overbook-#{System.unique_integer([:positive])}",
          [:ysc, :tickets, :overbooking_attempt],
          fn _event, measurements, metadata, _ ->
            send(parent, {:overbook, measurements, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 1})

      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 2})

      assert_receive {:overbook, %{count: 1},
                      %{
                        tier_id: ^tier_id,
                        reason: "insufficient_capacity"
                      }},
                     1_000
    end

    test "atomic_booking succeeds and creates order and tickets", %{
      user: user,
      event: event,
      tier: tier
    } do
      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 2})

      assert order.user_id == user.id
      assert order.event_id == event.id
      {:ok, fifty} = Money.mult(Money.new(25, :USD), 2)
      assert Money.equal?(order.total_amount, fifty)

      count =
        Repo.aggregate(
          from(t in Ticket, where: t.ticket_order_id == ^order.id),
          :count
        )

      assert count == 2
    end

    test "paid tier with unlimited quantity (nil) succeeds", %{
      user: user,
      event: event
    } do
      {:ok, open_tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(10, :USD),
          quantity: nil,
          event_id: event.id
        })

      assert {:ok, %{id: order_id}} =
               BookingLocker.atomic_booking(user.id, event.id, %{
                 open_tier.id => 3
               })

      assert Repo.aggregate(
               from(t in Ticket, where: t.ticket_order_id == ^order_id),
               :count
             ) == 3
    end

    test "donation tickets do not count toward event max_attendees capacity", %{
      organizer: organizer
    } do
      buyer = user_fixture() |> with_lifetime_membership()

      {:ok, event} =
        Events.create_event(%{
          title: "Donation capacity",
          description: "donations should not block regular sales",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              30,
              :day
            ),
          max_attendees: 10,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, paid_tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(10, :USD),
          quantity: 50,
          event_id: event.id
        })

      {:ok, donation_tier} =
        Events.create_ticket_tier(%{
          name: "Support",
          type: :donation,
          price: nil,
          quantity: 50,
          event_id: event.id
        })

      for _ <- 1..8 do
        other = user_fixture() |> with_lifetime_membership()

        assert {:ok, _} =
                 BookingLocker.atomic_booking(other.id, event.id, %{
                   paid_tier.id => 1
                 })
      end

      for i <- 1..5 do
        donor = user_fixture() |> with_lifetime_membership()

        assert {:ok, _} =
                 BookingLocker.atomic_booking(donor.id, event.id, %{
                   donation_tier.id => 1000 * i
                 })
      end

      assert {:ok, order} =
               BookingLocker.atomic_booking(buyer.id, event.id, %{
                 paid_tier.id => 1
               })

      assert order.event_id == event.id

      regular_ticket_count =
        Repo.aggregate(
          from(t in Ticket,
            join: tt in assoc(t, :ticket_tier),
            where:
              t.event_id == ^event.id and t.status in [:confirmed, :pending] and
                tt.type != :donation
          ),
          :count
        )

      assert regular_ticket_count == 9
    end

    test "donation tier accepts cents amount and creates one ticket", %{
      user: user,
      event: event
    } do
      {:ok, donation_tier} =
        Events.create_ticket_tier(%{
          name: "Support",
          type: :donation,
          price: nil,
          quantity: 50,
          event_id: event.id
        })

      cents = 5000

      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, %{
                 donation_tier.id => cents
               })

      assert Money.equal?(
               order.total_amount,
               Money.new(Ysc.MoneyHelper.cents_to_dollars(cents), :USD)
             )

      assert Repo.aggregate(
               from(t in Ticket, where: t.ticket_order_id == ^order.id),
               :count
             ) == 1
    end

    test "free tier books at zero total", %{user: user, event: event} do
      {:ok, free_tier} =
        Events.create_ticket_tier(%{
          name: "Comp",
          type: :free,
          quantity: 20,
          event_id: event.id
        })

      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, %{
                 free_tier.id => 1
               })

      assert Money.equal?(order.total_amount, Money.new(0, :USD))
    end

    test "active reservation reduces available capacity but counts toward user allowance",
         %{
           user: user,
           event: event,
           tier: tier,
           organizer: organizer
         } do
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 2})

      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: user.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active"
      })
      |> Repo.insert!()

      assert {:ok, _} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})
    end

    test "reservation with discount reduces order total", %{
      user: user,
      event: event,
      tier: tier,
      organizer: organizer
    } do
      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: user.id,
        quantity: 1,
        created_by_id: organizer.id,
        discount_percentage: Decimal.new(50),
        status: "active"
      })
      |> Repo.insert!()

      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})

      {:ok, expected} =
        Money.sub(Money.new(25, :USD), Money.new("12.50", :USD))

      assert Money.equal?(order.total_amount, expected)
      assert Money.positive?(order.discount_amount)
    end

    test "reservation past expires_at does not apply discount", %{
      user: user,
      event: event,
      tier: tier,
      organizer: organizer
    } do
      future =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      past =
        DateTime.utc_now()
        |> DateTime.add(-120, :second)
        |> DateTime.truncate(:second)

      {:ok, reservation} =
        %TicketReservation{}
        |> TicketReservation.changeset(%{
          ticket_tier_id: tier.id,
          user_id: user.id,
          quantity: 1,
          created_by_id: organizer.id,
          discount_percentage: Decimal.new(50),
          status: "active",
          expires_at: future
        })
        |> Repo.insert()

      reservation
      |> Ecto.Changeset.change(%{expires_at: past})
      |> Repo.update!()

      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})

      assert Money.equal?(order.total_amount, Money.new(25, :USD))
      discount = order.discount_amount || Money.new(0, :USD)
      assert Money.equal?(discount, Money.new(0, :USD))
    end

    test "event capacity check is bypassed when user has an active reservation",
         %{
           organizer: organizer
         } do
      buyer = user_fixture() |> with_lifetime_membership()

      {:ok, event} =
        Events.create_event(%{
          title: "Reservation bypass",
          description: "cap",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              20,
              :day
            ),
          max_attendees: 1,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(10, :USD),
          quantity: 50,
          event_id: event.id
        })

      other = user_fixture() |> with_lifetime_membership()

      {:ok, _} =
        BookingLocker.atomic_booking(other.id, event.id, %{tier.id => 1})

      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: buyer.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active"
      })
      |> Repo.insert!()

      assert {:ok, _} =
               BookingLocker.atomic_booking(buyer.id, event.id, %{tier.id => 1})
    end

    test "returns event_in_past when start_date and start_time are in the past",
         %{
           user: user,
           event: event,
           tier: tier
         } do
      past_date = ~U[2020-01-15 12:00:00Z]

      {:ok, _} =
        Events.update_event(event, %{
          start_date: past_date,
          start_time: ~T[10:00:00]
        })

      assert {:error, :event_in_past} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})
    end

    test "emits telemetry when event capacity would be exceeded without reservation",
         %{} do
      organizer =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      buyer = user_fixture() |> with_lifetime_membership()

      {:ok, event} =
        Events.create_event(%{
          title: "Telemetry cap",
          description: "telemetry",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              25,
              :day
            ),
          max_attendees: 1,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(5, :USD),
          quantity: 5,
          event_id: event.id
        })

      assert {:ok, _} =
               BookingLocker.atomic_booking(buyer.id, event.id, %{tier.id => 1})

      parent = self()

      ref =
        :telemetry.attach(
          "booking-locker-event-cap-#{System.unique_integer([:positive])}",
          [:ysc, :tickets, :overbooking_attempt],
          fn _event, measurements, metadata, _ ->
            send(parent, {:event_cap, measurements, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      other = user_fixture() |> with_lifetime_membership()

      assert {:error, :event_capacity_exceeded} =
               BookingLocker.atomic_booking(other.id, event.id, %{tier.id => 1})

      assert_receive {:event_cap, %{count: 1},
                      %{reason: "event_capacity_exceeded"}},
                     1_000
    end
  end
end
