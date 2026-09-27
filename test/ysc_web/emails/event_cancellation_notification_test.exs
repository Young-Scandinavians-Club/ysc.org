defmodule YscWeb.Emails.EventCancellationNotificationTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Accounts.EmailCategories
  alias YscWeb.Emails.EventCancellationNotification

  setup do
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})
    %{event: event}
  end

  test "template name, subject, and category", %{event: event} do
    assert EventCancellationNotification.get_template_name() ==
             "event_cancellation_notification"

    assert EventCancellationNotification.get_subject(event) ==
             "[YSC] Cancelled: #{event.title}"

    # Cancellation notices must ignore event-notification opt-outs.
    assert EmailCategories.get_category("event_cancellation_notification") ==
             :account
  end

  test "prepares data and renders", %{event: event} do
    data =
      EventCancellationNotification.prepare_email_data(event, %{
        email: "astrid@example.com",
        first_name: "Astrid"
      })

    assert data.first_name == "Astrid"
    assert data.event.title == event.title
    assert data.upcoming_events_url =~ "/events"

    html = EventCancellationNotification.render(data)
    assert html =~ "Astrid"
    assert html =~ "has been cancelled"
    assert html =~ event.title
  end

  test "falls back to a generic greeting without a first name", %{event: event} do
    data =
      EventCancellationNotification.prepare_email_data(event, %{
        "email" => "guest@example.com",
        "first_name" => nil
      })

    assert data.first_name == "there"
  end
end
