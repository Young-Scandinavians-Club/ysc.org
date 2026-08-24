defmodule YscWeb.Emails.EventPhotoUploadReminderTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.EventPhotos
  alias YscWeb.Emails.EventPhotoUploadReminder

  setup do
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})
    {:ok, collection} = EventPhotos.ensure_collection_for_event(event)
    recipient = %{email: "guest@example.com", first_name: "Alex"}
    upload_url = EventPhotos.upload_url(collection)

    %{event: event, recipient: recipient, upload_url: upload_url}
  end

  test "template name and subject", %{event: event} do
    assert EventPhotoUploadReminder.get_template_name() ==
             "event_photo_upload_reminder"

    assert EventPhotoUploadReminder.get_subject(event) =~ event.title
    assert EventPhotoUploadReminder.get_subject(event) =~ "Share your photos"
  end

  test "prepare_email_data includes upload url", %{
    event: event,
    recipient: recipient,
    upload_url: upload_url
  } do
    data =
      EventPhotoUploadReminder.prepare_email_data(event, recipient, upload_url)

    assert data.upload_url == upload_url
    assert data.first_name == "Alex"
    assert data.event_title == event.title
  end

  test "prepare_shared_email_data omits first_name", %{
    event: event,
    recipient: recipient,
    upload_url: upload_url
  } do
    shared =
      EventPhotoUploadReminder.prepare_shared_email_data(event, upload_url)

    refute Map.has_key?(shared, :first_name)

    data =
      EventPhotoUploadReminder.prepare_email_data(event, recipient, upload_url)

    assert data == Map.put(shared, :first_name, "Alex")
  end
end
