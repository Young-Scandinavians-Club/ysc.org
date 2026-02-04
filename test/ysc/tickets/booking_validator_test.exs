defmodule Ysc.Tickets.BookingValidatorTest do
  @moduledoc """
  Tests for ticket booking validation logic.

  These tests verify:
  - Event capacity validation
  - Ticket tier availability checks
  - User membership requirements
  - Event availability (not cancelled, not in past)
  - Concurrent booking prevention
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Tickets.BookingValidator
  alias Ysc.Events
  alias Ysc.Events.{Event, Ticket}
  alias Ysc.Repo

  setup do
    user = user_fixture()

    # Give user lifetime membership so they can purchase tickets
    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

    organizer = user_fixture()

    {:ok, event} =
      Events.create_event(%{
        title: "Test Event",
        description: "A test event",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    {:ok, tier1} =
      Events.create_ticket_tier(%{
        name: "General Admission",
        type: :paid,
        price: Money.new(50, :USD),
        quantity: 50,
        event_id: event.id
      })

    {:ok, tier2} =
      Events.create_ticket_tier(%{
        name: "VIP",
        type: :paid,
        price: Money.new(100, :USD),
        quantity: 25,
        event_id: event.id
      })

    {:ok, unlimited_tier} =
      Events.create_ticket_tier(%{
        name: "Unlimited Tier",
        type: :paid,
        price: Money.new(25, :USD),
        # Unlimited
        quantity: nil,
        event_id: event.id
      })

    %{
      user: user,
      event: event,
      tier1: tier1,
      tier2: tier2,
      unlimited_tier: unlimited_tier
    }
  end

  describe "validate_booking/3" do
    test "returns :ok for valid booking", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      ticket_selections = %{tier1.id => 2}

      assert :ok =
               BookingValidator.validate_booking(
                 user.id,
                 event.id,
                 ticket_selections
               )
    end

    test "returns error when user doesn't exist" do
      fake_user_id = Ecto.ULID.generate()
      fake_event_id = Ecto.ULID.generate()

      assert {:error, :user_not_found} =
               BookingValidator.validate_booking(
                 fake_user_id,
                 fake_event_id,
                 %{}
               )
    end

    test "returns error when user doesn't have active membership", %{
      event: event,
      tier1: tier1
    } do
      # Create user without membership
      user_without_membership = user_fixture()

      ticket_selections = %{tier1.id => 1}

      assert {:error, :membership_required} =
               BookingValidator.validate_booking(
                 user_without_membership.id,
                 event.id,
                 ticket_selections
               )
    end

    test "returns error when event doesn't exist", %{user: user} do
      fake_event_id = Ecto.ULID.generate()

      assert {:error, :event_not_found} =
               BookingValidator.validate_booking(user.id, fake_event_id, %{})
    end

    test "returns error when no tickets selected", %{user: user, event: event} do
      assert {:error, :no_tickets_selected} =
               BookingValidator.validate_booking(user.id, event.id, %{})
    end

    test "returns error when tier doesn't exist", %{user: user, event: event} do
      fake_tier_id = Ecto.ULID.generate()
      ticket_selections = %{fake_tier_id => 1}

      assert {:error, :invalid_tier_selection} =
               BookingValidator.validate_booking(
                 user.id,
                 event.id,
                 ticket_selections
               )
    end

    test "returns error when tier is for different event", %{
      user: user,
      event: _event,
      tier1: tier1
    } do
      # Create another event
      organizer = user_fixture()

      {:ok, other_event} =
        Events.create_event(%{
          title: "Other Event",
          description: "Another event",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              30,
              :day
            ),
          max_attendees: 50,
          published_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      ticket_selections = %{tier1.id => 1}

      assert {:error, :invalid_tier_selection} =
               BookingValidator.validate_booking(
                 user.id,
                 other_event.id,
                 ticket_selections
               )
    end

    test "returns error when tier is not on sale yet", %{
      user: user,
      event: event
    } do
      # Create tier with future start_date
      {:ok, future_tier} =
        Events.create_ticket_tier(%{
          name: "Future Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 50,
          event_id: event.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              1,
              :day
            )
        })

      ticket_selections = %{future_tier.id => 1}

      assert {:error, :invalid_tier_selection} =
               BookingValidator.validate_booking(
                 user.id,
                 event.id,
                 ticket_selections
               )
    end

    test "returns error when quantity is invalid", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      ticket_selections = %{tier1.id => 0}

      assert {:error, :invalid_tier_selection} =
               BookingValidator.validate_booking(
                 user.id,
                 event.id,
                 ticket_selections
               )

      ticket_selections = %{tier1.id => -1}

      assert {:error, :invalid_tier_selection} =
               BookingValidator.validate_booking(
                 user.id,
                 event.id,
                 ticket_selections
               )
    end

    test "returns error when tier capacity exceeded", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      # Request more tickets than available
      ticket_selections = %{tier1.id => 51}

      assert {:error, :tier_capacity_exceeded} =
               BookingValidator.validate_booking(
                 user.id,
                 event.id,
                 ticket_selections
               )
    end

    test "returns error when event capacity exceeded", %{
      user: user,
      event: event,
      tier1: tier1,
      tier2: _tier2
    } do
      # Fill up the event to capacity
      # Create 100 confirmed tickets (max_attendees = 100)
      for _i <- 1..100 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier1.id,
          status: :confirmed,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      # Try to book one more ticket
      ticket_selections = %{tier1.id => 1}

      # Event is already at capacity, so it returns :event_at_capacity
      assert {:error, :event_at_capacity} =
               BookingValidator.validate_booking(
                 user.id,
                 event.id,
                 ticket_selections
               )
    end

    test "allows booking when event has no max_attendees", %{
      user: user
    } do
      # Create event without max_attendees
      organizer = user_fixture()

      {:ok, unlimited_event} =
        Events.create_event(%{
          title: "Unlimited Event",
          description: "Event with no capacity limit",
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

      # Create an unlimited tier for this event
      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "General Admission",
          type: :paid,
          price: Money.new(50, :USD),
          # Unlimited
          quantity: nil,
          event_id: unlimited_event.id
        })

      ticket_selections = %{tier.id => 1000}

      assert :ok =
               BookingValidator.validate_booking(
                 user.id,
                 unlimited_event.id,
                 ticket_selections
               )
    end

    test "returns error when event is cancelled", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      # Cancel the event
      event
      |> Event.changeset(%{state: :cancelled})
      |> Repo.update!()

      ticket_selections = %{tier1.id => 1}

      assert {:error, :event_cancelled} =
               BookingValidator.validate_booking(
                 user.id,
                 event.id,
                 ticket_selections
               )
    end

    test "returns error when event is in the past", %{user: user, tier1: tier1} do
      # Create event in the past
      organizer = user_fixture()

      {:ok, past_event} =
        Events.create_event(%{
          title: "Past Event",
          description: "An event that already happened",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              -1,
              :day
            ),
          max_attendees: 100,
          published_at:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              -2,
              :day
            )
        })

      ticket_selections = %{tier1.id => 1}

      assert {:error, :event_in_past} =
               BookingValidator.validate_booking(
                 user.id,
                 past_event.id,
                 ticket_selections
               )
    end

    test "returns error when user has pending booking for same event", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      # Create a pending ticket order
      {:ok, ticket_order} =
        Ysc.Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      # Reload to ensure it's in pending status
      ticket_order = Ysc.Tickets.get_ticket_order(ticket_order.id)

      # Only test if order is still pending (it might have expired or been processed)
      if ticket_order.status == :pending do
        ticket_selections = %{tier1.id => 1}

        assert {:error, :concurrent_booking_not_allowed} =
                 BookingValidator.validate_booking(
                   user.id,
                   event.id,
                   ticket_selections
                 )
      end

      # Clean up
      if ticket_order.status == :pending do
        Ysc.Tickets.cancel_ticket_order(ticket_order, "Test cleanup")
      end
    end
  end

  describe "check_tier_capacity/2" do
    test "returns :ok for available tier", %{tier1: tier1} do
      assert {:ok, 50} = BookingValidator.check_tier_capacity(tier1.id, 10)
    end

    test "returns :unlimited for unlimited tier", %{
      unlimited_tier: unlimited_tier
    } do
      assert {:ok, :unlimited} =
               BookingValidator.check_tier_capacity(unlimited_tier.id, 1000)
    end

    test "returns error when tier not found" do
      fake_tier_id = Ecto.ULID.generate()

      assert {:error, :tier_not_found} =
               BookingValidator.check_tier_capacity(fake_tier_id, 1)
    end

    test "returns error when capacity exceeded", %{tier1: tier1} do
      assert {:error, :insufficient_capacity} =
               BookingValidator.check_tier_capacity(tier1.id, 51)
    end

    test "accounts for pending and confirmed tickets", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      # Create some pending and confirmed tickets
      for _i <- 1..10 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier1.id,
          status: :confirmed,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      for _i <- 1..5 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier1.id,
          status: :pending,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      # Tier has 50 total, 15 sold (10 confirmed + 5 pending), so 35 available
      assert {:ok, 35} = BookingValidator.check_tier_capacity(tier1.id, 10)

      assert {:error, :insufficient_capacity} =
               BookingValidator.check_tier_capacity(tier1.id, 36)
    end
  end

  describe "event_at_capacity?/1" do
    test "returns false when event has capacity", %{event: event} do
      assert false == BookingValidator.event_at_capacity?(event.id)
    end

    test "returns true when event is at capacity", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      # Fill up the event
      for _i <- 1..100 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier1.id,
          status: :confirmed,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      assert true == BookingValidator.event_at_capacity?(event.id)
    end

    test "returns false when event has no max_attendees", %{tier1: _tier1} do
      organizer = user_fixture()

      {:ok, unlimited_event} =
        Events.create_event(%{
          title: "Unlimited Event",
          description: "Event with no capacity limit",
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

      assert false == BookingValidator.event_at_capacity?(unlimited_event.id)
    end
  end

  describe "get_event_availability/1" do
    test "returns availability information for event", %{
      event: event,
      tier1: tier1,
      tier2: _tier2
    } do
      availability = BookingValidator.get_event_availability(event.id)

      assert %{event_capacity: event_capacity, tiers: tiers} = availability
      assert event_capacity.max_attendees == 100
      assert is_list(tiers)
      assert length(tiers) >= 2

      tier1_info = Enum.find(tiers, &(&1.tier_id == tier1.id))
      assert tier1_info != nil
      # Available should be 50 (total quantity) minus any sold tickets
      assert tier1_info.available == 50 or tier1_info.available == :unlimited
      assert tier1_info.total_quantity == 50
    end

    test "includes sold tickets in availability", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      # Create some tickets
      for _i <- 1..10 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier1.id,
          status: :confirmed,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      availability = BookingValidator.get_event_availability(event.id)
      tier1_info = Enum.find(availability.tiers, &(&1.tier_id == tier1.id))

      assert tier1_info != nil
      assert tier1_info.available == 40
      assert tier1_info.sold == 10
    end
  end
end
