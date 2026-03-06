defmodule YscWeb.Emails.EventNotificationTest do
  @moduledoc """
  Tests for EventNotification email module.

  Tests cover:
  - Template name retrieval
  - Email subject generation
  - Event URL generation
  - Email data preparation with and without cover images
  - Proper handling of missing associations
  """
  use Ysc.DataCase, async: true

  alias YscWeb.Emails.EventNotification
  alias Ysc.Events.Event
  alias Ysc.Media.Image
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  setup do
    organizer = user_fixture()
    user = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})

    %{organizer: organizer, user: user, event: event}
  end

  describe "get_template_name/0" do
    test "returns correct template name" do
      assert EventNotification.get_template_name() == "event_notification"
    end
  end

  describe "get_subject/1" do
    test "prefixes subject with [YSC]", %{event: event} do
      subject = EventNotification.get_subject(event)
      assert String.starts_with?(subject, "[YSC] ")
    end

    test "returns a subject containing the event title when event is provided",
         %{event: event} do
      subject = EventNotification.get_subject(event)
      assert subject =~ event.title
    end

    test "returns a save-the-date subject containing the event title when tickets_tbd is true",
         %{
           organizer: organizer
         } do
      event = event_fixture(%{organizer_id: organizer.id, tickets_tbd: true})
      subject = EventNotification.get_subject(event)
      assert String.starts_with?(subject, "[YSC] ")
      assert subject =~ event.title
    end

    test "returns a prefixed non-empty string when event is nil" do
      subject = EventNotification.get_subject(nil)
      assert String.starts_with?(subject, "[YSC] ")
    end

    test "returns a prefixed non-empty string when no argument is provided" do
      subject = EventNotification.get_subject()
      assert String.starts_with?(subject, "[YSC] ")
    end
  end

  describe "event_url/1" do
    test "generates correct event URL", %{event: event} do
      url = EventNotification.event_url(event.id)
      assert url =~ "/events/#{event.id}"
      assert url =~ YscWeb.Endpoint.url()
    end
  end

  describe "prepare_email_data/2" do
    test "prepares email data with all required fields", %{
      event: event,
      user: user
    } do
      # Reload event with associations
      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      # Check basic structure
      assert is_map(email_data)
      assert email_data.first_name == user.first_name
      assert is_map(email_data.event)
      assert email_data.event_url =~ "/events/#{event.id}"
      assert email_data.notification_settings_url =~ "/users/notifications"

      # Check event details
      assert email_data.event.id == event.id
      assert email_data.event.title == event.title
      assert email_data.event.description == event.description
      assert email_data.event.location_name == event.location_name
      assert email_data.event.address == event.address
    end

    test "uses fallback first name when user has no first_name", %{event: event} do
      # Create user and then update to remove first_name
      user = user_fixture()

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{first_name: nil})
        |> Repo.update()

      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      assert email_data.first_name == "Valued Member"
    end

    test "includes organizer information when available", %{
      event: event,
      user: user
    } do
      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      assert is_map(email_data.event.organizer)
      assert email_data.event.organizer.first_name == event.organizer.first_name
      assert email_data.event.organizer.last_name == event.organizer.last_name
    end

    test "formats event datetime correctly with date and time", %{
      event: event,
      user: user
    } do
      event =
        event
        |> Event.changeset(%{
          start_date:
            DateTime.add(DateTime.utc_now(), 86400, :second)
            |> DateTime.truncate(:second),
          start_time: ~T[14:30:00]
        })
        |> Repo.update!()
        |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      assert is_binary(email_data.event_date_time)
      # Should include date, time, and timezone (PST/PDT)
      assert email_data.event_date_time =~ ~r/\d{1,2}:\d{2} (AM|PM) (PST|PDT)/
    end

    test "formats event datetime with date only when no time", %{
      event: event,
      user: user
    } do
      event =
        event
        |> Event.changeset(%{
          start_date:
            DateTime.add(DateTime.utc_now(), 86400, :second)
            |> DateTime.truncate(:second),
          start_time: nil
        })
        |> Repo.update!()
        |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      assert is_binary(email_data.event_date_time)
      # Should only include date, not time
      refute email_data.event_date_time =~ ~r/\d{1,2}:\d{2} (AM|PM)/
    end

    test "returns nil datetime when event has no start_date", %{
      event: event,
      user: user
    } do
      event =
        event
        |> Event.changeset(%{start_date: nil, start_time: nil})
        |> Repo.update!()
        |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      assert email_data.event_date_time == nil
    end

    test "raises ArgumentError when event is nil", %{user: user} do
      assert_raise ArgumentError, "Event cannot be nil", fn ->
        EventNotification.prepare_email_data(nil, user)
      end
    end

    test "raises ArgumentError when user is nil", %{event: event} do
      assert_raise ArgumentError, "User cannot be nil", fn ->
        EventNotification.prepare_email_data(event, nil)
      end
    end

    test "loads event with associations when not preloaded", %{
      event: event,
      user: user
    } do
      # Reload to get actual organizer data first
      loaded_event = Repo.get!(Event, event.id) |> Repo.preload([:organizer])
      organizer_first_name = loaded_event.organizer.first_name

      # Pass event without preloaded associations
      email_data = EventNotification.prepare_email_data(event, user)

      # Should still work and include organizer info
      assert is_map(email_data.event.organizer)
      assert email_data.event.organizer.first_name == organizer_first_name
    end
  end

  describe "prepare_email_data/2 with event cover image" do
    test "includes image URL when event has cover image with optimized path", %{
      event: event,
      user: user
    } do
      # Create a cover image with optimized path
      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/raw/event-image.jpg",
          optimized_image_path: "https://example.com/optimized/event-image.jpg",
          processing_state: :completed
        }
        |> Repo.insert()

      # Associate image with event
      event
      |> Event.changeset(%{image_id: image.id})
      |> Repo.update!()

      # Reload event with associations
      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      # Should use optimized image path
      assert email_data.event_image_url ==
               "https://example.com/optimized/event-image.jpg"
    end

    test "falls back to raw image path when optimized path is nil", %{
      event: event,
      user: user
    } do
      # Create a cover image without optimized path (still processing)
      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/raw/event-image.jpg",
          optimized_image_path: nil,
          processing_state: :processing
        }
        |> Repo.insert()

      # Associate image with event
      event
      |> Event.changeset(%{image_id: image.id})
      |> Repo.update!()

      # Reload event with associations
      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      # Should use raw image path
      assert email_data.event_image_url ==
               "https://example.com/raw/event-image.jpg"
    end

    test "returns nil image URL when event has no cover image", %{
      event: event,
      user: user
    } do
      # Reload event with associations (but no cover image)
      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      # Should return nil when no image
      assert email_data.event_image_url == nil
    end

    test "returns nil image URL when cover_image association is not loaded", %{
      event: event,
      user: user
    } do
      # Pass event without preloaded cover_image
      # The function should load it, but if image_id is nil, result should be nil
      email_data = EventNotification.prepare_email_data(event, user)

      # Should return nil when no image
      assert email_data.event_image_url == nil
    end

    test "handles event with missing cover image gracefully", %{
      event: event,
      user: user
    } do
      # Create an image first
      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/raw/event-image.jpg",
          optimized_image_path: "https://example.com/optimized/event-image.jpg",
          processing_state: :completed
        }
        |> Repo.insert()

      # Associate image with event
      event =
        event
        |> Event.changeset(%{image_id: image.id})
        |> Repo.update!()

      # Now disassociate the image to simulate missing/deleted image
      event
      |> Event.changeset(%{image_id: nil})
      |> Repo.update!()

      # Delete the image
      Repo.delete!(image)

      # Reload event - cover_image should be nil
      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      # Should return nil when image doesn't exist
      assert email_data.event_image_url == nil
    end

    test "includes all required data when event has cover image", %{
      event: event,
      user: user
    } do
      # Create a cover image
      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/raw/event-image.jpg",
          optimized_image_path: "https://example.com/optimized/event-image.jpg",
          processing_state: :completed
        }
        |> Repo.insert()

      # Associate image with event
      event
      |> Event.changeset(%{image_id: image.id})
      |> Repo.update!()

      # Reload event with associations
      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      email_data = EventNotification.prepare_email_data(event, user)

      # Verify all required fields are present
      assert email_data.first_name == user.first_name
      assert is_map(email_data.event)
      assert email_data.event_url =~ "/events/#{event.id}"

      assert email_data.event_image_url ==
               "https://example.com/optimized/event-image.jpg"

      # Verify event details are still included
      assert email_data.event.id == event.id
      assert email_data.event.title == event.title
    end
  end
end
