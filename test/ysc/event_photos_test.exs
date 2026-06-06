defmodule Ysc.EventPhotosTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.EventPhotos
  alias Ysc.Events.Ticket
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
            dt
            |> DateTime.shift_zone!("America/Los_Angeles")
            |> DateTime.to_date()

          %Date{} = date ->
            date
        end

      assert EventPhotos.effective_end_date(single_day) == expected
      assert %Date{} = EventPhotos.effective_end_date(event)
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
  end

  describe "album_title/1" do
    test "includes event title and date", %{event: event} do
      title = EventPhotos.album_title(event)
      assert title =~ event.title

      assert String.length(title) <=
               Ysc.GooglePhotos.Limits.max_album_title_length()
    end
  end

  describe "photo_reminder_scheduled_at/1" do
    test "returns 9 AM America/Los_Angeles on the day after the event ends", %{
      event: event
    } do
      end_date =
        ~D[2026-06-10]
        |> DateTime.new!(~T[18:00:00], "America/Los_Angeles")
        |> DateTime.shift_zone!("Etc/UTC")
        |> DateTime.truncate(:second)

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

      assert :ok = EventPhotos.deliver_reminder_now(event, force: true)

      updated = EventPhotos.get_by_event_id(event.id)
      assert updated.reminder_recipient_count == 1
    end
  end

  describe "authorized_to_upload?/2 donation exclusion" do
    test "denies donation-only ticket holders", %{event: event} do
      donor = user_fixture()
      donation_tier = ticket_tier_fixture(%{event_id: event.id, type: :donation})

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
end
