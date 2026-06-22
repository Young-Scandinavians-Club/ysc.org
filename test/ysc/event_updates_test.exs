defmodule Ysc.EventUpdatesTest do
  use Ysc.DataCase, async: false

  alias Ysc.Events
  alias Ysc.Events.{Ticket, TicketDetail}
  alias Ysc.Repo
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()
    event = event_fixture(%{organizer_id: user.id})
    %{user: user, event: event}
  end

  describe "create_event_update/2" do
    test "creates an event update with valid attrs", %{event: event, user: user} do
      attrs = %{
        title: "Venue Change",
        raw_body: "<p>The venue has changed to Central Park</p>",
        rendered_body: "<p>The venue has changed to Central Park</p>",
        show_on_event_page: true,
        sent_by_id: user.id
      }

      assert {:ok, update} = Events.create_event_update(event, attrs)
      assert update.title == "Venue Change"
      assert update.raw_body == "<p>The venue has changed to Central Park</p>"
      assert update.show_on_event_page == true
      assert update.event_id == event.id
      assert update.sent_by_id == user.id
      assert is_nil(update.sent_at)
    end

    test "fails without a body", %{event: event, user: user} do
      attrs = %{title: "No Body", sent_by_id: user.id}
      assert {:error, changeset} = Events.create_event_update(event, attrs)
      assert %{raw_body: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_event_updates/1" do
    test "returns all updates for the event", %{event: event, user: user} do
      {:ok, _first} =
        Events.create_event_update(event, %{
          title: "First",
          raw_body: "first body",
          rendered_body: "first body",
          sent_by_id: user.id
        })

      {:ok, _second} =
        Events.create_event_update(event, %{
          title: "Second",
          raw_body: "second body",
          rendered_body: "second body",
          sent_by_id: user.id
        })

      updates = Events.list_event_updates(event.id)
      assert length(updates) == 2
      titles = Enum.map(updates, & &1.title) |> Enum.sort()
      assert titles == ["First", "Second"]
    end

    test "returns empty list for event with no updates", %{event: _event} do
      other_event = event_fixture()
      assert Events.list_event_updates(other_event.id) == []
    end
  end

  describe "list_visible_event_updates/1" do
    test "returns only updates with show_on_event_page true", %{
      event: event,
      user: user
    } do
      {:ok, _hidden} =
        Events.create_event_update(event, %{
          title: "Hidden",
          raw_body: "hidden",
          rendered_body: "hidden",
          show_on_event_page: false,
          sent_by_id: user.id
        })

      {:ok, visible} =
        Events.create_event_update(event, %{
          title: "Visible",
          raw_body: "visible",
          rendered_body: "visible",
          show_on_event_page: true,
          sent_by_id: user.id
        })

      updates = Events.list_visible_event_updates(event.id)
      assert length(updates) == 1
      assert hd(updates).id == visible.id
    end
  end

  describe "list_event_update_recipients/1" do
    test "returns ticket purchaser emails", %{event: event, user: user} do
      tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      recipients = Events.list_event_update_recipients(event.id)
      assert length(recipients) == 1
      assert hd(recipients).email == user.email
    end

    test "includes registrant emails from ticket details", %{
      event: event,
      user: user
    } do
      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :paid,
          requires_registration: true
        })

      ticket =
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id,
          status: :confirmed,
          expires_at:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      %TicketDetail{
        id: Ecto.ULID.generate(),
        ticket_id: ticket.id,
        first_name: "Guest",
        last_name: "User",
        email: "guest@example.com"
      }
      |> Repo.insert!()

      recipients = Events.list_event_update_recipients(event.id)
      emails = Enum.map(recipients, & &1.email) |> Enum.sort()
      assert "guest@example.com" in emails
      assert user.email in emails
    end

    test "deduplicates emails case-insensitively", %{event: event, user: user} do
      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :paid,
          requires_registration: true
        })

      ticket =
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id,
          status: :confirmed,
          expires_at:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      %TicketDetail{
        id: Ecto.ULID.generate(),
        ticket_id: ticket.id,
        first_name: "Same",
        last_name: "User",
        email: String.upcase(user.email)
      }
      |> Repo.insert!()

      recipients = Events.list_event_update_recipients(event.id)
      assert length(recipients) == 1
    end

    test "excludes donation tier tickets", %{event: event, user: user} do
      tier = ticket_tier_fixture(%{event_id: event.id, type: :donation})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      recipients = Events.list_event_update_recipients(event.id)
      assert recipients == []
    end

    test "excludes non-confirmed tickets", %{event: event, user: user} do
      tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        ticket_tier_id: tier.id,
        status: :pending,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      recipients = Events.list_event_update_recipients(event.id)
      assert recipients == []
    end

    test "returns empty for event with no tickets" do
      event = event_fixture()
      assert Events.list_event_update_recipients(event.id) == []
    end
  end

  describe "count_ticket_tiers_for_event/1" do
    test "returns tier count for the event", %{event: event} do
      ticket_tier_fixture(%{event_id: event.id, name: "Tier A"})
      ticket_tier_fixture(%{event_id: event.id, name: "Tier B"})

      other_event = event_fixture()
      ticket_tier_fixture(%{event_id: other_event.id, name: "Other"})

      assert Events.count_ticket_tiers_for_event(event.id) == 2
    end

    test "returns 0 when event has no tiers" do
      event = event_fixture()
      assert Events.count_ticket_tiers_for_event(event.id) == 0
    end
  end

  describe "count_event_update_recipients/1" do
    test "matches list_event_update_recipients/1 length", %{
      event: event,
      user: user
    } do
      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :paid,
          requires_registration: true
        })

      ticket =
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id,
          status: :confirmed,
          expires_at:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      %TicketDetail{
        id: Ecto.ULID.generate(),
        ticket_id: ticket.id,
        first_name: "Guest",
        last_name: "User",
        email: "guest@example.com"
      }
      |> Repo.insert!()

      assert Events.count_event_update_recipients(event.id) ==
               length(Events.list_event_update_recipients(event.id))
    end

    test "returns 0 for event with no tickets" do
      event = event_fixture()
      assert Events.count_event_update_recipients(event.id) == 0
    end
  end

  describe "event_update_recipient_email?/2" do
    test "matches list_event_update_recipients/1 membership", %{
      event: event,
      user: user
    } do
      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :paid,
          requires_registration: true
        })

      ticket =
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier.id,
          status: :confirmed,
          expires_at:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      %TicketDetail{
        id: Ecto.ULID.generate(),
        ticket_id: ticket.id,
        first_name: "Guest",
        last_name: "User",
        email: "guest@example.com"
      }
      |> Repo.insert!()

      recipients = Events.list_event_update_recipients(event.id)

      for recipient <- recipients do
        assert Events.event_update_recipient_email?(event.id, recipient.email)
      end

      refute Events.event_update_recipient_email?(
               event.id,
               "stranger@example.com"
             )
    end

    test "returns false for donation-only ticket holders", %{event: event} do
      donor = user_fixture()

      donation_tier =
        ticket_tier_fixture(%{event_id: event.id, type: :donation})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: donor.id,
        ticket_tier_id: donation_tier.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      refute Events.event_update_recipient_email?(event.id, donor.email)
    end

    test "returns false for blank email" do
      event = event_fixture()
      refute Events.event_update_recipient_email?(event.id, "")
      refute Events.event_update_recipient_email?(event.id, nil)
    end
  end

  describe "mark_event_notification_sent/2" do
    test "sets notification_sent_at and notification_recipient_count", %{
      event: event
    } do
      assert {:ok, updated} = Events.mark_event_notification_sent(event, 25)
      assert updated.notification_sent_at != nil
      assert updated.notification_recipient_count == 25
    end
  end

  describe "mark_event_update_sent/2" do
    test "sets sent_at and recipient_count", %{event: event, user: user} do
      {:ok, update} =
        Events.create_event_update(event, %{
          title: "Test",
          raw_body: "body",
          rendered_body: "body",
          sent_by_id: user.id
        })

      assert {:ok, marked} = Events.mark_event_update_sent(update, 42)
      assert marked.recipient_count == 42
      assert marked.sent_at != nil
    end
  end
end
