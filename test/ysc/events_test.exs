defmodule Ysc.EventsTest do
  use Ysc.DataCase, async: false

  alias Ysc.Agendas
  alias Ysc.Events
  alias Ysc.Events.{Event, EventPricingCache, FaqQuestion, Ticket, TicketTier}
  alias Ysc.Ledgers
  alias Ysc.Repo
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

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

    test "count_recent_tickets_sold returns correct count excluding donations" do
      user = user_fixture()

      {:ok, event} =
        Events.create_event(%{
          title: "Test Event 4",
          description: "A test event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, paid_tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :paid})

      {:ok, donation_tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :donation})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      recent_time = DateTime.add(now, -1, :day)
      old_time = DateTime.add(now, -5, :day)

      expires_at = DateTime.add(now, 1, :day)

      for _i <- 1..3 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: paid_tier.id,
          status: :confirmed,
          inserted_at: recent_time,
          expires_at: expires_at
        }
        |> Repo.insert!()
      end

      for _i <- 1..2 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: paid_tier.id,
          status: :confirmed,
          inserted_at: old_time,
          expires_at: expires_at
        }
        |> Repo.insert!()
      end

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: donation_tier.id,
        status: :confirmed,
        inserted_at: recent_time,
        expires_at: expires_at
      }
      |> Repo.insert!()

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: paid_tier.id,
        status: :pending,
        inserted_at: recent_time,
        expires_at: expires_at
      }
      |> Repo.insert!()

      assert Events.count_recent_tickets_sold(event.id) == 3
    end
  end

  describe "event changeset with tickets_tbd" do
    test "accepts tickets_tbd as true", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      assert event.tickets_tbd == true
    end

    test "defaults tickets_tbd to false when not set", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      assert event.tickets_tbd == false
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

    test "create_event/1 returns error changeset when required fields are missing",
         %{
           user: user
         } do
      assert {:error, %Ecto.Changeset{} = cs} =
               Events.create_event(%{
                 organizer_id: user.id,
                 start_date: DateTime.add(DateTime.utc_now(), 30, :day),
                 published_at: DateTime.utc_now()
               })

      assert cs.errors[:title]
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

  describe "copy_event/1" do
    test "creates a draft event with copied details and new reference_id", %{
      user: user
    } do
      {:ok, source} =
        Events.create_event(%{
          title: "Original Event",
          description: "Original description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      assert {:ok, copied} = Events.copy_event(source)

      assert copied.state == :draft
      assert copied.title == "Copy of Original Event"
      assert copied.description == source.description
      assert copied.organizer_id == source.organizer_id
      refute copied.reference_id == source.reference_id
      assert copied.published_at == nil
      assert copied.publish_at == nil
      assert copied.id != source.id
    end

    test "copies agendas and agenda items", %{user: user} do
      {:ok, source} =
        Events.create_event(%{
          title: "Event With Agenda",
          description: "Desc",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, agenda} = Agendas.create_agenda(source, %{title: "Day 1"})

      {:ok, _item} =
        Agendas.create_agenda_item(source.id, agenda, %{
          title: "Opening Session"
        })

      source =
        Events.get_event!(source.id) |> Repo.preload(agendas: :agenda_items)

      assert {:ok, copied} = Events.copy_event(source)

      copied =
        Events.get_event!(copied.id) |> Repo.preload(agendas: :agenda_items)

      assert length(copied.agendas) == 1
      assert hd(copied.agendas).title == "Day 1"
      assert hd(copied.agendas).event_id == copied.id
      assert length(hd(copied.agendas).agenda_items) == 1
      assert hd(hd(copied.agendas).agenda_items).title == "Opening Session"
    end

    test "copies ticket tiers but not tickets", %{user: user} do
      {:ok, source} =
        Events.create_event(%{
          title: "Event With Tiers",
          description: "Desc",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, _tier} =
        Events.create_ticket_tier(%{
          name: "General",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 50,
          event_id: source.id
        })

      source = Events.get_event!(source.id) |> Repo.preload(:ticket_tiers)

      assert {:ok, copied} = Events.copy_event(source)

      copied = Events.get_event!(copied.id) |> Repo.preload(:ticket_tiers)
      assert length(copied.ticket_tiers) == 1
      assert hd(copied.ticket_tiers).name == "General"
      assert hd(copied.ticket_tiers).event_id == copied.id

      tickets = Events.list_tickets_for_event(copied.id)
      assert tickets == []
    end

    test "copies FAQ questions", %{user: user} do
      {:ok, source} =
        Events.create_event(%{
          title: "Event With FAQ",
          description: "Desc",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      %FaqQuestion{}
      |> Ecto.Changeset.change(%{
        event_id: source.id,
        question: "When?",
        answer: "Tomorrow."
      })
      |> Repo.insert!()

      source = Events.get_event!(source.id) |> Repo.preload(:faq_questions)

      assert {:ok, copied} = Events.copy_event(source)

      copied = Events.get_event!(copied.id) |> Repo.preload(:faq_questions)
      assert length(copied.faq_questions) == 1
      faq = hd(copied.faq_questions)
      assert faq.question == "When?"
      assert faq.answer == "Tomorrow."
      assert faq.event_id == copied.id
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

    test "create_ticket_tier/1 normalizes 'nil' string in description to nil",
         %{
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

      attrs = %{
        name: "Tier",
        type: :paid,
        price: Money.new(100, :USD),
        quantity: 50,
        event_id: event.id,
        description: "nil"
      }

      assert {:ok, %Ysc.Events.TicketTier{} = tier} =
               Events.create_ticket_tier(attrs)

      assert tier.description == nil
    end
  end

  describe "tickets_tbd functionality" do
    test "set_tickets_tbd/2 sets flag to true", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event TBD",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      assert event.tickets_tbd == false

      assert {:ok, updated} = Events.set_tickets_tbd(event, true)
      assert updated.tickets_tbd == true
    end

    test "set_tickets_tbd/2 sets flag to false", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event TBD",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      assert {:ok, updated} = Events.set_tickets_tbd(event, false)
      assert updated.tickets_tbd == false
    end

    test "create_ticket_tier/1 auto-clears tickets_tbd flag when first tier is added",
         %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event TBD",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, _} = Events.set_tickets_tbd(event, true)
      event = Events.get_event!(event.id)
      assert event.tickets_tbd == true

      {:ok, _tier} =
        Events.create_ticket_tier(%{
          name: "First Tier",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 50,
          event_id: event.id
        })

      event = Events.get_event!(event.id)
      assert event.tickets_tbd == false
    end

    test "create_ticket_tier/1 does not affect tickets_tbd if already false", %{
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

      assert event.tickets_tbd == false

      {:ok, _tier} =
        Events.create_ticket_tier(%{
          name: "Tier",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 50,
          event_id: event.id
        })

      event = Events.get_event!(event.id)
      assert event.tickets_tbd == false
    end

    test "list_upcoming_events returns pricing_info display_text 'Tickets Coming Soon' when tickets_tbd is true",
         %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event TBD Soon",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      [loaded | _] = Events.list_upcoming_events(10)
      assert loaded.id == event.id
      assert loaded.pricing_info.display_text == "Tickets Coming Soon"
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

    test "get_event_by_reference/1 returns nil for unknown reference_id" do
      assert Events.get_event_by_reference(
               "evt_missing_#{System.unique_integer([:positive])}"
             ) ==
               nil
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

      for event <- events do
        assert %{registrations: registrations, capacity: capacity} =
                 event.capacity_info

        assert is_integer(registrations)
        assert capacity == :unlimited or is_integer(capacity)
      end
    end

    test "list_events_paginated/1 capacity_info registrations exclude donation tickets" do
      user = user_fixture()

      {:ok, event} =
        create_event_fixture(%{
          title: "Capacity batch #{System.unique_integer()}",
          max_attendees: 50,
          organizer_id: user.id
        })

      {:ok, paid_tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :paid})

      {:ok, donation_tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :donation})

      for _ <- 1..2 do
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: paid_tier.id,
          status: :confirmed
        })
      end

      for _ <- 1..4 do
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: donation_tier.id,
          status: :confirmed
        })
      end

      assert {:ok, {events, _meta}} =
               Events.list_events_paginated(%{page: 1, page_size: 50})

      listed = Enum.find(events, &(&1.id == event.id))
      assert listed.capacity_info.registrations == 2
    end

    test "list_events_paginated/2 filters drafts tab" do
      user = user_fixture()

      {:ok, draft} =
        Events.create_event(%{
          title: "Draft only #{System.unique_integer()}",
          description: "D",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      params = %{page: 1, page_size: 20}

      assert {:ok, {rows, _meta}} =
               Events.list_events_paginated(params, tab: :drafts)

      assert Enum.any?(rows, &(&1.id == draft.id))
    end

    test "list_events_paginated/2 filters past tab" do
      user = user_fixture()

      {:ok, past} =
        Events.create_event(%{
          title: "Past event #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.utc_now()
            |> DateTime.add(-2, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      params = %{page: 1, page_size: 20}

      assert {:ok, {rows, _meta}} =
               Events.list_events_paginated(params, tab: :past)

      assert Enum.any?(rows, &(&1.id == past.id))
    end

    test "list_events_paginated/2 filters upcoming tab" do
      user = user_fixture()

      {:ok, upcoming} =
        Events.create_event(%{
          title: "Upcoming tab #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 20, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      params = %{page: 1, page_size: 20}

      assert {:ok, {rows, _meta}} =
               Events.list_events_paginated(params, tab: :upcoming)

      assert Enum.any?(rows, &(&1.id == upcoming.id))
    end

    test "list_events_paginated/2 accepts tab as string and filters drafts" do
      user = user_fixture()

      {:ok, draft} =
        Events.create_event(%{
          title: "Draft str tab #{System.unique_integer()}",
          description: "D",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 40, :day)
        })

      params = %{page: 1, page_size: 20}

      assert {:ok, {rows, _meta}} =
               Events.list_events_paginated(params, tab: "drafts")

      assert Enum.any?(rows, &(&1.id == draft.id))
    end

    test "list_events_paginated/2 filters by date_from and date_to" do
      user = user_fixture()
      day = Date.add(Date.utc_today(), 200)

      {:ok, ev} =
        Events.create_event(%{
          title: "Date filter #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.new!(day, ~T[15:00:00], "Etc/UTC"),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      params = %{page: 1, page_size: 20}
      from_str = Date.to_iso8601(Date.add(day, -1))
      to_str = Date.to_iso8601(Date.add(day, 1))

      assert {:ok, {rows, _meta}} =
               Events.list_events_paginated(params,
                 date_from: from_str,
                 date_to: to_str
               )

      assert Enum.any?(rows, &(&1.id == ev.id))
    end

    test "list_events_paginated/2 with search string opts uses fuzzy search path" do
      user = user_fixture()
      q = "UniqueSearchTitle#{System.unique_integer()}"

      {:ok, ev} =
        Events.create_event(%{
          title: q,
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 50, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      params = %{page: 1, page_size: 20}

      assert {:ok, {rows, _meta}} = Events.list_events_paginated(params, q)

      assert Enum.any?(rows, &(&1.id == ev.id))
    end

    test "publish_event/1 returns missing_start_date when start_date is nil" do
      user = user_fixture()

      blank =
        Repo.insert!(%Ysc.Events.Event{
          title: "Has title",
          reference_id: "EVT-NODATE-#{System.unique_integer([:positive])}",
          state: :draft,
          organizer_id: user.id,
          start_date: nil
        })

      assert Events.publish_event(blank) == {:error, :missing_start_date}
    end

    test "list_upcoming_events_paginated/1 clamps page_size to max 100" do
      {rows, meta} =
        Events.list_upcoming_events_paginated(%{
          "page" => "1",
          "page_size" => "500"
        })

      assert meta.page_size == 100
      assert is_list(rows)
    end

    test "list_events_paginated/2 returns error for invalid Flop params" do
      _event = create_event_fixture()

      assert {:error, %Flop.Meta{errors: errors}} =
               Events.list_events_paginated(%{"limit" => "not_a_number"}, [])

      assert Keyword.has_key?(errors, :limit)
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

    test "non_donation_sold_count_from_tiers/1 excludes donation tier sales" do
      tiers = [
        %{type: :paid, sold_tickets_count: 3},
        %{type: :donation, sold_tickets_count: 5},
        %{"type" => "paid", "sold_tickets_count" => 2}
      ]

      assert Events.non_donation_sold_count_from_tiers(tiers) == 5
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

    test "list_upcoming_confirmed_tickets_for_user/2 excludes past events and non-confirmed tickets" do
      user = user_fixture()

      {:ok, upcoming_event} =
        Events.create_event(%{
          title: "Upcoming",
          description: "Soon",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 3, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, past_event} =
        Events.create_event(%{
          title: "Past",
          description: "Gone",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 5, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, upcoming_tier} =
        create_ticket_tier_fixture(%{event_id: upcoming_event.id})

      {:ok, past_tier} = create_ticket_tier_fixture(%{event_id: past_event.id})

      upcoming_ticket =
        create_ticket_fixture(%{
          event_id: upcoming_event.id,
          user_id: user.id,
          ticket_tier_id: upcoming_tier.id,
          status: :confirmed
        })

      past_ticket =
        create_ticket_fixture(%{
          event_id: past_event.id,
          user_id: user.id,
          ticket_tier_id: past_tier.id,
          status: :confirmed
        })

      past_start =
        DateTime.add(DateTime.utc_now(), -10, :day)
        |> DateTime.truncate(:second)

      {:ok, _} =
        past_event
        |> Ecto.Changeset.change(%{start_date: past_start})
        |> Repo.update()

      _pending_ticket =
        create_ticket_fixture(%{
          event_id: upcoming_event.id,
          user_id: user.id,
          ticket_tier_id: upcoming_tier.id,
          status: :pending
        })

      tickets = Events.list_upcoming_confirmed_tickets_for_user(user.id)
      ids = Enum.map(tickets, & &1.id)

      assert upcoming_ticket.id in ids
      refute past_ticket.id in ids
      assert Enum.all?(tickets, &(&1.status == :confirmed))
    end

    test "list_upcoming_confirmed_tickets_for_user/2 after_now excludes events that already started today" do
      user = user_fixture()

      started_at =
        DateTime.utc_now()
        |> DateTime.add(-30, :minute)
        |> DateTime.truncate(:second)

      start_of_today =
        "America/Los_Angeles"
        |> DateTime.now!()
        |> DateTime.to_date()
        |> DateTime.new!(~T[00:00:00], "America/Los_Angeles")
        |> DateTime.shift_zone!("Etc/UTC")

      if DateTime.compare(started_at, start_of_today) != :gt do
        assert DateTime.now!("America/Los_Angeles").hour == 0
      else
        do_after_now_excludes_started_today_test(user, started_at)
      end
    end

    defp do_after_now_excludes_started_today_test(user, started_at) do
      {:ok, started_event} =
        Events.create_event(%{
          title: "Started Earlier Today",
          description: "Already underway",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 2, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, started_tier} =
        create_ticket_tier_fixture(%{event_id: started_event.id})

      started_ticket =
        create_ticket_fixture(%{
          event_id: started_event.id,
          user_id: user.id,
          ticket_tier_id: started_tier.id,
          status: :confirmed
        })

      {:ok, _started_event} =
        started_event
        |> Ecto.Changeset.change(%{start_date: started_at})
        |> Repo.update()

      default_tickets = Events.list_upcoming_confirmed_tickets_for_user(user.id)
      assert started_ticket.id in Enum.map(default_tickets, & &1.id)

      after_now_tickets =
        Events.list_upcoming_confirmed_tickets_for_user(user.id,
          after_now: true
        )

      refute started_ticket.id in Enum.map(after_now_tickets, & &1.id)
    end

    test "list_upcoming_confirmed_tickets_for_user/2 event_limit with after_now only counts future events" do
      user = user_fixture()

      started_at =
        DateTime.utc_now()
        |> DateTime.add(-30, :minute)
        |> DateTime.truncate(:second)

      start_of_today =
        "America/Los_Angeles"
        |> DateTime.now!()
        |> DateTime.to_date()
        |> DateTime.new!(~T[00:00:00], "America/Los_Angeles")
        |> DateTime.shift_zone!("Etc/UTC")

      if DateTime.compare(started_at, start_of_today) != :gt do
        assert DateTime.now!("America/Los_Angeles").hour == 0
      else
        do_event_limit_after_now_test(user, started_at)
      end
    end

    defp do_event_limit_after_now_test(user, started_at) do
      {:ok, started_event} =
        Events.create_event(%{
          title: "Started Earlier Today Limit",
          description: "Already underway",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 2, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, started_tier} =
        create_ticket_tier_fixture(%{event_id: started_event.id})

      create_ticket_fixture(%{
        event_id: started_event.id,
        user_id: user.id,
        ticket_tier_id: started_tier.id,
        status: :confirmed
      })

      {:ok, started_event} =
        started_event
        |> Ecto.Changeset.change(%{start_date: started_at})
        |> Repo.update()

      future_event_ids =
        for idx <- 1..2 do
          {:ok, event} =
            Events.create_event(%{
              title: "Future #{idx}",
              description: "Soon",
              state: :published,
              organizer_id: user.id,
              start_date:
                DateTime.add(DateTime.utc_now(), idx, :day)
                |> DateTime.truncate(:second),
              published_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

          {:ok, tier} = create_ticket_tier_fixture(%{event_id: event.id})

          create_ticket_fixture(%{
            event_id: event.id,
            user_id: user.id,
            ticket_tier_id: tier.id,
            status: :confirmed
          })

          event.id
        end

      tickets =
        Events.list_upcoming_confirmed_tickets_for_user(user.id,
          after_now: true,
          event_limit: 2
        )

      returned_event_ids = tickets |> Enum.map(& &1.event.id) |> Enum.uniq()

      assert length(returned_event_ids) == 2
      assert started_event.id not in returned_event_ids
      assert returned_event_ids == future_event_ids
    end

    test "list_upcoming_confirmed_tickets_for_user/2 limits distinct events with event_limit" do
      user = user_fixture()

      event_ids =
        for idx <- 1..4 do
          {:ok, event} =
            Events.create_event(%{
              title: "Upcoming #{idx}",
              description: "Soon",
              state: :published,
              organizer_id: user.id,
              start_date:
                DateTime.add(DateTime.utc_now(), idx, :day)
                |> DateTime.truncate(:second),
              published_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

          {:ok, tier} = create_ticket_tier_fixture(%{event_id: event.id})

          create_ticket_fixture(%{
            event_id: event.id,
            user_id: user.id,
            ticket_tier_id: tier.id,
            status: :confirmed
          })

          event.id
        end

      tickets =
        Events.list_upcoming_confirmed_tickets_for_user(user.id, event_limit: 2)

      returned_event_ids = tickets |> Enum.map(& &1.event.id) |> Enum.uniq()

      assert length(returned_event_ids) == 2
      assert returned_event_ids == Enum.take(event_ids, 2)
    end

    test "list_events_by_ids/2 returns events in id order" do
      user = user_fixture()
      event_a = event_fixture(%{organizer_id: user.id})
      event_b = event_fixture(%{organizer_id: user.id})

      events =
        Events.list_events_by_ids([event_b.id, event_a.id],
          preloads: [:cover_image]
        )

      assert Enum.map(events, & &1.id) == [event_b.id, event_a.id]
    end

    test "count_tickets_sold_excluding_donations/1 counts non-donation tickets" do
      {:ok, event} = create_event_fixture()
      user = user_fixture()

      {:ok, tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :paid})

      {:ok, donation_tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :donation})

      for _i <- 1..3 do
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id,
          status: :confirmed
        })
      end

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: donation_tier.id,
        status: :confirmed
      })

      assert Events.count_tickets_sold_excluding_donations(event.id) == 3
    end

    test "enrich_single_event_with_pricing_from_db ticket_count excludes donations" do
      {:ok, event} = create_event_fixture()
      user = user_fixture()

      {:ok, paid_tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :paid})

      {:ok, donation_tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :donation})

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: paid_tier.id,
        status: :confirmed
      })

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: donation_tier.id,
        status: :confirmed
      })

      enriched = Events.enrich_single_event_with_pricing_from_db(event)
      assert enriched.ticket_count == 1
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

    test "get_ticket_counts_per_user/1 returns map of user_id to ticket count" do
      {:ok, event} = create_event_fixture()
      user = user_fixture()
      {:ok, tier} = create_ticket_tier_fixture(%{event_id: event.id})

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id
      })

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id
      })

      counts = Events.get_ticket_counts_per_user(event.id)
      assert Map.get(counts, user.id) == 2
    end

    test "attendee_ticket_data_for_event/1 returns sold count, buyers, and per-user counts" do
      {:ok, event} = create_event_fixture()
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :paid})

      {:ok, donation_tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :donation})

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user1.id,
        ticket_tier_id: tier.id,
        status: :confirmed
      })

      for _ <- 1..2 do
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user2.id,
          ticket_tier_id: tier.id,
          status: :confirmed
        })
      end

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user1.id,
        ticket_tier_id: donation_tier.id,
        status: :confirmed
      })

      data = Events.attendee_ticket_data_for_event(event.id)

      assert data.sold_count == 3
      assert Map.get(data.ticket_counts, user1.id) == 1
      assert Map.get(data.ticket_counts, user2.id) == 2
      assert Enum.map(data.ticket_buyers, & &1.id) == [user1.id, user2.id]
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

    test "aggregates sold_tickets_count per tier for the dashboard query", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Sold count event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 10,
          event_id: event.id
        })

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        ticket_tier_id: tier.id,
        user_id: user.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      rows = Events.get_upcoming_events_with_ticket_tier_counts()
      row = Enum.find(rows, fn %{event: e} -> e.id == event.id end)
      assert row
      tier_row = Enum.find(row.ticket_tiers, fn t -> t.id == tier.id end)
      assert tier_row.sold_tickets_count == 1
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

  describe "get_event_sales_stats/1" do
    test "sums revenue per tier net of discounts, and excludes donation tiers",
         %{user: user} do
      {:ok, event} = create_event_fixture()

      {:ok, paid_tier} =
        create_ticket_tier_fixture(%{
          event_id: event.id,
          name: "VIP",
          type: :paid,
          price: Money.new(100, :USD)
        })

      {:ok, donation_tier} =
        create_ticket_tier_fixture(%{event_id: event.id, type: :donation})

      expires_at =
        DateTime.add(DateTime.utc_now(), 30, :day) |> DateTime.truncate(:second)

      # Two full-price VIP tickets.
      for _i <- 1..2 do
        %Ticket{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: paid_tier.id,
          status: :confirmed,
          expires_at: expires_at
        }
        |> Repo.insert!()
      end

      # One discounted VIP ticket.
      %Ticket{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: paid_tier.id,
        status: :confirmed,
        discount_amount: Money.new(20, :USD),
        expires_at: expires_at
      }
      |> Repo.insert!()

      # A pending (not confirmed) ticket should not count.
      %Ticket{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: paid_tier.id,
        status: :pending,
        expires_at: expires_at
      }
      |> Repo.insert!()

      # Donation tickets have no fixed price and must not crash/appear here.
      %Ticket{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: donation_tier.id,
        status: :confirmed,
        expires_at: expires_at
      }
      |> Repo.insert!()

      stats = Events.get_event_sales_stats(event.id)

      assert stats.total_tickets_sold == 3
      assert Money.equal?(stats.total_revenue, Money.new(280, :USD))
      assert [tier_row] = stats.by_tier
      assert tier_row.name == "VIP"
      assert tier_row.tickets_sold == 3
      assert Money.equal?(tier_row.revenue, Money.new(280, :USD))
    end

    test "returns zero totals and empty by_tier for an event with no confirmed tickets" do
      {:ok, event} = create_event_fixture()
      stats = Events.get_event_sales_stats(event.id)

      assert stats.by_tier == []
      assert stats.total_tickets_sold == 0
      assert Money.equal?(stats.total_revenue, Money.new(0, :USD))
    end
  end

  describe "get_event_sales_over_time/1" do
    test "buckets confirmed ticket revenue by day and excludes donation tiers",
         %{user: user} do
      {:ok, event} = create_event_fixture()

      {:ok, tier} =
        create_ticket_tier_fixture(%{
          event_id: event.id,
          type: :paid,
          price: Money.new(50, :USD)
        })

      expires_at =
        DateTime.add(DateTime.utc_now(), 30, :day) |> DateTime.truncate(:second)

      day1 =
        DateTime.utc_now()
        |> DateTime.add(-2, :day)
        |> DateTime.truncate(:second)

      day2 =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      for _i <- 1..2 do
        %Ticket{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id,
          status: :confirmed,
          inserted_at: day1,
          expires_at: expires_at
        }
        |> Repo.insert!()
      end

      %Ticket{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        inserted_at: day2,
        expires_at: expires_at
      }
      |> Repo.insert!()

      points = Events.get_event_sales_over_time(event.id)
      dates = Enum.map(points, & &1.date)

      assert DateTime.to_date(day1) in dates
      assert DateTime.to_date(day2) in dates

      day1_point = Enum.find(points, &(&1.date == DateTime.to_date(day1)))
      assert day1_point.tickets_sold == 2
      assert Money.equal?(day1_point.revenue, Money.new(100, :USD))

      day2_point = Enum.find(points, &(&1.date == DateTime.to_date(day2)))
      assert day2_point.tickets_sold == 1
      assert Money.equal?(day2_point.revenue, Money.new(50, :USD))
    end

    test "returns an empty list for an event with no confirmed tickets and no sale window" do
      {:ok, event} = create_event_fixture()
      assert Events.get_event_sales_over_time(event.id) == []
    end
  end

  describe "get_event_ticket_sale_window/1" do
    test "returns the earliest start_date and latest end_date across tiers" do
      {:ok, event} = create_event_fixture()

      start1 =
        DateTime.add(DateTime.utc_now(), -10, :day)
        |> DateTime.truncate(:second)

      end1 =
        DateTime.add(DateTime.utc_now(), 5, :day) |> DateTime.truncate(:second)

      start2 =
        DateTime.add(DateTime.utc_now(), -5, :day) |> DateTime.truncate(:second)

      end2 =
        DateTime.add(DateTime.utc_now(), 20, :day) |> DateTime.truncate(:second)

      {:ok, _tier1} =
        create_ticket_tier_fixture(%{
          event_id: event.id,
          start_date: start1,
          end_date: end1
        })

      {:ok, _tier2} =
        create_ticket_tier_fixture(%{
          event_id: event.id,
          start_date: start2,
          end_date: end2
        })

      window = Events.get_event_ticket_sale_window(event.id)

      assert DateTime.compare(window.start_date, start1) == :eq
      assert DateTime.compare(window.end_date, end2) == :eq
    end

    test "returns nil start/end when no tiers set a sale window" do
      {:ok, event} = create_event_fixture()
      {:ok, _tier} = create_ticket_tier_fixture(%{event_id: event.id})

      assert Events.get_event_ticket_sale_window(event.id) == %{
               start_date: nil,
               end_date: nil
             }
    end
  end

  describe "get_event_stripe_fees_total/1" do
    test "sums stripe fees only for confirmed tickets with a payment", %{
      user: user
    } do
      {:ok, event} = create_event_fixture()
      {:ok, tier} = create_ticket_tier_fixture(%{event_id: event.id})

      Ledgers.ensure_basic_accounts()
      stripe_fees_account = Ledgers.get_account_by_name("stripe_fees")

      [payment] = Ysc.LedgersFixtures.payment_rows!(user.id, 1)

      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: stripe_fees_account.id,
          payment_id: payment.id,
          amount: Money.new(320, :USD),
          debit_credit: :debit,
          description: "fee"
        })

      expires_at =
        DateTime.add(DateTime.utc_now(), 30, :day) |> DateTime.truncate(:second)

      # Confirmed ticket linked to the payment: counts.
      %Ticket{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        payment_id: payment.id,
        expires_at: expires_at
      }
      |> Repo.insert!()

      # Confirmed ticket with no payment: ignored.
      %Ticket{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        expires_at: expires_at
      }
      |> Repo.insert!()

      assert Money.equal?(
               Events.get_event_stripe_fees_total(event.id),
               Money.new(320, :USD)
             )
    end

    test "returns zero for an event with no confirmed ticket payments" do
      {:ok, event} = create_event_fixture()

      assert Money.equal?(
               Events.get_event_stripe_fees_total(event.id),
               Money.new(0, :USD)
             )
    end
  end

  describe "get_event_donations_total/1" do
    test "delegates to the donation_revenue ledger total for the event" do
      {:ok, event} = create_event_fixture()

      Ledgers.ensure_basic_accounts()
      donation_account = Ledgers.get_account_by_name("donation_revenue")

      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: donation_account.id,
          amount: Money.new(75, :USD),
          debit_credit: :credit,
          related_entity_type: :donation,
          related_entity_id: event.id,
          description: "Donation"
        })

      assert Money.equal?(
               Events.get_event_donations_total(event.id),
               Money.new(75, :USD)
             )
    end

    test "returns zero for an event with no donations" do
      {:ok, event} = create_event_fixture()

      assert Money.equal?(
               Events.get_event_donations_total(event.id),
               Money.new(0, :USD)
             )
    end
  end

  describe "event partiful_link validation" do
    test "accepts valid partiful.com URL", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Partiful Event",
          description: "Test",
          state: :draft,
          organizer_id: user.id
        })

      {:ok, updated} =
        Events.update_event(event, %{
          "partiful_link" =>
            "https://partiful.com/e/g1hU5HXmUnfJwxpW8u8M?c=fLU6roGc"
        })

      assert updated.partiful_link ==
               "https://partiful.com/e/g1hU5HXmUnfJwxpW8u8M?c=fLU6roGc"
    end

    test "trims leading and trailing whitespace from partiful_link", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Partiful Event",
          description: "Test",
          state: :draft,
          organizer_id: user.id
        })

      {:ok, updated} =
        Events.update_event(event, %{
          "partiful_link" => "  https://partiful.com/e/abc123  "
        })

      assert updated.partiful_link == "https://partiful.com/e/abc123"
    end

    test "rejects non-partiful.com URL", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Test",
          state: :draft,
          organizer_id: user.id
        })

      {:error, changeset} =
        Events.update_event(event, %{
          "partiful_link" => "https://evil.com/phishing"
        })

      assert %{partiful_link: ["must be a partiful.com URL"]} =
               errors_on(changeset)
    end

    test "rejects invalid URL", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Test",
          state: :draft,
          organizer_id: user.id
        })

      {:error, changeset} =
        Events.update_event(event, %{"partiful_link" => "not-a-url"})

      assert %{partiful_link: ["must be a valid URL"]} = errors_on(changeset)
    end

    test "allows nil and empty partiful_link", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Test",
          state: :draft,
          organizer_id: user.id
        })

      {:ok, updated} = Events.update_event(event, %{"partiful_link" => ""})
      assert updated.partiful_link == nil
    end
  end

  describe "event description HTML stripping" do
    test "strips HTML tags from description on create", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "HTML Test Event",
          description: "<div>We had <strong>great</strong> weather</div>",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert event.description == "We had great weather"
    end

    test "strips HTML tags from description on update", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "HTML Test Event",
          description: "Plain description",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, updated} =
        Events.update_event(event, %{
          description:
            "<p>Updated <em>description</em> with <a href=\"#\">a link</a></p>"
        })

      assert updated.description == "Updated description with a link"
    end

    test "preserves plain text description unchanged", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Plain Text Event",
          description: "A simple plain text description",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert event.description == "A simple plain text description"
    end

    test "accepts nil description without error", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "No Description Event",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert event.description == nil
    end

    test "strips HTML entities and nested tags", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Nested HTML Event",
          description:
            "<div>We had stunning weather and a nice turnout for the 3rd annual Brewery Crawl. The Rake &amp; Admiral Maltings did a fine job.</div>",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      refute event.description =~ "<"
      refute event.description =~ ">"
      assert event.description =~ "Brewery Crawl"
    end
  end

  describe "event notification subscriptions" do
    test "subscribe_to_event_notification/3 creates a subscription", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      assert {:ok, sub} =
               Events.subscribe_to_event_notification(
                 event,
                 user.id,
                 "save_the_date"
               )

      assert sub.event_id == event.id
      assert sub.user_id == user.id
      assert sub.notification_type == "save_the_date"
    end

    test "subscribe_to_event_notification/3 is idempotent (no error on duplicate)",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      assert {:ok, _} =
               Events.subscribe_to_event_notification(
                 event,
                 user.id,
                 "save_the_date"
               )

      assert {:ok, _} =
               Events.subscribe_to_event_notification(
                 event,
                 user.id,
                 "save_the_date"
               )
    end

    test "subscribed_to_event_notification?/3 returns true when subscribed", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      assert Events.subscribed_to_event_notification?(
               event,
               user.id,
               "save_the_date"
             ) == true
    end

    test "subscribed_to_event_notification?/3 returns false when not subscribed",
         %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      assert Events.subscribed_to_event_notification?(
               event,
               user.id,
               "save_the_date"
             ) == false
    end

    test "subscribed_to_event_notification?/3 returns false for nil user_id", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      assert Events.subscribed_to_event_notification?(
               event,
               nil,
               "save_the_date"
             ) == false
    end

    test "subscribed_to_event_notification?/3 accepts enriched event maps", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      enriched_event =
        event
        |> Map.from_struct()
        |> Map.put(:pricing_info, %{display_text: "Tickets Coming Soon"})

      Events.subscribe_to_event_notification(
        enriched_event,
        user.id,
        "save_the_date"
      )

      assert Events.subscribed_to_event_notification?(
               enriched_event,
               user.id,
               "save_the_date"
             ) == true
    end

    @tag process_caches: true
    test "subscribe_to_event_notification/3 accepts EventPricingCache enriched events",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Cached Notification Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      _tier = ticket_tier_fixture(%{event_id: event.id})
      EventPricingCache.invalidate()

      enriched = EventPricingCache.enrich_event(event)

      assert {:ok, _sub} =
               Events.subscribe_to_event_notification(
                 enriched,
                 user.id,
                 "save_the_date"
               )

      assert Events.subscribed_to_event_notification?(
               enriched,
               user.id,
               "save_the_date"
             ) == true
    end

    test "unsubscribe_from_event_notification/3 removes the subscription", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      assert Events.subscribed_to_event_notification?(
               event,
               user.id,
               "save_the_date"
             ) == true

      Events.unsubscribe_from_event_notification(
        event,
        user.id,
        "save_the_date"
      )

      assert Events.subscribed_to_event_notification?(
               event,
               user.id,
               "save_the_date"
             ) == false
    end

    test "unsubscribe_from_event_notification/3 is safe when no subscription exists",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      assert :ok =
               Events.unsubscribe_from_event_notification(
                 event,
                 user.id,
                 "save_the_date"
               )
    end

    test "get_event_notification_subscribers/2 returns subscribed users", %{
      user: user
    } do
      other_user = user_fixture()

      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      Events.subscribe_to_event_notification(
        event,
        other_user.id,
        "save_the_date"
      )

      subscribers =
        Events.get_event_notification_subscribers(event.id, "save_the_date")

      subscriber_ids = Enum.map(subscribers, & &1.id)

      assert length(subscribers) == 2
      assert user.id in subscriber_ids
      assert other_user.id in subscriber_ids
    end

    test "get_event_notification_subscribers/2 returns only subscribers for the given type",
         %{
           user: user
         } do
      other_user = user_fixture()

      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      # other_user does NOT subscribe
      _ = other_user

      subscribers =
        Events.get_event_notification_subscribers(event.id, "save_the_date")

      assert length(subscribers) == 1
      assert hd(subscribers).id == user.id
    end

    test "delete_event_notification_subscriptions/2 removes all subscriptions for an event + type",
         %{user: user} do
      other_user = user_fixture()

      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      Events.subscribe_to_event_notification(
        event,
        other_user.id,
        "save_the_date"
      )

      Events.delete_event_notification_subscriptions(event.id, "save_the_date")

      assert Events.get_event_notification_subscribers(
               event.id,
               "save_the_date"
             ) == []
    end

    test "set_tickets_tbd/2 schedules save-the-date worker when clearing tbd flag",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now(),
          tickets_tbd: true
        })

      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      {:ok, updated} = Events.set_tickets_tbd(event, false)
      assert updated.tickets_tbd == false

      # With Oban :inline mode the worker runs immediately, which deletes subscriptions
      assert Events.get_event_notification_subscribers(
               event.id,
               "save_the_date"
             ) == []
    end

    test "set_tickets_tbd/2 does not schedule worker when setting tbd flag to true",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Save the Date Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      Events.subscribe_to_event_notification(event, user.id, "save_the_date")
      {:ok, _} = Events.set_tickets_tbd(event, true)

      # Subscriptions should be untouched — worker was not triggered
      assert length(
               Events.get_event_notification_subscribers(
                 event.id,
                 "save_the_date"
               )
             ) == 1
    end

    test "set_tickets_tbd/2 does not schedule worker when flag was already false",
         %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "No-op Event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      assert event.tickets_tbd == false
      {:ok, _} = Events.set_tickets_tbd(event, false)

      # Subscriptions untouched — no transition occurred
      assert length(
               Events.get_event_notification_subscribers(
                 event.id,
                 "save_the_date"
               )
             ) == 1
    end
  end

  describe "publish, unpublish, cancel, and API helpers" do
    setup %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Pub helpers",
          description: "D",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 14, :day)
        })

      %{event: event}
    end

    test "publish_event promotes draft to published", %{event: event} do
      assert {:ok, published} = Events.publish_event(event)
      assert published.state == :published
      assert published.published_at
    end

    test "publish_event returns invalid_state when not draft or scheduled", %{
      user: user
    } do
      {:ok, live} =
        Events.create_event(%{
          title: "Already out",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 20, :day),
          published_at: DateTime.utc_now()
        })

      assert Events.publish_event(live) == {:error, :invalid_state}
    end

    test "publish_event returns missing_title when title is blank", %{
      user: user
    } do
      blank =
        Repo.insert!(%Ysc.Events.Event{
          title: "",
          reference_id: "EVT-BLANK-#{System.unique_integer([:positive])}",
          state: :draft,
          organizer_id: user.id,
          start_date:
            DateTime.utc_now()
            |> DateTime.add(10, :day)
            |> DateTime.truncate(:second)
        })

      assert Events.publish_event(blank) == {:error, :missing_title}
    end

    test "unpublish_event and cancel_event update state", %{event: event} do
      assert {:ok, published} = Events.publish_event(event)
      assert {:ok, draft} = Events.unpublish_event(published)
      assert draft.state == :draft

      assert {:ok, published2} = Events.publish_event(draft)
      assert {:ok, cancelled} = Events.cancel_event(published2)
      assert cancelled.state == :cancelled
    end

    test "list_upcoming_events_paginated returns meta and events", %{user: user} do
      {:ok, _} =
        Events.create_event(%{
          title: "Paginated upcoming",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {rows, meta} =
        Events.list_upcoming_events_paginated(%{
          "page" => "1",
          "page_size" => "10"
        })

      assert is_list(rows)
      assert meta.page >= 1
      assert meta.total_count >= 1
    end

    test "list_upcoming_events_with_preload loads events", %{user: user} do
      {:ok, _} =
        Events.create_event(%{
          title: "Preload list",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 25, :day),
          published_at: DateTime.utc_now()
        })

      events = Events.list_upcoming_events_with_preload(5, [])
      assert is_list(events)
    end

    test "event_pricing_display_string and event_earliest_tickets_sale_date", %{
      event: event
    } do
      sale_start =
        DateTime.utc_now()
        |> DateTime.add(2, :day)
        |> DateTime.truncate(:second)

      {:ok, _} =
        Events.create_ticket_tier(%{
          event_id: event.id,
          name: "GA",
          type: :paid,
          price: Money.new(1500, :USD),
          quantity: 100,
          start_date: sale_start
        })

      loaded = Events.get_event!(event.id) |> Repo.preload(:ticket_tiers)

      assert is_binary(Events.event_pricing_display_string(loaded))

      assert DateTime.compare(
               Events.event_earliest_tickets_sale_date(loaded),
               sale_start
             ) ==
               :eq
    end

    test "subscribe/0 subscribes to events PubSub topic" do
      assert :ok = Events.subscribe()
    end

    test "registration_required?/1 covers ticket and tier branches" do
      tier = %Ysc.Events.TicketTier{requires_registration: true}
      ticket = %Ysc.Events.Ticket{ticket_tier: tier}
      assert Events.registration_required?(ticket)

      tier2 = %Ysc.Events.TicketTier{requires_registration: false}

      assert Events.registration_required?(%Ysc.Events.Ticket{
               ticket_tier: tier2
             }) ==
               false

      refute Events.registration_required?(Ecto.ULID.generate())
      refute Events.registration_required?(:not_a_ticket)
    end
  end

  describe "list_events_paginated tab and date filter edge cases" do
    test "unknown tab string normalizes to :all so draft events are included" do
      user = user_fixture()

      {:ok, draft} =
        Events.create_event(%{
          title: "Draft invalid tab #{System.unique_integer()}",
          description: "D",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      params = %{page: 1, page_size: 20}

      assert {:ok, {rows, _meta}} =
               Events.list_events_paginated(params, tab: "invalid_tab")

      assert Enum.any?(rows, &(&1.id == draft.id))
    end

    test "invalid date_from and date_to strings are ignored without breaking the query" do
      user = user_fixture()

      {:ok, ev} =
        Events.create_event(%{
          title: "Bad date filter #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 25, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      params = %{page: 1, page_size: 20}

      assert {:ok, {rows, _meta}} =
               Events.list_events_paginated(params,
                 tab: :all,
                 date_from: "not-a-date",
                 date_to: "also-bad"
               )

      assert Enum.any?(rows, &(&1.id == ev.id))
    end
  end

  describe "list_events applies organizer_id filter" do
    test "returns only events for the given organizer", %{user: user} do
      other = user_fixture()

      {:ok, mine} =
        Events.create_event(%{
          title: "Mine #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 20, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, theirs} =
        Events.create_event(%{
          title: "Theirs #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: other.id,
          start_date: DateTime.add(DateTime.utc_now(), 21, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      rows = Events.list_events(%{organizer_id: user.id})

      ids = Enum.map(rows, & &1.id)
      assert mine.id in ids
      refute theirs.id in ids
    end
  end

  describe "list_upcoming_events_paginated parse_page_param" do
    test "coerces page 0 and negative numeric strings to at least 1" do
      _user = user_fixture()

      {_, meta0} =
        Events.list_upcoming_events_paginated(%{
          "page" => "0",
          "page_size" => "10"
        })

      assert meta0.page == 1

      {_, meta_neg} =
        Events.list_upcoming_events_paginated(%{
          "page" => "-3",
          "page_size" => "10"
        })

      assert meta_neg.page == 1
    end

    test "non-integer page values fall back to default page 1" do
      {_, meta} =
        Events.list_upcoming_events_paginated(%{
          "page" => "12abc",
          "page_size" => "10"
        })

      assert meta.page == 1
    end

    test "non-binary non-integer page values fall back to default" do
      {_, meta} =
        Events.list_upcoming_events_paginated(%{
          "page" => 1.5,
          "page_size" => "10"
        })

      assert meta.page == 1
    end
  end

  describe "event_pricing_display_string free and donation tiers" do
    test "shows FREE when only free ticket tiers exist", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Free only #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 18, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, _} =
        Events.create_ticket_tier(%{
          name: "Freebie",
          type: :free,
          quantity: 100,
          event_id: event.id
        })

      loaded = Events.get_event!(event.id) |> Repo.preload(:ticket_tiers)
      assert Events.event_pricing_display_string(loaded) == "Free"
    end

    test "shows From $0.00 when both free and paid tiers exist", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Mixed tiers #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 19, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, _} =
        Events.create_ticket_tier(%{
          name: "Free",
          type: :free,
          quantity: 50,
          event_id: event.id
        })

      {:ok, _} =
        Events.create_ticket_tier(%{
          name: "Paid",
          type: :paid,
          price: Money.new(2500, :USD),
          quantity: 50,
          event_id: event.id
        })

      loaded = Events.get_event!(event.id) |> Repo.preload(:ticket_tiers)
      assert Events.event_pricing_display_string(loaded) == "From $0.00"
    end

    test "shows FREE when only donation tiers exist (no priced paid tiers)", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Donation only #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 22, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, _} =
        Events.create_ticket_tier(%{
          name: "Pay what you want",
          type: :donation,
          quantity: 100,
          event_id: event.id
        })

      loaded = Events.get_event!(event.id) |> Repo.preload(:ticket_tiers)
      assert Events.event_pricing_display_string(loaded) == "Free"
    end

    test "accepts enriched event maps from pricing cache", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Enriched map #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 20, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 50,
          event_id: event.id,
          start_date: DateTime.add(DateTime.utc_now(), 1, :day)
        })

      enriched =
        event
        |> Map.from_struct()
        |> Map.put(:ticket_tiers, [tier])
        |> Map.put(:tickets_tbd, false)

      assert Events.event_pricing_display_string(enriched) == "$25.00"

      assert Events.event_earliest_tickets_sale_date(enriched) ==
               tier.start_date
    end
  end

  describe "schedule_event string formats and validation" do
    test "parses datetime-local string via America/Los_Angeles to UTC", %{
      user: user
    } do
      start_at =
        DateTime.add(DateTime.utc_now(), 30, :day) |> DateTime.truncate(:second)

      {:ok, event} =
        Events.create_event(%{
          title: "Local schedule #{System.unique_integer()}",
          description: "D",
          state: :draft,
          organizer_id: user.id,
          start_date: start_at
        })

      publish_naive =
        DateTime.utc_now()
        |> DateTime.add(5, :day)
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)

      publish_str =
        publish_naive
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      assert {:ok, scheduled} = Events.schedule_event(event, publish_str)
      assert scheduled.state == :scheduled
      assert scheduled.publish_at
    end

    test "raises ArgumentError for unparseable publish_at string", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Bad schedule #{System.unique_integer()}",
          description: "D",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      assert_raise ArgumentError, ~r/Invalid datetime format/, fn ->
        Events.schedule_event(event, "totally-not-a-datetime")
      end
    end

    test "returns error changeset when publish_at is after event start", %{
      user: user
    } do
      start_at =
        DateTime.add(DateTime.utc_now(), 10, :day) |> DateTime.truncate(:second)

      {:ok, event} =
        Events.create_event(%{
          title: "Late publish #{System.unique_integer()}",
          description: "D",
          state: :draft,
          organizer_id: user.id,
          start_date: start_at,
          start_time: ~T[12:00:00]
        })

      late_publish =
        DateTime.add(DateTime.utc_now(), 40, :day) |> DateTime.truncate(:second)

      assert {:error, changeset} = Events.schedule_event(event, late_publish)
      assert %{publish_at: _} = errors_on(changeset)
    end
  end

  describe "create_ticket_tier and copy_event error paths" do
    test "create_ticket_tier/1 returns error changeset when required fields are missing",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Tier errors #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 15, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:error, %Ecto.Changeset{} = cs} =
               Events.create_ticket_tier(%{
                 type: :paid,
                 price: Money.new(100, :USD),
                 quantity: 10,
                 event_id: event.id
               })

      assert cs.errors[:name]
    end

    test "copy_event/1 returns error when copied title exceeds max length", %{
      user: user
    } do
      long_title = String.duplicate("x", 100)

      {:ok, source} =
        Events.create_event(%{
          title: long_title,
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 12, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:error, %Ecto.Changeset{}} = Events.copy_event(source)
    end
  end

  describe "list_events/1 state and title filters" do
    test "filters by draft state", %{user: user} do
      {:ok, draft} =
        Events.create_event(%{
          title: "Draft filter #{System.unique_integer()}",
          description: "D",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 40, :day)
        })

      {:ok, published} =
        Events.create_event(%{
          title: "Pub filter #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 41, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      rows = Events.list_events(%{state: :draft})

      ids = Enum.map(rows, & &1.id)
      assert draft.id in ids
      refute published.id in ids
    end

    test "filters by title substring", %{user: user} do
      marker = "TitleFilter#{System.unique_integer()}"

      {:ok, match_ev} =
        Events.create_event(%{
          title: "ZZZ #{marker} AAA",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 42, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, other} =
        Events.create_event(%{
          title: "Other #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 43, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      rows = Events.list_events(%{title: marker})

      ids = Enum.map(rows, & &1.id)
      assert match_ev.id in ids
      refute other.id in ids
    end
  end

  describe "error paths, pricing edge cases, and ticket detail CRUD" do
    test "update_event/2 returns error changeset when title exceeds max length",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Valid title",
          description: "D",
          state: :draft,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 20, :day)
        })

      assert {:error, %Ecto.Changeset{} = cs} =
               Events.update_event(event, %{title: String.duplicate("x", 101)})

      assert cs.errors[:title]
    end

    test "list_upcoming_events_paginated/1 uses max(page,1) for integer page param" do
      {_, meta} =
        Events.list_upcoming_events_paginated(%{
          "page" => 0,
          "page_size" => 10
        })

      assert meta.page == 1
    end

    test "list_events/1 ignores unknown filter keys (apply_filters fallback)",
         %{
           user: user
         } do
      {:ok, ev} =
        Events.create_event(%{
          title: "Unknown filter #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 44, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      rows =
        Events.list_events(%{organizer_id: user.id, not_a_real_filter: true})

      ids = Enum.map(rows, & &1.id)
      assert ev.id in ids
    end

    test "event_pricing_display_string/1 uses format_price fallback for non-Money tier price" do
      tier = %TicketTier{type: :paid, price: %{amount: Decimal.new(100)}}

      event = %Event{
        tickets_tbd: false,
        ticket_tiers: [tier]
      }

      assert Events.event_pricing_display_string(event) == "$0.00"
    end

    test "list_tickets_for_export/1 returns empty list and hits empty ticket_details map",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "No export tickets #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 45, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert Events.list_tickets_for_export(event.id) == []
    end

    test "list_tickets_for_export/1 attaches ticket_detail for confirmed tickets",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Export details #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 46, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(10, :USD),
          quantity: 10,
          event_id: event.id
        })

      ticket =
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id
        })

      assert {:ok, detail} =
               Events.create_ticket_detail(%{
                 ticket_id: ticket.id,
                 first_name: "Ada",
                 last_name: "Lovelace",
                 email: "ada@example.com"
               })

      [row] = Events.list_tickets_for_export(event.id)
      assert row.ticket_detail.id == detail.id
      assert row.ticket_detail.first_name == "Ada"
    end

    test "get_ticket_purchase_summary/1 uses Money.new(0,:USD) for donation tier with nil price",
         %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Donation summary #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 47, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Donate",
          type: :donation,
          quantity: 100,
          event_id: event.id
        })

      create_ticket_fixture(%{
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id
      })

      [row] = Events.get_ticket_purchase_summary(event.id)
      assert row.total_amount == Money.new(0, :USD)
    end

    test "create_ticket/1 returns error changeset when attrs are invalid", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Bad ticket #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 48, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:error, %Ecto.Changeset{} = cs} =
               Events.create_ticket(%{
                 event_id: event.id,
                 user_id: user.id,
                 status: :confirmed
               })

      assert cs.errors[:ticket_tier_id] || cs.errors[:expires_at]
    end

    test "update_ticket_tier/2 returns error changeset when validation fails",
         %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Tier bad #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 49, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "T",
          type: :paid,
          price: Money.new(5, :USD),
          quantity: 5,
          event_id: event.id
        })

      assert {:error, %Ecto.Changeset{} = cs} =
               Events.update_ticket_tier(tier, %{quantity: -1})

      assert cs.errors[:quantity]
    end

    test "delete_ticket_tier/1 raises ConstraintError when tier is referenced by tickets",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Tier fk #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 50, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(5, :USD),
          quantity: 5,
          event_id: event.id
        })

      _ticket =
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id
        })

      assert_raise Ecto.ConstraintError, fn ->
        Events.delete_ticket_tier(tier)
      end
    end

    test "create_ticket_details/1 rolls back when one row is invalid", %{
      user: user
    } do
      {:ok, event} =
        Events.create_event(%{
          title: "Batch details #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 51, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(5, :USD),
          quantity: 5,
          event_id: event.id
        })

      ticket =
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id
        })

      assert {:error, %Ecto.Changeset{}} =
               Events.create_ticket_details([
                 %{
                   ticket_id: ticket.id,
                   first_name: "A",
                   last_name: "B",
                   email: "bad-email"
                 }
               ])

      refute Events.get_ticket_detail_for_ticket(ticket.id)
    end

    test "create_ticket_detail/1 returns error for invalid email", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Detail email #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 52, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(5, :USD),
          quantity: 5,
          event_id: event.id
        })

      ticket =
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id
        })

      assert {:error, %Ecto.Changeset{} = cs} =
               Events.create_ticket_detail(%{
                 ticket_id: ticket.id,
                 first_name: "A",
                 last_name: "B",
                 email: "not-an-email"
               })

      assert cs.errors[:email]
    end

    test "create_registration/1 and update_registration/2 and delete_registration/1",
         %{
           user: user
         } do
      {:ok, event} =
        Events.create_event(%{
          title: "Reg flow #{System.unique_integer()}",
          description: "D",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 53, :day),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(5, :USD),
          quantity: 5,
          event_id: event.id
        })

      ticket =
        create_ticket_fixture(%{
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id
        })

      assert {:ok, reg} =
               Events.create_registration(%{
                 ticket_id: ticket.id,
                 first_name: "Grace",
                 last_name: "Hopper",
                 email: "grace@example.com"
               })

      assert Events.get_registration_for_ticket(ticket.id).id == reg.id

      assert %{} = Events.list_ticket_details_for_ticket_ids([])

      details_by_id = Events.list_ticket_details_for_ticket_ids([ticket.id])

      assert %Ysc.Events.TicketDetail{id: reg_id} =
               Map.fetch!(details_by_id, ticket.id)

      assert reg_id == reg.id

      assert {:ok, updated} =
               Events.update_registration(reg, %{first_name: "Grace M."})

      assert updated.first_name == "Grace M."

      assert {:ok, _} = Events.delete_registration(updated)
      assert Events.get_ticket_detail_for_ticket(ticket.id) == nil
    end
  end

  describe "list_*_reservations_for_tiers/1" do
    test "batch loads active and expired reservations grouped by tier", %{
      user: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier_a = ticket_tier_fixture(%{event_id: event.id, name: "Tier A"})
      tier_b = ticket_tier_fixture(%{event_id: event.id, name: "Tier B"})
      member = user_fixture()

      future_expiry =
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.add(2, :day)

      past_expiry =
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.add(-1, :hour)

      assert {:ok, active_a} =
               Events.create_ticket_reservation(%{
                 ticket_tier_id: tier_a.id,
                 user_id: member.id,
                 created_by_id: admin.id,
                 quantity: 1,
                 expires_at: future_expiry
               })

      assert {:ok, expired_b} =
               Events.create_ticket_reservation(%{
                 ticket_tier_id: tier_b.id,
                 user_id: member.id,
                 created_by_id: admin.id,
                 quantity: 2,
                 expires_at: future_expiry
               })

      expired_b
      |> Ecto.Changeset.change(%{expires_at: past_expiry})
      |> Repo.update!()

      tier_ids = [tier_a.id, tier_b.id]

      active_by_tier = Events.list_active_reservations_for_tiers(tier_ids)

      expired_by_tier =
        Events.list_expired_active_reservations_for_tiers(tier_ids)

      assert [loaded_a] = Map.fetch!(active_by_tier, tier_a.id)
      assert loaded_a.id == active_a.id
      assert Map.fetch!(active_by_tier, tier_b.id) == []

      assert [loaded_b] = Map.fetch!(expired_by_tier, tier_b.id)
      assert loaded_b.quantity == 2
      assert Map.fetch!(expired_by_tier, tier_a.id) == []
    end

    test "returns empty map for empty tier id list" do
      assert Events.list_active_reservations_for_tiers([]) == %{}
      assert Events.list_expired_active_reservations_for_tiers([]) == %{}
    end
  end

  describe "create_ticket_reservation/1 notification email" do
    test "enqueues EmailNotifier job for the member", %{user: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      member = user_fixture()

      expires_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.add(2, :day)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, reservation} =
                 Events.create_ticket_reservation(%{
                   ticket_tier_id: tier.id,
                   user_id: member.id,
                   created_by_id: admin.id,
                   quantity: 2,
                   expires_at: expires_at,
                   discount_percentage: Decimal.new("10")
                 })

        assert [job] = all_enqueued(worker: YscWeb.Workers.EmailNotifier)
        assert job.queue == "transactional_mail"
        assert job.args["template"] == "ticket_reservation_created"
        assert job.args["recipient"] == member.email
        assert job.args["user_id"] == member.id

        assert job.args["idempotency_key"] ==
                 "ticket_reservation_created_#{reservation.id}"
      end)
    end
  end

  describe "public event page access (#353)" do
    test "get_public_event/1 returns published and cancelled events only" do
      {:ok, published} = create_event_fixture(%{state: :published})
      {:ok, cancelled} = create_event_fixture(%{state: :cancelled})
      {:ok, draft} = create_event_fixture(%{state: :draft, published_at: nil})

      assert %Event{id: id} = Events.get_public_event(published.id)
      assert id == published.id

      assert %Event{id: id} = Events.get_public_event(cancelled.id)
      assert id == cancelled.id

      assert Events.get_public_event(draft.id) == nil
    end

    test "get_public_event/1 returns nil for invalid ULID values" do
      assert Events.get_public_event("images.php") == nil
      assert Events.get_public_event("invalid-id") == nil
    end

    test "get_event_for_page/2 returns nil for invalid ULID values" do
      admin = user_fixture(%{role: :admin})
      volunteer = user_fixture(%{role: :volunteer})

      assert Events.get_event_for_page("images.php", nil) == nil
      assert Events.get_event_for_page("invalid-id", nil) == nil
      assert Events.get_event_for_page("images.php", admin) == nil
      assert Events.get_event_for_page("invalid-id", admin) == nil
      assert Events.get_event_for_page("images.php", volunteer) == nil
      assert Events.get_event_for_page("invalid-id", volunteer) == nil
    end

    test "get_event_for_page/2 hides draft events from members but allows staff preview" do
      {:ok, draft} =
        create_event_fixture(%{
          title: "Draft preview event",
          state: :draft,
          published_at: nil
        })

      member = user_fixture(%{state: :active})
      admin = user_fixture(%{role: :admin})
      volunteer = user_fixture(%{role: :volunteer})

      assert Events.get_event_for_page(draft.id, member) == nil
      assert %Event{id: id} = Events.get_event_for_page(draft.id, admin)
      assert id == draft.id
      assert %Event{id: id} = Events.get_event_for_page(draft.id, volunteer)
      assert id == draft.id
    end

    test "get_event_for_page_by_reference/2 allows staff to preview scheduled events" do
      {:ok, scheduled} =
        create_event_fixture(%{
          title: "Scheduled preview",
          state: :scheduled,
          published_at: nil
        })

      member = user_fixture(%{state: :active})
      admin = user_fixture(%{role: :admin})

      assert Events.get_event_for_page_by_reference(
               scheduled.reference_id,
               member
             ) ==
               nil

      assert %Event{id: id} =
               Events.get_event_for_page_by_reference(
                 scheduled.reference_id,
                 admin
               )

      assert id == scheduled.id
    end
  end
end
