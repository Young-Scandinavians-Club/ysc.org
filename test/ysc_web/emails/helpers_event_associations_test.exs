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

    test "raises when the event row no longer exists" do
      organizer = user_fixture()
      event = event_fixture(%{organizer_id: organizer.id})
      Repo.delete!(event)

      assert_raise ArgumentError, "Event not found: #{event.id}", fn ->
        Helpers.preload_event_associations(event)
      end
    end
  end
end
