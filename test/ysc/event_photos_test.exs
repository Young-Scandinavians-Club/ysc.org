defmodule Ysc.EventPhotosTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.EventPhotos
  alias Ysc.Events.{Event, Ticket, TicketDetail}
  alias Ysc.Repo

  setup do
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})
    %{organizer: organizer, event: event}
  end

  describe "ensure_collection_for_event/1" do
    test "creates a unique upload token", %{event: event} do
      assert {:ok, collection} = EventPhotos.ensure_collection_for_event(event)
      assert collection.upload_token
      assert is_nil(collection.google_album_id)

      assert {:ok, same} = EventPhotos.ensure_collection_for_event(event)
      assert same.id == collection.id
    end

    test "accepts an event_id string and creates a collection", %{event: event} do
      assert {:ok, collection} =
               EventPhotos.ensure_collection_for_event(event.id)

      assert collection.event_id == event.id
    end

    test "returns :not_found for an unknown event_id string" do
      assert {:error, :not_found} =
               EventPhotos.ensure_collection_for_event(Ecto.ULID.generate())
    end
  end

  describe "get_by_upload_token/1 and get_by_upload_token!/1" do
    test "returns the collection with event preloaded for a known token", %{
      event: event
    } do
      {:ok, collection} = EventPhotos.ensure_collection_for_event(event)

      found = EventPhotos.get_by_upload_token(collection.upload_token)
      assert found.id == collection.id
      assert %Event{} = found.event

      found_bang = EventPhotos.get_by_upload_token!(collection.upload_token)
      assert found_bang.id == collection.id
    end

    test "returns nil for an unknown upload token" do
      assert is_nil(EventPhotos.get_by_upload_token(Ecto.UUID.generate()))
    end

    test "get_by_upload_token! raises for an unknown token" do
      assert_raise Ecto.NoResultsError, fn ->
        EventPhotos.get_by_upload_token!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_by_event_id/1" do
    test "returns nil when no collection exists for the event", %{event: event} do
      assert is_nil(EventPhotos.get_by_event_id(event.id))
    end
  end

  describe "upload_url/1" do
    test "builds the public upload page URL from the token", %{event: event} do
      {:ok, collection} = EventPhotos.ensure_collection_for_event(event)

      url = EventPhotos.upload_url(collection)
      assert url =~ "/events/photos/#{collection.upload_token}"
    end
  end

  describe "set_google_album_id/2" do
    test "persists the album id", %{event: event} do
      {:ok, collection} = EventPhotos.ensure_collection_for_event(event)

      assert {:ok, updated} =
               EventPhotos.set_google_album_id(collection, "album-123")

      assert updated.google_album_id == "album-123"
    end
  end

  describe "effective_end_date/1" do
    test "uses end_date when set", %{event: event} do
      date = EventPhotos.effective_end_date(event)
      assert %Date{} = date
    end

    test "falls back to start_date when end_date is nil", %{event: event} do
      single_day = %{event | end_date: nil}

      expected =
        case single_day.start_date do
          %DateTime{} = dt ->
            DateTime.to_date(dt)

          %Date{} = date ->
            date
        end

      assert EventPhotos.effective_end_date(single_day) == expected
      assert %Date{} = EventPhotos.effective_end_date(event)
    end

    test "reads the calendar date directly without shifting timezones, since start_date/end_date store a date placeholder (midnight UTC), not a real instant",
         %{event: event} do
      # This is how the admin date-range picker actually stores a picked calendar
      # day (date_range_picker.ex: `Date.to_string(value) <> "T00:00:00Z"`) — the
      # date component IS the intended calendar day, with no real timezone meaning.
      {:ok, dated_event} =
        Ysc.Events.update_event(event, %{
          start_date: ~U[2026-08-15 00:00:00Z],
          end_date: ~U[2026-08-15 00:00:00Z]
        })

      assert EventPhotos.effective_end_date(dated_event) == ~D[2026-08-15]
    end

    test "returns a plain %Date{} end_date as-is", %{event: event} do
      date_event = %{event | end_date: ~D[2026-09-01]}
      assert EventPhotos.effective_end_date(date_event) == ~D[2026-09-01]
    end

    test "returns nil when both start_date and end_date are nil", %{
      event: event
    } do
      undated = %{event | start_date: nil, end_date: nil}
      assert is_nil(EventPhotos.effective_end_date(undated))
    end
  end

  describe "authorized_to_upload?/2" do
    test "allows ticket holder email", %{event: event} do
      buyer =
        user_fixture(%{email: "buyer-#{System.unique_integer()}@example.com"})

      tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: buyer.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      assert EventPhotos.authorized_to_upload?(event, buyer)
    end

    test "allows admin users", %{event: event} do
      admin = user_fixture(%{role: :admin})
      assert EventPhotos.authorized_to_upload?(event, admin)
    end

    test "denies unrelated users", %{event: event} do
      other = user_fixture()
      refute EventPhotos.authorized_to_upload?(event, other)
    end

    test "denies non-admin users without a binary email", %{event: event} do
      user = %Ysc.Accounts.User{role: :member, email: nil}
      refute EventPhotos.authorized_to_upload?(event, user)
    end

    test "allows registrant email from ticket details", %{event: event} do
      buyer = user_fixture()

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
          user_id: buyer.id,
          ticket_tier_id: tier.id,
          status: :confirmed,
          expires_at:
            DateTime.add(DateTime.utc_now(), 1, :day)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      guest_email = "guest-registrant-#{System.unique_integer()}@example.com"

      %TicketDetail{
        id: Ecto.ULID.generate(),
        ticket_id: ticket.id,
        first_name: "Guest",
        last_name: "Registrant",
        email: guest_email
      }
      |> Repo.insert!()

      guest = user_fixture(%{email: guest_email})

      assert EventPhotos.authorized_to_upload?(event, guest)
    end
  end

  describe "album_title/1" do
    test "includes event title and date", %{event: event} do
      title = EventPhotos.album_title(event)
      assert title =~ event.title

      assert String.length(title) <=
               Ysc.GooglePhotos.Limits.max_album_title_length()
    end

    test "formats a plain %Date{} start_date the same as a %DateTime{}", %{
      event: event
    } do
      date_event = %{event | start_date: ~D[2026-03-15]}
      assert EventPhotos.album_title(date_event) =~ "Mar 15, 2026"
    end

    test "falls back to the bare title when start_date is neither Date nor DateTime",
         %{
           event: event
         } do
      title = EventPhotos.album_title(%{event | start_date: nil})
      assert title == Ysc.GooglePhotos.Limits.normalize_album_title(event.title)
    end
  end

  describe "photo_reminder_scheduled_at/1" do
    test "returns 9 AM America/Los_Angeles on the day after the event ends", %{
      event: event
    } do
      # Matches how the admin date-range picker actually stores a picked calendar
      # day: the literal date at midnight UTC (a placeholder, not a real instant).
      end_date = ~U[2026-06-10 00:00:00Z]

      {:ok, dated_event} =
        Ysc.Events.update_event(event, %{
          start_date: end_date,
          end_date: end_date
        })

      scheduled_at = EventPhotos.photo_reminder_scheduled_at(dated_event)

      assert scheduled_at ==
               ~D[2026-06-10]
               |> Date.add(1)
               |> DateTime.new!(~T[09:00:00], "America/Los_Angeles")
               |> DateTime.shift_zone!("Etc/UTC")
    end

    test "returns nil when event has no dates", %{event: event} do
      {:ok, undated_event} =
        Ysc.Events.update_event(event, %{start_date: nil, end_date: nil})

      assert EventPhotos.photo_reminder_scheduled_at(undated_event) == nil
    end
  end

  describe "mark_reminder_sent/2" do
    test "persists reminder timestamp and recipient count", %{event: event} do
      {:ok, collection} = EventPhotos.ensure_collection_for_event(event)

      assert {:ok, updated} = EventPhotos.mark_reminder_sent(collection, 5)
      assert updated.reminder_sent_at != nil
      assert updated.reminder_recipient_count == 5
    end
  end

  describe "deliver_reminder_now/2" do
    test "force clears prior sent state before resending", %{event: event} do
      buyer = user_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: buyer.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      {:ok, collection} = EventPhotos.ensure_collection_for_event(event)
      {:ok, _} = EventPhotos.mark_reminder_sent(collection, 99)

      assert :ok =
               EventPhotos.deliver_reminder_now(event,
                 force: true,
                 allow_future: true
               )

      updated = EventPhotos.get_by_event_id(event.id)
      assert updated.reminder_recipient_count == 1
    end

    test "refuses to send while the event hasn't ended yet", %{event: event} do
      assert {:error, :event_not_ended} =
               EventPhotos.deliver_reminder_now(event)

      assert is_nil(EventPhotos.get_by_event_id(event.id))
    end

    test "sends without force when there are no recipients yet", %{event: event} do
      assert :ok = EventPhotos.deliver_reminder_now(event, allow_future: true)

      updated = EventPhotos.get_by_event_id(event.id)
      assert updated.reminder_recipient_count == 0
    end

    test "treats an event with no dates as already ended (not blocked by allow_future)",
         %{
           event: event
         } do
      {:ok, undated_event} =
        Ysc.Events.update_event(event, %{start_date: nil, end_date: nil})

      assert :ok = EventPhotos.deliver_reminder_now(undated_event)
      assert EventPhotos.get_by_event_id(event.id)
    end

    test "accepts an event_id string and delivers the reminder", %{event: event} do
      assert :ok =
               EventPhotos.deliver_reminder_now(event.id, allow_future: true)

      assert EventPhotos.get_by_event_id(event.id)
    end

    test "returns :not_found for an unknown event_id string" do
      assert {:error, :not_found} =
               EventPhotos.deliver_reminder_now(Ecto.ULID.generate(),
                 allow_future: true
               )
    end
  end

  describe "authorized_to_upload?/2 donation exclusion" do
    test "denies donation-only ticket holders", %{event: event} do
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

      refute EventPhotos.authorized_to_upload?(event, donor)
    end
  end

  describe "ci_query_explain_query/0" do
    test "returns a well-formed Ecto query for CI query-plan checks" do
      assert %Ecto.Query{} = EventPhotos.ci_query_explain_query()
    end
  end
end
