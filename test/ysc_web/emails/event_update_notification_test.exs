defmodule YscWeb.Emails.EventUpdateNotificationTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Media.Image
  alias Ysc.Repo
  alias YscWeb.Emails.EventUpdateNotification

  setup do
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})

    {:ok, update} =
      Events.create_event_update(event, %{
        title: "Venue Change",
        raw_body: "<p>Updated location</p>",
        rendered_body: "<p>Updated location</p>",
        sent_by_id: organizer.id
      })

    recipient = %{email: "attendee@example.com", first_name: "Alex"}

    %{organizer: organizer, event: event, update: update, recipient: recipient}
  end

  describe "get_template_name/0 and get_subject/2" do
    test "returns template name", %{event: event, update: update} do
      assert EventUpdateNotification.get_template_name() ==
               "event_update_notification"

      assert EventUpdateNotification.get_subject(event, update) =~
               "Venue Change"

      assert EventUpdateNotification.get_subject(event, update) =~ event.title
    end

    test "uses default title when update title is empty", %{
      event: event,
      update: update
    } do
      update = %{update | title: ""}
      subject = EventUpdateNotification.get_subject(event, update)
      assert subject =~ "Important Update"
    end
  end

  describe "prepare_email_data/3" do
    test "prepares email data with required fields", %{
      event: event,
      update: update,
      recipient: recipient
    } do
      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      data =
        EventUpdateNotification.prepare_email_data(event, update, recipient)

      assert data.first_name == "Alex"
      assert data.update_title == update.title
      assert data.update_body =~ "Updated location"
      assert data.event.id == event.id
      assert data.event_url =~ "/events/#{event.id}"
      assert data.notification_settings_url =~ "/users/notifications"
      assert data.event_image_url == nil
    end

    test "raises when event or update is nil", %{
      update: update,
      recipient: recipient
    } do
      event = event_fixture()

      assert_raise ArgumentError, "Event cannot be nil", fn ->
        Ysc.Test.Invoke.call(EventUpdateNotification, :prepare_email_data, [
          nil,
          update,
          recipient
        ])
      end

      assert_raise ArgumentError, "Update cannot be nil", fn ->
        Ysc.Test.Invoke.call(EventUpdateNotification, :prepare_email_data, [
          event,
          nil,
          recipient
        ])
      end
    end

    test "uses string-keyed recipient first_name", %{
      event: event,
      update: update
    } do
      event =
        Repo.get!(Event, event.id) |> Repo.preload([:organizer, :cover_image])

      recipient = %{"first_name" => "Jordan", "email" => "j@example.com"}

      data =
        EventUpdateNotification.prepare_email_data(event, update, recipient)

      assert data.first_name == "Jordan"
    end
  end

  describe "prepare_email_data/3 with event cover image" do
    test "includes optimized image URL when cover image is preloaded", %{
      event: event,
      update: update,
      recipient: recipient,
      organizer: organizer
    } do
      {:ok, image} =
        %Image{
          user_id: organizer.id,
          raw_image_path: "https://example.com/raw/event-update.jpg",
          optimized_image_path:
            "https://example.com/optimized/event-update.jpg",
          processing_state: :completed
        }
        |> Repo.insert()

      event =
        event
        |> Event.changeset(%{image_id: image.id})
        |> Repo.update!()
        |> Repo.preload([:organizer, :cover_image])

      data =
        EventUpdateNotification.prepare_email_data(event, update, recipient)

      assert data.event_image_url ==
               "https://example.com/optimized/event-update.jpg"
    end

    test "falls back to raw image path when optimized path is nil", %{
      event: event,
      update: update,
      recipient: recipient,
      organizer: organizer
    } do
      {:ok, image} =
        %Image{
          user_id: organizer.id,
          raw_image_path: "https://example.com/raw/event-update.jpg",
          optimized_image_path: nil,
          processing_state: :processing
        }
        |> Repo.insert()

      event =
        event
        |> Event.changeset(%{image_id: image.id})
        |> Repo.update!()
        |> Repo.preload([:organizer, :cover_image])

      data =
        EventUpdateNotification.prepare_email_data(event, update, recipient)

      assert data.event_image_url == "https://example.com/raw/event-update.jpg"
    end
  end
end
