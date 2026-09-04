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

    test "allows booking a date-only event until Pacific midnight of that day",
         %{
           user: user,
           event: event,
           tier: tier
         } do
      # Same encoding the admin date picker uses: midnight UTC of the Pacific
      # calendar day. Tomorrow Pacific can already be "today" in UTC (evening
      # in California), so comparing the stored DateTime to utc_now would
      # spuriously reject checkout.
      pacific_tomorrow =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()
        |> Date.add(1)

      stored_start = DateTime.new!(pacific_tomorrow, ~T[00:00:00], "Etc/UTC")

      {:ok, _} =
        Events.update_event(event, %{
          start_date: stored_start,
          start_time: nil
        })

      assert {:ok, _order} =
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

    test "treats a tier with quantity 0 as unlimited", %{event: event} do
      {:ok, zero_tier} =
        Events.create_ticket_tier(%{
          name: "Legacy unset quantity",
          type: :paid,
          price: Money.new(10, :USD),
          quantity: 5,
          event_id: event.id
        })

      # The create/update changeset normalizes an incoming 0 to nil (treated
      # as unlimited already), so a raw quantity: 0 row can only occur via
      # legacy/imported data. Bypass the changeset with update_all to
      # reproduce that on-disk state.
      Repo.update_all(
        from(tt in Ysc.Events.TicketTier, where: tt.id == ^zero_tier.id),
        set: [quantity: 0]
      )

      assert {:ok, %{tiers: tiers}} =
               BookingLocker.check_availability_with_lock(event.id)

      assert %{available: :unlimited} =
               Enum.find(tiers, &(&1.tier_id == zero_tier.id))
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

    test "succeeds against an event with no max_attendees limit", %{
      user: user,
      tier: tier,
      organizer: organizer
    } do
      {:ok, unlimited_event} =
        Events.create_event(%{
          title: "No cap event",
          description: "unlimited attendees",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              30,
              :day
            ),
          max_attendees: nil,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, tier2} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 20,
          event_id: unlimited_event.id
        })

      assert {:ok, _order} =
               BookingLocker.atomic_booking(user.id, unlimited_event.id, %{
                 tier2.id => 1
               })

      refute tier.id == tier2.id
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

    @user_pk ~r/FROM "users" AS u0 WHERE \(u0\."id" = \$/

    test "looks up the buyer once when inserting several tickets", %{
      user: user,
      event: event,
      tier: tier
    } do
      {{:ok, order}, user_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 3})
          end,
          pattern: @user_pk,
          caller_pids: [self()]
        )

      count =
        Repo.aggregate(
          from(t in Ticket, where: t.ticket_order_id == ^order.id),
          :count
        )

      assert count == 3
      assert user_lookups == 1
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

    test "allows donation-only atomic booking when event is sold out on regular tickets",
         %{
           organizer: organizer
         } do
      donor = user_fixture() |> with_lifetime_membership()

      {:ok, event} =
        Events.create_event(%{
          title: "Sold out donations",
          description: "donations after sellout",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              30,
              :day
            ),
          max_attendees: 2,
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

      for _ <- 1..2 do
        buyer = user_fixture() |> with_lifetime_membership()

        assert {:ok, _} =
                 BookingLocker.atomic_booking(buyer.id, event.id, %{
                   paid_tier.id => 1
                 })
      end

      assert {:ok, order} =
               BookingLocker.atomic_booking(donor.id, event.id, %{
                 donation_tier.id => 2500
               })

      assert order.event_id == event.id
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

    test "another user's active reservation blocks booking when capacity is exhausted",
         %{
           user: user,
           event: event,
           tier: tier,
           organizer: organizer
         } do
      other_user = user_fixture() |> with_lifetime_membership()
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 2})

      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: other_user.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active"
      })
      |> Repo.insert!()

      assert {:ok, _} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})

      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 2})
    end

    test "another user's active reservation blocks booking when tier is fully held",
         %{
           user: user,
           event: event,
           tier: tier,
           organizer: organizer
         } do
      other_user = user_fixture() |> with_lifetime_membership()
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 1})

      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: other_user.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active"
      })
      |> Repo.insert!()

      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})
    end

    test "expired reservation from another user does not block booking",
         %{
           user: user,
           event: event,
           tier: tier,
           organizer: organizer
         } do
      other_user = user_fixture() |> with_lifetime_membership()
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 1})

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
          user_id: other_user.id,
          quantity: 1,
          created_by_id: organizer.id,
          status: "active",
          expires_at: future
        })
        |> Repo.insert()

      reservation
      |> Ecto.Changeset.change(%{expires_at: past})
      |> Repo.update!()

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

    test "partial checkout only creates tickets for selected quantity and keeps reservation remainder",
         %{
           user: user,
           event: event,
           tier: tier,
           organizer: organizer
         } do
      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: user.id,
        quantity: 5,
        created_by_id: organizer.id,
        discount_percentage: Decimal.new(50),
        status: "active"
      })
      |> Repo.insert!()

      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 2})

      tickets =
        from(t in Ticket, where: t.ticket_order_id == ^order.id)
        |> Repo.all()

      assert length(tickets) == 2

      {:ok, expected_total} =
        Money.sub(Money.new(50, :USD), Money.new("25.00", :USD))

      assert Money.equal?(order.total_amount, expected_total)

      active_remainder =
        from(tr in TicketReservation,
          where:
            tr.user_id == ^user.id and tr.ticket_tier_id == ^tier.id and
              tr.status == "active"
        )
        |> Repo.all()

      assert length(active_remainder) == 1
      assert hd(active_remainder).quantity == 3
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

  describe "atomic_booking/4 with bypass_guards: true" do
    test "succeeds for an event that has already started", %{
      user: user,
      event: event,
      tier: tier
    } do
      past = DateTime.add(DateTime.utc_now(), -2, :day)
      {:ok, _} = Events.update_event(event, %{start_date: past})

      assert {:ok, _order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1},
                 bypass_guards: true
               )
    end

    test "still rejects a cancelled event", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, _} = Events.update_event(event, %{state: :cancelled})

      assert {:error, :event_cancelled} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1},
                 bypass_guards: true
               )
    end

    test "still rejects a draft event", %{user: user, event: event, tier: tier} do
      {:ok, _} = Events.update_event(event, %{state: :draft})

      assert {:error, :event_not_available} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1},
                 bypass_guards: true
               )
    end

    test "succeeds for a tier whose sale window hasn't started yet", %{
      user: user,
      event: event,
      tier: tier
    } do
      future =
        DateTime.add(DateTime.utc_now(), 2, :day) |> DateTime.truncate(:second)

      {:ok, _} = Events.update_ticket_tier(tier, %{start_date: future})

      assert {:ok, _order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1},
                 bypass_guards: true
               )
    end

    test "succeeds selling more than the tier's remaining capacity", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 2})

      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 5},
                 bypass_guards: true
               )

      assert Repo.aggregate(
               from(t in Ticket, where: t.ticket_order_id == ^order.id),
               :count
             ) == 5
    end

    test "succeeds selling past the event's max_attendees", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, _} = Events.update_event(event, %{max_attendees: 1})
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 10})

      assert {:ok, _order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 4},
                 bypass_guards: true
               )
    end

    test "skips event and tier SELECTs when they are passed in", %{
      user: user,
      event: event,
      tier: tier
    } do
      selections = %{tier.id => 1}

      {result, event_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.atomic_booking(user.id, event.id, selections,
              bypass_guards: true,
              user: user,
              event: event,
              tiers: [tier]
            )
          end,
          pattern: ~r/FROM "events"/,
          caller_pids: [self()]
        )

      {_, tier_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.atomic_booking(user.id, event.id, selections,
              bypass_guards: true,
              user: user,
              event: event,
              tiers: [tier]
            )
          end,
          pattern: ~r/FROM "ticket_tiers"/,
          caller_pids: [self()]
        )

      assert {:ok, _order} = result
      assert event_lookups == 0
      assert tier_lookups == 0
    end

    test "still rejects a cancelled event struct without reloading it", %{
      user: user,
      event: event,
      tier: tier
    } do
      cancelled = %{event | state: :cancelled}

      {result, event_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1},
              bypass_guards: true,
              event: cancelled,
              tiers: [tier]
            )
          end,
          pattern: ~r/FROM "events"/,
          caller_pids: [self()]
        )

      assert {:error, :event_cancelled} = result
      assert event_lookups == 0
    end

    test "reloads selected tiers when the passed list is incomplete", %{
      user: user,
      event: event,
      tier: tier
    } do
      {result, tier_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1},
              bypass_guards: true,
              user: user,
              event: event,
              tiers: []
            )
          end,
          pattern: ~r/FROM "ticket_tiers"/,
          caller_pids: [self()]
        )

      assert {:ok, _order} = result
      assert tier_lookups == 1
    end

    # #1213 reuses caller-supplied event/tier structs. QueryCounter tests prove
    # matching ids skip SELECTs; these prove a mismatched id still reloads.
    test "reloads the booked event when the passed struct is a different event",
         %{
           user: user,
           event: event,
           tier: tier,
           organizer: organizer
         } do
      {:ok, other} =
        Events.create_event(%{
          title: "Other locker event",
          description: "ID mismatch",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              30,
              :day
            ),
          max_attendees: 100,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, _} = Events.update_event(event, %{state: :cancelled})

      {result, event_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1},
              bypass_guards: true,
              event: other,
              tiers: [tier]
            )
          end,
          pattern: ~r/FROM "events"/,
          caller_pids: [self()]
        )

      assert {:error, :event_cancelled} = result
      assert event_lookups == 1
    end

    test "does not reject a published booking when a cancelled other-event struct is passed",
         %{
           user: user,
           event: event,
           tier: tier,
           organizer: organizer
         } do
      {:ok, other} =
        Events.create_event(%{
          title: "Cancelled other locker event",
          description: "ID mismatch",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              30,
              :day
            ),
          max_attendees: 100,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, other} = Events.update_event(other, %{state: :cancelled})

      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1},
                 bypass_guards: true,
                 user: user,
                 event: other,
                 tiers: [tier]
               )

      assert order.event_id == event.id
    end

    test "reloads this event's tiers when the passed list belongs to another event",
         %{
           user: user,
           event: event,
           tier: tier,
           organizer: organizer
         } do
      {:ok, other} =
        Events.create_event(%{
          title: "Cheap other locker event",
          description: "ID mismatch",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              30,
              :day
            ),
          max_attendees: 100,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, cheap_tier} =
        Events.create_ticket_tier(%{
          name: "Cheap",
          type: :paid,
          price: Money.new(1, :USD),
          quantity: 20,
          event_id: other.id
        })

      {result, tier_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1},
              bypass_guards: true,
              user: user,
              event: event,
              tiers: [cheap_tier]
            )
          end,
          pattern: ~r/FROM "ticket_tiers"/,
          caller_pids: [self()]
        )

      assert {:ok, order} = result
      assert Money.equal?(order.total_amount, Money.new(25, :USD))
      assert tier_lookups == 1
    end
  end

  describe "capacity_warnings/2" do
    test "empty when the selection is within tier and event capacity", %{
      event: event,
      tier: tier
    } do
      assert BookingLocker.capacity_warnings(event.id, %{tier.id => 1}) == []
    end

    test "warns when the selection exceeds the tier's remaining capacity", %{
      event: event,
      tier: tier
    } do
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 2})

      assert [warning] =
               BookingLocker.capacity_warnings(event.id, %{tier.id => 5})

      assert warning =~ tier.name
      assert warning =~ "exceeds the 2 remaining by 3"
    end

    test "warns when the selection would exceed event max_attendees", %{
      event: event,
      tier: tier
    } do
      {:ok, _} = Events.update_event(event, %{max_attendees: 1})
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 10})

      assert [warning] =
               BookingLocker.capacity_warnings(event.id, %{tier.id => 4})

      assert warning =~ "Event capacity"
      assert warning =~ "exceeding it by 3"
    end

    test "can return both a tier and an event capacity warning", %{
      event: event,
      tier: tier
    } do
      {:ok, _} = Events.update_event(event, %{max_attendees: 1})
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 2})

      assert warnings =
               BookingLocker.capacity_warnings(event.id, %{tier.id => 5})

      assert length(warnings) == 2
    end

    test "does not warn for donation tiers regardless of quantity", %{
      event: event
    } do
      {:ok, donation_tier} =
        Events.create_ticket_tier(%{
          name: "Donate",
          type: :donation,
          price: Money.new(0, :USD),
          quantity: 1,
          event_id: event.id
        })

      assert BookingLocker.capacity_warnings(event.id, %{donation_tier.id => 50}) ==
               []
    end

    test "returns an empty list for an unknown event", %{tier: tier} do
      assert BookingLocker.capacity_warnings(Ecto.ULID.generate(), %{
               tier.id => 1
             }) == []
    end

    test "skips event and tier SELECTs when they are passed in", %{
      event: event,
      tier: tier
    } do
      selections = %{tier.id => 1}

      {warnings, event_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.capacity_warnings(event.id, selections,
              event: event,
              tiers: [tier]
            )
          end,
          pattern: ~r/FROM "events"/,
          caller_pids: [self()]
        )

      {_, tier_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.capacity_warnings(event.id, selections,
              event: event,
              tiers: [tier]
            )
          end,
          pattern: ~r/FROM "ticket_tiers"/,
          caller_pids: [self()]
        )

      assert warnings == []
      assert event_lookups == 0
      assert tier_lookups == 0
    end

    test "counts another buyer's hold against remaining capacity", %{
      event: event,
      tier: tier,
      organizer: organizer
    } do
      other_user = user_fixture() |> with_lifetime_membership()
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 2})

      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: other_user.id,
        quantity: 1,
        created_by_id: organizer.id,
        status: "active"
      })
      |> Repo.insert!()

      assert [warning] =
               BookingLocker.capacity_warnings(event.id, %{tier.id => 2})

      assert warning =~ "exceeds the 1 remaining by 1"
    end

    test "warns per selected capped tier in a multi-tier sale", %{
      event: event,
      tier: tier
    } do
      {:ok, _} = Events.update_ticket_tier(tier, %{quantity: 1})

      {:ok, vip} =
        Events.create_ticket_tier(%{
          name: "VIP",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 1,
          event_id: event.id
        })

      warnings =
        BookingLocker.capacity_warnings(event.id, %{
          tier.id => 2,
          vip.id => 3
        })

      assert length(warnings) == 2
      assert Enum.any?(warnings, &String.contains?(&1, tier.name))
      assert Enum.any?(warnings, &String.contains?(&1, "VIP"))
    end
  end

  describe "batched inventory counts" do
    # Ecto 3.14 emits `= ANY($1)` for `in ^list` and `= $1` for a single id.
    # Event-wide `SELECT count(id)` joins `ON tickets.ticket_tier_id = ticket_tiers.id`
    # and must not be mistaken for a per-tier COUNT.
    @per_tier_sold_count ~r/FROM "tickets" AS t0 WHERE \(t0\."ticket_tier_id" = \$/
    @batched_sold_count ~r/FROM "tickets" AS t0 WHERE \(t0\."ticket_tier_id" = ANY/
    @per_tier_reserved_sum ~r/FROM "ticket_reservations" AS t0 WHERE \(t0\."ticket_tier_id" = \$/
    @batched_reserved_sum ~r/FROM "ticket_reservations" AS t0 WHERE \(t0\."ticket_tier_id" = ANY/

    defp extra_capped_tiers(event, count) do
      Enum.map(1..count, fn n ->
        {:ok, tier} =
          Events.create_ticket_tier(%{
            name: "Tier #{n}",
            type: :paid,
            price: Money.new(10, :USD),
            quantity: 10,
            event_id: event.id
          })

        tier
      end)
    end

    test "capacity_warnings does not issue a sold COUNT per selected tier", %{
      event: event,
      tier: tier
    } do
      extra = extra_capped_tiers(event, 3)

      selections =
        Map.new([tier | extra], fn t -> {t.id, 1} end)

      {{warnings, per_tier_sold}, batched_sold} =
        with {warnings, per_tier_sold} <-
               Ysc.QueryCounter.with_query_counter(
                 fn ->
                   BookingLocker.capacity_warnings(event.id, selections)
                 end,
                 pattern: @per_tier_sold_count,
                 caller_pids: [self()]
               ),
             {_, batched_sold} <-
               Ysc.QueryCounter.with_query_counter(
                 fn ->
                   BookingLocker.capacity_warnings(event.id, selections)
                 end,
                 pattern: @batched_sold_count,
                 caller_pids: [self()]
               ) do
          {{warnings, per_tier_sold}, batched_sold}
        end

      assert warnings == []
      assert per_tier_sold == 0
      assert batched_sold == 1
    end

    test "capacity_warnings does not issue a reservation SUM per selected tier",
         %{
           event: event,
           tier: tier
         } do
      extra = extra_capped_tiers(event, 3)

      selections =
        Map.new([tier | extra], fn t -> {t.id, 1} end)

      {{_warnings, per_tier_reserved}, batched_reserved} =
        with {warnings, per_tier_reserved} <-
               Ysc.QueryCounter.with_query_counter(
                 fn ->
                   BookingLocker.capacity_warnings(event.id, selections)
                 end,
                 pattern: @per_tier_reserved_sum,
                 caller_pids: [self()]
               ),
             {_, batched_reserved} <-
               Ysc.QueryCounter.with_query_counter(
                 fn ->
                   BookingLocker.capacity_warnings(event.id, selections)
                 end,
                 pattern: @batched_reserved_sum,
                 caller_pids: [self()]
               ) do
          {{warnings, per_tier_reserved}, batched_reserved}
        end

      assert per_tier_reserved == 0
      assert batched_reserved == 1
    end

    test "atomic_booking does not issue a sold COUNT per selected tier", %{
      user: user,
      event: event,
      tier: tier
    } do
      extra = extra_capped_tiers(event, 2)

      selections =
        Map.new([tier | extra], fn t -> {t.id, 1} end)

      {{result, per_tier_sold}, batched_sold} =
        with {result, per_tier_sold} <-
               Ysc.QueryCounter.with_query_counter(
                 fn ->
                   BookingLocker.atomic_booking(user.id, event.id, selections)
                 end,
                 pattern: @per_tier_sold_count,
                 caller_pids: [self()]
               ),
             {_, batched_sold} <-
               Ysc.QueryCounter.with_query_counter(
                 fn ->
                   BookingLocker.atomic_booking(user.id, event.id, %{
                     List.first(extra).id => 1
                   })
                 end,
                 pattern: @batched_sold_count,
                 caller_pids: [self()]
               ) do
          {{result, per_tier_sold}, batched_sold}
        end

      assert {:ok, _order} = result
      assert per_tier_sold == 0
      assert batched_sold == 1
    end

    test "check_availability_with_lock does not issue a sold COUNT per tier", %{
      event: event,
      tier: tier
    } do
      _extra = extra_capped_tiers(event, 3)
      _ = tier

      {{result, per_tier_sold}, batched_sold} =
        with {result, per_tier_sold} <-
               Ysc.QueryCounter.with_query_counter(
                 fn -> BookingLocker.check_availability_with_lock(event.id) end,
                 pattern: @per_tier_sold_count,
                 caller_pids: [self()]
               ),
             {_, batched_sold} <-
               Ysc.QueryCounter.with_query_counter(
                 fn -> BookingLocker.check_availability_with_lock(event.id) end,
                 pattern: @batched_sold_count,
                 caller_pids: [self()]
               ) do
          {{result, per_tier_sold}, batched_sold}
        end

      assert {:ok, %{tiers: tiers}} = result
      assert length(tiers) >= 4
      assert per_tier_sold == 0
      assert batched_sold == 1
    end
  end

  describe "validate_fulfillment_capacity/3" do
    test "returns :ok when requested tickets fit remaining capacity", %{
      user: user,
      event: event,
      tier: tier
    } do
      assert :ok =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 event.id,
                 %{tier.id => 1}
               )
    end

    test "returns {:error, :event_capacity_exceeded} when event is full", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, limited_event} = Events.update_event(event, %{max_attendees: 1})
      other = user_fixture() |> with_lifetime_membership()

      assert {:ok, _} =
               BookingLocker.atomic_booking(other.id, limited_event.id, %{
                 tier.id => 1
               })

      assert {:error, :event_capacity_exceeded} =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 limited_event.id,
                 %{tier.id => 1}
               )
    end

    test "returns {:error, :tier_validation_failed} when tier is sold out", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, limited_tier} = Events.update_ticket_tier(tier, %{quantity: 1})
      other = user_fixture() |> with_lifetime_membership()

      assert {:ok, _} =
               BookingLocker.atomic_booking(other.id, event.id, %{
                 limited_tier.id => 1
               })

      assert {:error, :tier_validation_failed} =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 event.id,
                 %{limited_tier.id => 1}
               )
    end

    test "skip_capacity allows validation when tier is sold out", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, limited_tier} = Events.update_ticket_tier(tier, %{quantity: 1})
      other = user_fixture() |> with_lifetime_membership()

      assert {:ok, _} =
               BookingLocker.atomic_booking(other.id, event.id, %{
                 limited_tier.id => 1
               })

      assert {:error, :tier_validation_failed} =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 event.id,
                 %{limited_tier.id => 1}
               )

      assert :ok =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 event.id,
                 %{limited_tier.id => 1},
                 skip_capacity: true
               )
    end

    test "skip_capacity allows validation when event capacity is full", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, limited_event} = Events.update_event(event, %{max_attendees: 1})
      other = user_fixture() |> with_lifetime_membership()

      assert {:ok, _} =
               BookingLocker.atomic_booking(other.id, limited_event.id, %{
                 tier.id => 1
               })

      assert {:error, :event_capacity_exceeded} =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 limited_event.id,
                 %{tier.id => 1}
               )

      assert :ok =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 limited_event.id,
                 %{tier.id => 1},
                 skip_capacity: true
               )
    end

    test "skip_sale_guards allows validation for past events", %{
      user: user,
      event: event,
      tier: tier
    } do
      past = DateTime.add(DateTime.utc_now(), -2, :day)

      {:ok, past_event} =
        Events.update_event(event, %{
          start_date: past
        })

      assert {:error, :event_in_past} =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 past_event.id,
                 %{tier.id => 1}
               )

      assert :ok =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 past_event.id,
                 %{tier.id => 1},
                 skip_sale_guards: true,
                 skip_capacity: true
               )
    end

    test "skip_capacity alone does not bypass past-event checks", %{
      user: user,
      event: event,
      tier: tier
    } do
      past = DateTime.add(DateTime.utc_now(), -2, :day)

      {:ok, past_event} =
        Events.update_event(event, %{
          start_date: past
        })

      assert {:error, :event_in_past} =
               BookingLocker.validate_fulfillment_capacity(
                 user.id,
                 past_event.id,
                 %{tier.id => 1},
                 skip_capacity: true
               )
    end

    test "skip_capacity and skip_sale_guards together skip event and tier SELECTs",
         %{
           user: user,
           event: event,
           tier: tier
         } do
      {result, lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.validate_fulfillment_capacity(
              user.id,
              event.id,
              %{tier.id => 1},
              skip_capacity: true,
              skip_sale_guards: true
            )
          end,
          pattern: ~r/FROM "(events|ticket_tiers)"/,
          caller_pids: [self()]
        )

      assert result == :ok
      assert lookups == 0
    end
  end

  describe "validate_fulfillment_capacity_in_transaction/4" do
    test "skip_capacity bypasses tier limits inside an existing transaction", %{
      user: user,
      event: event,
      tier: tier
    } do
      {:ok, limited_tier} = Events.update_ticket_tier(tier, %{quantity: 1})
      other = user_fixture() |> with_lifetime_membership()

      assert {:ok, _} =
               BookingLocker.atomic_booking(other.id, event.id, %{
                 limited_tier.id => 1
               })

      assert {:ok, :ok} =
               Repo.transaction(fn ->
                 assert :ok =
                          BookingLocker.validate_fulfillment_capacity_in_transaction(
                            user.id,
                            event.id,
                            %{limited_tier.id => 1},
                            skip_capacity: true
                          )

                 :ok
               end)
    end

    test "defaults opts to [] when called with 3 arguments", %{
      user: user,
      event: event,
      tier: tier
    } do
      assert {:ok, :ok} =
               Repo.transaction(fn ->
                 assert :ok =
                          BookingLocker.validate_fulfillment_capacity_in_transaction(
                            user.id,
                            event.id,
                            %{tier.id => 1}
                          )

                 :ok
               end)
    end

    test "skip_sale_guards with an unknown event returns event_not_found", %{
      user: user,
      tier: tier
    } do
      assert {:ok, {:error, :event_not_found}} =
               Repo.transaction(fn ->
                 BookingLocker.validate_fulfillment_capacity_in_transaction(
                   user.id,
                   Ecto.ULID.generate(),
                   %{tier.id => 1},
                   skip_sale_guards: true
                 )
               end)
    end
  end

  describe "ci_query_explain_query/0" do
    test "builds a runnable Ecto query for CI query-plan diagnostics" do
      query = BookingLocker.ci_query_explain_query()

      assert %Ecto.Query{} = query
      assert Repo.all(query) == []
    end

    test "sold-count and user-reserved explain queries are runnable" do
      sold = BookingLocker.ci_query_explain_sold_counts_query()
      reserved = BookingLocker.ci_query_explain_user_reserved_query()

      assert %Ecto.Query{} = sold
      assert %Ecto.Query{} = reserved
      assert Repo.all(sold) == []
      assert Repo.all(reserved) == []

      selected = BookingLocker.ci_query_explain_selected_tiers_query()
      assert %Ecto.Query{} = selected
      assert Repo.all(selected) == []
    end
  end

  describe "fulfill_reservations_for_selections/4" do
    test "links active reservations to the ticket order FIFO per tier", %{
      user: user,
      event: event,
      tier: tier,
      organizer: organizer
    } do
      expires_at =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      {:ok, reservation} =
        %TicketReservation{}
        |> TicketReservation.changeset(%{
          ticket_tier_id: tier.id,
          user_id: user.id,
          quantity: 1,
          created_by_id: organizer.id,
          status: "active",
          expires_at: expires_at
        })
        |> Repo.insert()

      assert {:ok, order} =
               Repo.transaction(fn ->
                 {:ok, order} =
                   %Ysc.Tickets.TicketOrder{}
                   |> Ysc.Tickets.TicketOrder.create_changeset(%{
                     user_id: user.id,
                     event_id: event.id,
                     total_amount: Money.new(25, :USD),
                     expires_at: expires_at
                   })
                   |> Repo.insert()

                 assert {:ok, _fulfilled_by_tier} =
                          BookingLocker.fulfill_reservations_for_selections(
                            user.id,
                            event.id,
                            order.id,
                            %{tier.id => 1}
                          )

                 order
               end)

      reservation = Repo.reload!(reservation)
      assert reservation.status == "fulfilled"
      assert reservation.ticket_order_id == order.id
    end
  end

  describe "estimate_order_total/3" do
    test "returns zero for empty selections", %{user: user, event: event} do
      assert {:ok, total, discount} =
               BookingLocker.estimate_order_total(user.id, event.id, %{})

      assert Money.zero?(total)
      assert Money.zero?(discount)
    end

    test "matches atomic_booking total for paid tiers", %{
      user: user,
      event: event,
      tier: tier
    } do
      selections = %{tier.id => 2}

      assert {:ok, estimated_total, estimated_discount} =
               BookingLocker.estimate_order_total(user.id, event.id, selections)

      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, selections)

      assert Money.equal?(estimated_total, order.total_amount)

      assert Money.equal?(
               estimated_discount,
               order.discount_amount || Money.new(0, :USD)
             )
    end

    test "applies active reservation discounts", %{
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

      assert {:ok, estimated_total, estimated_discount} =
               BookingLocker.estimate_order_total(user.id, event.id, %{
                 tier.id => 1
               })

      {:ok, expected_total} =
        Money.sub(Money.new(25, :USD), Money.new("12.50", :USD))

      assert Money.equal?(estimated_total, expected_total)
      assert Money.positive?(estimated_discount)
    end

    test "keeps a 100%-off discount after checkout fulfills the reservation", %{
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
        discount_percentage: Decimal.new(100),
        status: "active"
      })
      |> Repo.insert!()

      assert {:ok, order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})

      assert Money.zero?(order.total_amount)

      # The hold is now "fulfilled", so an active-holds-only reprice loses it.
      assert {:ok, active_only_total, active_only_discount} =
               BookingLocker.estimate_order_total(user.id, event.id, %{
                 tier.id => 1
               })

      assert Money.equal?(active_only_total, tier.price)
      assert Money.zero?(active_only_discount)

      # Repricing the order must still see the discount it already fulfilled.
      assert {:ok, reprice_total, reprice_discount} =
               BookingLocker.estimate_order_total(
                 user.id,
                 event.id,
                 %{tier.id => 1},
                 include_fulfilled_for_order_id: order.id
               )

      assert Money.zero?(reprice_total)
      assert Money.equal?(reprice_discount, tier.price)
    end

    test "keeps a partial reservation discount after checkout fulfills the hold",
         %{
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

      {:ok, expected_total} = Money.sub(tier.price, Money.new("12.50", :USD))
      assert Money.equal?(order.total_amount, expected_total)

      assert {:ok, reprice_total, reprice_discount} =
               BookingLocker.estimate_order_total(
                 user.id,
                 event.id,
                 %{tier.id => 1},
                 include_fulfilled_for_order_id: order.id
               )

      assert Money.equal?(reprice_total, expected_total)
      assert Money.equal?(reprice_discount, Money.new("12.50", :USD))
    end

    test "does not apply a reservation fulfilled by a different order", %{
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
        discount_percentage: Decimal.new(100),
        status: "active"
      })
      |> Repo.insert!()

      assert {:ok, discounted_order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})

      assert Money.zero?(discounted_order.total_amount)

      assert {:ok, other_order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})

      assert Money.equal?(other_order.total_amount, tier.price)

      assert {:ok, other_total, other_discount} =
               BookingLocker.estimate_order_total(
                 user.id,
                 event.id,
                 %{tier.id => 1},
                 include_fulfilled_for_order_id: other_order.id
               )

      assert Money.equal?(other_total, tier.price)
      assert Money.zero?(other_discount)

      assert {:ok, original_total, original_discount} =
               BookingLocker.estimate_order_total(
                 user.id,
                 event.id,
                 %{tier.id => 1},
                 include_fulfilled_for_order_id: discounted_order.id
               )

      assert Money.zero?(original_total)
      assert Money.equal?(original_discount, tier.price)
    end

    @estimate_tiers ~r/FROM "ticket_tiers"/

    test "skips the tier SELECT when selected tiers are passed", %{
      user: user,
      event: event,
      tier: tier
    } do
      {_, lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.estimate_order_total(
              user.id,
              event.id,
              %{tier.id => 2},
              tiers: [tier]
            )
          end,
          pattern: @estimate_tiers,
          caller_pids: [self()]
        )

      assert lookups == 0
    end

    test "loads selected tiers once when they are not passed", %{
      user: user,
      event: event,
      tier: tier
    } do
      {_, lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.estimate_order_total(user.id, event.id, %{
              tier.id => 2
            })
          end,
          pattern: @estimate_tiers,
          caller_pids: [self()]
        )

      assert lookups == 1
    end

    # #1219 reuses caller-supplied :tiers for door-sale PaymentIntent
    # repricing. QueryCounter tests prove matching ids skip the SELECT;
    # these prove a mismatched/incomplete list still charges this event.
    test "reloads this event's prices when the passed :tiers belong to another event",
         %{
           user: user,
           event: event,
           tier: tier,
           organizer: organizer
         } do
      {:ok, other} =
        Events.create_event(%{
          title: "Cheap other estimate event",
          description: "ID mismatch",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              30,
              :day
            ),
          max_attendees: 100,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      {:ok, cheap_tier} =
        Events.create_ticket_tier(%{
          name: "Cheap",
          type: :paid,
          price: Money.new(1, :USD),
          quantity: 20,
          event_id: other.id
        })

      {result, tier_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.estimate_order_total(
              user.id,
              event.id,
              %{tier.id => 1},
              tiers: [cheap_tier]
            )
          end,
          pattern: @estimate_tiers,
          caller_pids: [self()]
        )

      assert {:ok, estimated_total, estimated_discount} = result
      assert Money.equal?(estimated_total, Money.new(25, :USD))
      assert Money.zero?(estimated_discount)
      assert tier_lookups == 1
    end

    test "reloads selected tiers when the passed :tiers list is incomplete", %{
      user: user,
      event: event,
      tier: tier
    } do
      {result, tier_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            BookingLocker.estimate_order_total(
              user.id,
              event.id,
              %{tier.id => 2},
              tiers: []
            )
          end,
          pattern: @estimate_tiers,
          caller_pids: [self()]
        )

      assert {:ok, estimated_total, _discount} = result
      assert Money.equal?(estimated_total, Money.new(50, :USD))
      assert tier_lookups == 1
    end
  end
end
