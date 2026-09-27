defmodule YscWeb.Emails.HelpersEventAssociationsTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events.Event
  alias Ysc.Media.Image
  alias Ysc.Repo
  alias YscWeb.Emails.Helpers

  describe "preload_event_associations/2" do
    test "returns the event unchanged when associations are already loaded" do
      organizer = user_fixture()
      event = event_fixture(%{organizer_id: organizer.id})

      loaded =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      assert Helpers.preload_event_associations(loaded) == loaded
    end

    test "does not re-select the event row when associations are already loaded" do
      organizer = user_fixture()
      event = event_fixture(%{organizer_id: organizer.id})

      loaded =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      {_result, event_selects} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Helpers.preload_event_associations(loaded) end,
          pattern: ~r/FROM "events"/i,
          caller_pids: [self()]
        )

      assert event_selects == 0
    end

    test "loads organizer and cover_image when they are not loaded" do
      organizer = user_fixture()
      event = event_fixture(%{organizer_id: organizer.id})
      refute Ecto.assoc_loaded?(event.organizer)
      refute Ecto.assoc_loaded?(event.cover_image)

      loaded = Helpers.preload_event_associations(event)

      assert Ecto.assoc_loaded?(loaded.organizer)
      assert Ecto.assoc_loaded?(loaded.cover_image)
      assert loaded.organizer.id == organizer.id
      assert loaded.cover_image == nil
    end

    test "slims organizer to name columns without password hashes" do
      organizer =
        user_fixture(%{first_name: "Org", last_name: "Anizer"})
        |> Ecto.Changeset.change(%{board_bio: "must not load this bio"})
        |> Repo.update!()

      event = event_fixture(%{organizer_id: organizer.id})

      {loaded, password_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Helpers.preload_event_associations(event) end,
          pattern: ~r/hashed_password|board_bio/i,
          caller_pids: [self()]
        )

      assert password_cols == 0
      assert loaded.organizer.first_name == "Org"
      assert loaded.organizer.last_name == "Anizer"
      assert is_nil(loaded.organizer.hashed_password)
      assert is_nil(loaded.organizer.board_bio)
    end

    test "loads only the requested associations" do
      organizer = user_fixture()

      {:ok, image} =
        %Image{
          user_id: organizer.id,
          raw_image_path: "https://example.com/raw/cover.jpg",
          optimized_image_path: "https://example.com/opt/cover.jpg",
          processing_state: :completed
        }
        |> Repo.insert()

      event =
        event_fixture(%{organizer_id: organizer.id})
        |> Event.changeset(%{image_id: image.id})
        |> Repo.update!()

      loaded = Helpers.preload_event_associations(event, [:cover_image])

      assert Ecto.assoc_loaded?(loaded.cover_image)
      refute Ecto.assoc_loaded?(loaded.organizer)
      assert loaded.cover_image.id == image.id
    end

    test "preloads from in-memory foreign keys when the event row was deleted" do
      organizer = user_fixture()
      event = event_fixture(%{organizer_id: organizer.id})
      Repo.delete!(event)

      loaded = Helpers.preload_event_associations(event)

      assert Ecto.assoc_loaded?(loaded.organizer)
      assert loaded.organizer.id == organizer.id
    end
  end
end
