defmodule YscWeb.Workers.EventNotificationWorkerTest do
  @moduledoc """
  Tests for EventNotificationWorker.
  """
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.EventNotificationWorker
  alias Ysc.Events.Event
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})
    %{organizer: organizer, event: event}
  end

  describe "perform/1" do
    test "sends notifications for published event", %{event: event} do
      # Update event to published state
      event
      |> Event.changeset(%{state: :published})
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = EventNotificationWorker.perform(job)
      assert result == :ok
    end

    test "skips notifications for non-published event", %{event: event} do
      # Update event to draft state
      event
      |> Event.changeset(%{state: :draft})
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = EventNotificationWorker.perform(job)
      assert result == :ok
    end

    test "handles missing event gracefully" do
      job = %Oban.Job{
        id: 1,
        args: %{"event_id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.EventNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = EventNotificationWorker.perform(job)
      assert result == :ok
    end
  end

  describe "schedule_notifications/2" do
    test "schedules notifications for future publish time", %{event: event} do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      result =
        EventNotificationWorker.schedule_notifications(event.id, future_time)

      assert result == :ok
    end

    test "sends immediately if 1 hour has passed", %{event: event} do
      past_time = DateTime.add(DateTime.utc_now(), -7200, :second)

      # Update event to published
      event
      |> Event.changeset(%{state: :published})
      |> Ysc.Repo.update!()

      result =
        EventNotificationWorker.schedule_notifications(event.id, past_time)

      assert result == :ok
    end
  end
end
