defmodule YscWeb.Components.Events.CommunicationTimelineTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias Ysc.EventPhotos
  alias Ysc.Events
  alias Ysc.Events.EventUpdate
  alias YscWeb.Components.Events.CommunicationTimeline

  describe "build_entries/3" do
    test "includes sent event update" do
      organizer = Ysc.AccountsFixtures.user_fixture()
      event = event_fixture(%{organizer_id: organizer.id, state: :published})

      {:ok, update} =
        Events.create_event_update(event, %{
          title: "Venue Change",
          raw_body: "<p>Moved indoors</p>",
          rendered_body: "<p>Moved indoors</p>",
          sent_by_id: organizer.id
        })

      {:ok, update} = Events.mark_event_update_sent(update, 12)

      [entry] = CommunicationTimeline.build_entries(event, [update], nil)

      assert entry.type == :event_update
      assert entry.title == "Venue Change"
      assert entry.status == :sent
      assert entry.recipient_label == "12 email(s)"
      assert "Email" in entry.badges
    end

    test "includes SMS badge and recipient label when send_sms is enabled" do
      organizer = Ysc.AccountsFixtures.user_fixture()
      event = event_fixture(%{organizer_id: organizer.id, state: :published})

      {:ok, update} =
        Events.create_event_update(event, %{
          title: "Gate code",
          raw_body: "<p>Code is 1234</p>",
          rendered_body: "<p>Code is 1234</p>",
          send_sms: true,
          sms_body: "[YSC] Gate code: Code is 1234",
          sent_by_id: organizer.id
        })

      {:ok, update} = Events.mark_event_update_sent(update, 12)

      {:ok, update} =
        Events.mark_event_update_sms_sent(update, 5, update.sms_body)

      [entry] = CommunicationTimeline.build_entries(event, [update], nil)

      assert "Email" in entry.badges
      assert "SMS" in entry.badges
      assert entry.recipient_label == "12 email(s) · 5 SMS"
    end

    test "includes pending event update" do
      organizer = Ysc.AccountsFixtures.user_fixture()
      event = event_fixture(%{organizer_id: organizer.id, state: :published})

      {:ok, update} =
        Events.create_event_update(event, %{
          title: nil,
          raw_body: "<p>Pending</p>",
          rendered_body: "<p>Pending</p>",
          sent_by_id: organizer.id
        })

      [entry] = CommunicationTimeline.build_entries(event, [update], nil)

      assert entry.status == :pending
      assert entry.title == "Event Update"
    end

    test "includes sent publication notification" do
      organizer = Ysc.AccountsFixtures.user_fixture()
      event = event_fixture(%{organizer_id: organizer.id, state: :published})

      {:ok, event} = Events.mark_event_notification_sent(event, 42)

      [entry] = CommunicationTimeline.build_entries(event, [], nil)

      assert entry.type == :event_published
      assert entry.title == "New Event Announcement"
      assert entry.recipient_label == "42 member(s) notified"
    end

    test "includes scheduled publication notification when not yet sent" do
      organizer = Ysc.AccountsFixtures.user_fixture()

      published_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          state: :published,
          published_at: published_at,
          start_date:
            DateTime.add(DateTime.utc_now(), 7, :day)
            |> DateTime.truncate(:second),
          start_time: ~T[18:00:00]
        })

      [entry] = CommunicationTimeline.build_entries(event, [], nil)

      assert entry.type == :event_published
      assert entry.status == :scheduled
      assert "Scheduled" in entry.badges
    end

    test "includes sent photo reminder" do
      organizer = Ysc.AccountsFixtures.user_fixture()
      event = event_fixture(%{organizer_id: organizer.id, state: :published})
      {:ok, collection} = EventPhotos.ensure_collection_for_event(event)
      {:ok, collection} = EventPhotos.mark_reminder_sent(collection, 8)

      [entry] = CommunicationTimeline.build_entries(event, [], collection)

      assert entry.type == :photo_reminder
      assert entry.title == "Photo Upload Reminder"
      assert entry.preview =~ "8 attendee(s)"
    end

    test "sorts sent entries newest first with scheduled at bottom" do
      organizer = Ysc.AccountsFixtures.user_fixture()

      published_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          state: :published,
          published_at: published_at,
          start_date:
            DateTime.add(DateTime.utc_now(), 7, :day)
            |> DateTime.truncate(:second),
          start_time: ~T[18:00:00]
        })

      older =
        %EventUpdate{
          id: Ecto.ULID.generate(),
          title: "Older",
          rendered_body: "<p>old</p>",
          sent_at: DateTime.add(DateTime.utc_now(), -3600, :second),
          inserted_at: DateTime.add(DateTime.utc_now(), -7200, :second),
          recipient_count: 1,
          show_on_event_page: false
        }

      newer =
        %EventUpdate{
          id: Ecto.ULID.generate(),
          title: "Newer",
          rendered_body: "<p>new</p>",
          sent_at: DateTime.utc_now(),
          inserted_at: DateTime.utc_now(),
          recipient_count: 2,
          show_on_event_page: false
        }

      entries = CommunicationTimeline.build_entries(event, [older, newer], nil)

      assert Enum.at(entries, 0).title == "Newer"
      assert List.last(entries).status == :scheduled
    end
  end
end
