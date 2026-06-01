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
      end_from_start = EventPhotos.effective_end_date(single_day)
      end_with_end = EventPhotos.effective_end_date(event)
      assert %Date{} = end_from_start
      assert end_with_end != nil
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
end
