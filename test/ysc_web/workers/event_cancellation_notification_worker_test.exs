defmodule YscWeb.Workers.EventCancellationNotificationWorkerTest do
  use Ysc.DataCase, async: false

  alias Ysc.Events.Event
  alias Ysc.Messages.MessageIdempotency
  alias Ysc.Repo
  alias YscWeb.Workers.EventCancellationNotificationWorker
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  @cancelled_at "2026-09-26T12:00:00Z"

  setup do
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})
    %{event: event}
  end

  defp job(event_id, recipients) do
    %Oban.Job{
      id: 1,
      args: %{
        "event_id" => event_id,
        "cancelled_at" => @cancelled_at,
        "recipients" => recipients
      },
      worker: "YscWeb.Workers.EventCancellationNotificationWorker",
      queue: "bulk_mail",
      state: "available",
      attempt: 1
    }
  end

  defp cancel!(event) do
    event |> Ecto.Changeset.change(state: :cancelled) |> Repo.update!()
  end

  defp idempotency_key(event, email) do
    "event_cancelled_#{event.id}_#{@cancelled_at}_#{String.downcase(email)}"
  end

  test "new_for_event/3 snapshots blank first names as nil", %{event: event} do
    job =
      EventCancellationNotificationWorker.new_for_event(
        event,
        [
          %{email: "blank@example.com", first_name: "  "},
          %{email: "astrid@example.com", first_name: "Astrid"}
        ],
        ~U[2026-09-26 12:00:00Z]
      )

    assert job.changes.args["recipients"] == [
             %{"email" => "blank@example.com", "first_name" => nil},
             %{"email" => "astrid@example.com", "first_name" => "Astrid"}
           ]
  end

  test "emails every snapshotted recipient of a cancelled event", %{
    event: event
  } do
    event = cancel!(event)

    recipients = [
      %{"email" => "Astrid@example.com", "first_name" => "Astrid"},
      %{"email" => "guest@example.com", "first_name" => nil}
    ]

    assert :ok =
             EventCancellationNotificationWorker.perform(
               job(event.id, recipients)
             )

    for %{"email" => email} <- recipients do
      assert Repo.get_by(MessageIdempotency,
               idempotency_key: idempotency_key(event, email)
             )
    end
  end

  test "skips events that are no longer cancelled", %{event: event} do
    assert Repo.get!(Event, event.id).state != :cancelled

    recipients = [%{"email" => "astrid@example.com", "first_name" => "Astrid"}]

    assert :ok =
             EventCancellationNotificationWorker.perform(
               job(event.id, recipients)
             )

    refute Repo.get_by(MessageIdempotency,
             idempotency_key: idempotency_key(event, "astrid@example.com")
           )
  end

  test "handles a missing event" do
    assert :ok =
             EventCancellationNotificationWorker.perform(
               job(Ecto.ULID.generate(), [])
             )
  end
end
