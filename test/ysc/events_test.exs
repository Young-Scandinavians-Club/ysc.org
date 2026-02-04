defmodule Ysc.EventsTest do
  use Ysc.DataCase

  alias Ysc.Events
  alias Ysc.Events.Ticket
  import Ysc.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "selling fast functionality" do
    test "is_event_selling_fast? returns true when 10+ tickets sold in last 3 days" do
      # Create a user and event
      user = user_fixture()

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event",
          description: "A test event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          published_at: DateTime.utc_now()
        })

      # Create a ticket tier for the tickets
      {:ok, ticket_tier} =
        Events.create_ticket_tier(%{
          name: "General Admission",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      # Create 10 tickets with recent timestamps (within last 3 days)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # 1 day ago
      recent_time = DateTime.add(now, -1, :day)

      # Insert 10 confirmed tickets with ticket_tier_id
      for _i <- 1..10 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: ticket_tier.id,
          status: :confirmed,
          inserted_at: recent_time,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      # Test the function
      assert Events.event_selling_fast?(event.id) == true
    end

    test "is_event_selling_fast? returns false when less than 10 tickets sold in last 3 days" do
      # Create a user and event
      user = user_fixture()

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event 2",
          description: "A test event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          published_at: DateTime.utc_now()
        })

      # Create only 5 tickets with recent timestamps
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # 1 day ago
      recent_time = DateTime.add(now, -1, :day)

      # Insert 5 confirmed tickets
      for _i <- 1..5 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          status: :confirmed,
          inserted_at: recent_time,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      # Test the function
      assert Events.event_selling_fast?(event.id) == false
    end

    test "is_event_selling_fast? returns false when tickets are older than 3 days" do
      # Create a user and event
      user = user_fixture()

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event 3",
          description: "A test event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          published_at: DateTime.utc_now()
        })

      # Create 15 tickets with old timestamps (more than 3 days ago)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # 5 days ago
      old_time = DateTime.add(now, -5, :day)

      # Insert 15 confirmed tickets
      for _i <- 1..15 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          status: :confirmed,
          inserted_at: old_time,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      # Test the function
      assert Events.event_selling_fast?(event.id) == false
    end

    test "count_recent_tickets_sold returns correct count" do
      # Create a user and event
      user = user_fixture()

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event 4",
          description: "A test event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          published_at: DateTime.utc_now()
        })

      # Create tickets with different timestamps
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # 1 day ago
      recent_time = DateTime.add(now, -1, :day)
      # 5 days ago
      old_time = DateTime.add(now, -5, :day)

      # Insert 3 recent confirmed tickets
      for _i <- 1..3 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          status: :confirmed,
          inserted_at: recent_time,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      # Insert 2 old confirmed tickets
      for _i <- 1..2 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          status: :confirmed,
          inserted_at: old_time,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Repo.insert!()
      end

      # Insert 1 pending ticket (should not be counted)
      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        status: :pending,
        inserted_at: recent_time,
        expires_at:
          DateTime.add(
            DateTime.utc_now() |> DateTime.truncate(:second),
            1,
            :day
          )
      }
      |> Repo.insert!()

      # Test the function
      assert Events.count_recent_tickets_sold(event.id) == 3
    end
  end

  describe "event CRUD operations" do
    test "create_event/1 creates an event", %{user: user} do
      attrs = %{
        title: "New Event",
        description: "Event description",
        state: :published,
        organizer_id: user.id,
        start_date: DateTime.add(DateTime.utc_now(), 30, :day),
        published_at: DateTime.utc_now()
      }

      assert {:ok, %Ysc.Events.Event{} = event} = Events.create_event(attrs)
      assert event.title == "New Event"
      assert event.organizer_id == user.id
    end

    test "update_event/2 updates an event", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Original Title",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      assert {:ok, updated} =
               Events.update_event(event, %{title: "Updated Title"})

      assert updated.title == "Updated Title"
    end

    test "delete_event/1 marks event as deleted", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "To Delete",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      assert {:ok, deleted} = Events.delete_event(event)
      assert deleted.state == :deleted
    end
  end

  describe "ticket tier management" do
    test "create_ticket_tier/1 creates a tier", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event with Tiers",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      attrs = %{
        name: "VIP Tier",
        type: :paid,
        price: Money.new(100, :USD),
        quantity: 50,
        event_id: event.id
      }

      assert {:ok, %Ysc.Events.TicketTier{} = tier} =
               Events.create_ticket_tier(attrs)

      assert tier.name == "VIP Tier"
      assert tier.event_id == event.id
    end

    test "update_ticket_tier/2 updates a tier", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Original Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      assert {:ok, updated} =
               Events.update_ticket_tier(tier, %{name: "Updated Tier"})

      assert updated.name == "Updated Tier"
    end

    test "delete_ticket_tier/1 deletes a tier", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "To Delete",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      assert {:ok, _deleted} = Events.delete_ticket_tier(tier)
      assert Events.get_ticket_tier(tier.id) == nil
    end
  end

  describe "ticket counting" do
    test "count_tickets_for_tier/1 returns correct count", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      # Create some tickets
      for _i <- 1..5 do
        %Ysc.Events.Ticket{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          status: :confirmed
        }
        |> Ysc.Repo.insert!()
      end

      count = Events.count_tickets_for_tier(tier.id)
      assert count == 5
    end

    test "count_total_tickets_sold_for_event/1 returns correct count", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      # Create some tickets
      for _i <- 1..3 do
        %Ysc.Events.Ticket{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          status: :confirmed
        }
        |> Ysc.Repo.insert!()
      end

      count = Events.count_total_tickets_sold_for_event(event.id)
      assert count == 3
    end
  end

  describe "event queries" do
    test "get_event/1 returns event by id" do
      {:ok, event} = create_event_fixture()
      found = Events.get_event(event.id)
      assert found.id == event.id
    end

    test "get_event/1 returns nil for non-existent event" do
      refute Events.get_event(Ecto.ULID.generate())
    end

    test "get_event_by_reference!/1 returns event by reference_id" do
      {:ok, event} = create_event_fixture()
      found = Events.get_event_by_reference!(event.reference_id)
      assert found.id == event.id
    end

    test "list_events/1 returns all events" do
      {:ok, event1} = create_event_fixture()
      {:ok, event2} = create_event_fixture()

      events = Events.list_events()
      assert Enum.any?(events, &(&1.id == event1.id))
      assert Enum.any?(events, &(&1.id == event2.id))
    end

    test "list_events_paginated/1 returns paginated events" do
      {:ok, _event1} = create_event_fixture()
      {:ok, _event2} = create_event_fixture()

      params = %{page: 1, page_size: 10}

      # Function returns Flop result which is a tuple {:ok, {events, meta}} or error
      result = Events.list_events_paginated(params)
      assert {:ok, {events, meta}} = result
      assert is_list(events)
      assert meta.current_page == 1
    end

    test "count_published_events/0 returns count of published events" do
      {:ok, _event1} = create_event_fixture(%{state: :published})
      {:ok, _event2} = create_event_fixture(%{state: :draft})

      count = Events.count_published_events()
      assert count >= 1
    end

    test "count_upcoming_events/0 returns count of upcoming events" do
      {:ok, _event1} =
        create_event_fixture(%{
          state: :published,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day)
        })

      count = Events.count_upcoming_events()
      assert count >= 1
    end

    test "has_more_past_events?/1 checks if more past events exist" do
      {:ok, _event1} =
        create_event_fixture(%{
          state: :published,
          start_date: DateTime.add(DateTime.utc_now(), -7, :day)
        })

      result = Events.has_more_past_events?(5)
      assert is_boolean(result)
    end

    test "list_upcoming_events/1 returns upcoming events" do
      {:ok, event} =
        create_event_fixture(%{
          state: :published,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day)
        })

      events = Events.list_upcoming_events(10)
      assert Enum.any?(events, &(&1.id == event.id))
    end

    test "list_past_events/1 returns past events" do
      {:ok, event} =
        create_event_fixture(%{
          state: :published,
          start_date: DateTime.add(DateTime.utc_now(), -7, :day)
        })

      events = Events.list_past_events(10)
      assert Enum.any?(events, &(&1.id == event.id))
    end

    test "list_recent_and_upcoming_events/0 returns recent and upcoming events" do
      {:ok, _event1} =
        create_event_fixture(%{
          state: :published,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day)
        })

      events = Events.list_recent_and_upcoming_events()
      assert is_list(events)
    end
  end

  describe "ticket tier queries" do
    test "list_ticket_tiers_for_event/1 returns tiers for event" do
      {:ok, event} = create_event_fixture()
      {:ok, tier} = create_ticket_tier_fixture(%{event_id: event.id})

      tiers = Events.list_ticket_tiers_for_event(event.id)
      assert Enum.any?(tiers, &(&1.id == tier.id))
    end

    test "get_ticket_tier!/1 returns tier by id" do
      {:ok, tier} = create_ticket_tier_fixture()
      found = Events.get_ticket_tier!(tier.id)
      assert found.id == tier.id
    end

    test "get_ticket_tier/1 returns tier by id" do
      {:ok, tier} = create_ticket_tier_fixture()
      found = Events.get_ticket_tier(tier.id)
      assert found.id == tier.id
    end

    test "get_ticket_tier/1 returns nil for non-existent tier" do
      refute Events.get_ticket_tier(Ecto.ULID.generate())
    end
  end

  describe "ticket queries" do
    test "list_tickets_for_event/1 returns tickets for event" do
      {:ok, event} = create_event_fixture()
      user = user_fixture()
      {:ok, tier} = create_ticket_tier_fixture(%{event_id: event.id})

      ticket =
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id
        })

      tickets = Events.list_tickets_for_event(event.id)
      assert Enum.any?(tickets, &(&1.id == ticket.id))
    end

    test "list_tickets_for_user/1 returns tickets for user" do
      user = user_fixture()
      {:ok, event} = create_event_fixture()
      {:ok, tier} = create_ticket_tier_fixture(%{event_id: event.id})

      ticket =
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id
        })

      tickets = Events.list_tickets_for_user(user.id)
      assert Enum.any?(tickets, &(&1.id == ticket.id))
    end

    test "count_tickets_sold_excluding_donations/1 counts non-donation tickets" do
      {:ok, event} = create_event_fixture()
      user = user_fixture()

      {:ok, tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :paid})

      for _i <- 1..3 do
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id,
          status: :confirmed
        })
      end

      count = Events.count_tickets_sold_excluding_donations(event.id)
      assert count >= 3
    end

    test "list_unique_attendees_for_event/1 returns unique attendees" do
      {:ok, event} = create_event_fixture()
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, tier} = create_ticket_tier_fixture(%{event_id: event.id})

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user1.id,
        ticket_tier_id: tier.id
      })

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user2.id,
        ticket_tier_id: tier.id
      })

      attendees = Events.list_unique_attendees_for_event(event.id)
      assert length(attendees) >= 2
    end
  end

  # Helper functions
  defp create_event_fixture(attrs \\ %{}) do
    user = user_fixture()

    default_attrs = %{
      title: "Test Event #{System.unique_integer()}",
      description: "Test description",
      state: :published,
      organizer_id: user.id,
      start_date: DateTime.add(DateTime.utc_now(), 30, :day),
      published_at: DateTime.utc_now()
    }

    default_attrs
    |> Map.merge(attrs)
    |> Events.create_event()
  end

  defp create_ticket_tier_fixture(attrs \\ %{}) do
    {:ok, event} = create_event_fixture()

    default_attrs = %{
      name: "Test Tier #{System.unique_integer()}",
      type: :paid,
      price: Money.new(50, :USD),
      quantity: 100,
      event_id: event.id
    }

    default_attrs
    |> Map.merge(attrs)
    |> Events.create_ticket_tier()
  end

  defp create_ticket_fixture(attrs) do
    # Extract provided IDs (handle both atom and string keys)
    provided_event_id = attrs[:event_id] || attrs["event_id"]
    provided_user_id = attrs[:user_id] || attrs["user_id"]
    provided_tier_id = attrs[:ticket_tier_id] || attrs["ticket_tier_id"]

    # Use provided event_id or create a new event
    event =
      if provided_event_id do
        Ysc.Repo.get!(Ysc.Events.Event, provided_event_id)
      else
        {:ok, event} = create_event_fixture()
        event
      end

    # Use provided user_id or create a new user
    user =
      if provided_user_id do
        user = Ysc.Repo.get!(Ysc.Accounts.User, provided_user_id)

        # Ensure user has active membership (required for tickets)
        # Use update_all to ensure the change is committed immediately
        Ysc.Repo.update_all(
          from(u in Ysc.Accounts.User, where: u.id == ^user.id),
          set: [
            lifetime_membership_awarded_at:
              DateTime.truncate(DateTime.utc_now(), :second)
          ]
        )

        # Reload to get the updated user
        Ysc.Repo.get!(Ysc.Accounts.User, provided_user_id)
      else
        user = user_fixture()

        # Ensure user has active membership (required for tickets)
        # Use update_all to ensure the change is committed immediately
        Ysc.Repo.update_all(
          from(u in Ysc.Accounts.User, where: u.id == ^user.id),
          set: [
            lifetime_membership_awarded_at:
              DateTime.truncate(DateTime.utc_now(), :second)
          ]
        )

        # Reload to get the updated user
        Ysc.Repo.get!(Ysc.Accounts.User, user.id)
      end

    # Use provided ticket_tier_id or create a new tier
    tier =
      if provided_tier_id do
        Ysc.Repo.get!(Ysc.Events.TicketTier, provided_tier_id)
      else
        {:ok, tier} = create_ticket_tier_fixture(%{event_id: event.id})
        tier
      end

    default_attrs = %{
      event_id: event.id,
      user_id: user.id,
      ticket_tier_id: tier.id,
      status: :confirmed,
      expires_at: DateTime.add(DateTime.utc_now(), 30, :day)
    }

    {:ok, ticket} =
      default_attrs
      |> Map.merge(attrs)
      |> Events.create_ticket()

    ticket
  end

  describe "schedule_event/2" do
    test "schedules event for future publication", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Scheduled Event",
          description: "Description",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      publish_at = DateTime.add(DateTime.utc_now(), 1, :day)

      assert {:ok, scheduled} = Events.schedule_event(event, publish_at)
      assert scheduled.publish_at != nil
    end

    test "schedules event with string datetime", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Scheduled Event String",
          description: "Description",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      publish_at =
        DateTime.add(DateTime.utc_now(), 1, :day) |> DateTime.to_iso8601()

      assert {:ok, scheduled} = Events.schedule_event(event, publish_at)
      assert scheduled.publish_at != nil
    end
  end

  describe "get_all_authors/0" do
    test "returns all unique event authors", %{user: user} do
      {:ok, _event} =
        Events.create_event(%{
          title: "Author Test Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      authors = Events.get_all_authors()
      # Function returns list of tuples {name, id}
      assert is_list(authors)
      assert Enum.any?(authors, fn {_name, id} -> id == user.id end)
    end
  end

  describe "get_upcoming_events_with_ticket_tier_counts/0" do
    test "returns upcoming events with ticket tier counts", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Upcoming Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, _tier} =
        Events.create_ticket_tier(%{
          name: "Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      events = Events.get_upcoming_events_with_ticket_tier_counts()
      assert is_list(events)
      # Function returns list of maps with :event and :ticket_tiers keys
      assert Enum.any?(events, fn event_map ->
               event_map.event.id == event.id
             end)
    end
  end

  describe "list_tickets_for_export/1" do
    test "returns tickets for export", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Export Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      for _i <- 1..3 do
        %Ysc.Events.Ticket{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          status: :confirmed
        }
        |> Ysc.Repo.insert!()
      end

      tickets = Events.list_tickets_for_export(event.id)
      assert is_list(tickets)
      assert length(tickets) >= 3
    end
  end

  describe "get_ticket_purchase_summary/1" do
    test "returns ticket purchase summary", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Summary Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      for _i <- 1..2 do
        %Ysc.Events.Ticket{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          status: :confirmed
        }
        |> Ysc.Repo.insert!()
      end

      summary = Events.get_ticket_purchase_summary(event.id)
      # Function returns a list of purchase summaries, not a single map
      assert is_list(summary)
      assert length(summary) == 1
      purchase = Enum.at(summary, 0)
      assert Map.has_key?(purchase, :ticket_count)
      assert Map.has_key?(purchase, :total_amount)
    end
  end
end
