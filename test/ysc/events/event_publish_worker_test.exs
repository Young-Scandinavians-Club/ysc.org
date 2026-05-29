defmodule Ysc.Events.EventPublishWorkerTest do
  @moduledoc """
  Tests for Ysc.Events.EventPublishWorker.
  """
  use Ysc.DataCase, async: true

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Events.EventPublishWorker
  alias Ysc.Events.Event
  alias Ysc.Repo

  setup do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    organizer = user_fixture()

    # Create an event scheduled in the past
    past_event =
      Repo.insert!(%Event{
        title: "Past Scheduled Event",
        reference_id: "EVT-PAST",
        state: :scheduled,
        publish_at: DateTime.add(now, -3600, :second),
        start_date: DateTime.add(now, 86_400, :second),
        end_date: DateTime.add(now, 90_000, :second),
        organizer_id: organizer.id
      })

    # Create an event scheduled in the future
    future_event =
      Repo.insert!(%Event{
        title: "Future Scheduled Event",
        reference_id: "EVT-FUTURE",
        state: :scheduled,
        publish_at: DateTime.add(now, 3600, :second),
        start_date: DateTime.add(now, 86_400, :second),
        end_date: DateTime.add(now, 90_000, :second),
        organizer_id: organizer.id
      })

    %{past_event: past_event, future_event: future_event, organizer: organizer}
  end

  describe "perform/1" do
    test "publishes events scheduled in the past", %{past_event: past_event} do
      assert {:ok, _} = EventPublishWorker.perform(%Oban.Job{})

      updated_event = Repo.get(Event, past_event.id)
      # Atom or string depending on EctoEnum or string field
      assert updated_event.state == :published
      # Let's check schema: usually state is string or enum atom.
      # The worker uses `where([e], e.state == "scheduled")` so it seems it's a string or EctoEnum that casts to string in query.
      # If it is an EctoEnum, it should be atom in struct.
      # Let's check if `Ysc.Events.publish_event` returns atom state.
      # Assuming :published atom.
    end

    test "does not publish future events", %{future_event: future_event} do
      assert {:ok, _} = EventPublishWorker.perform(%Oban.Job{})

      updated_event = Repo.get(Event, future_event.id)
      assert updated_event.state == :scheduled
    end

    test "perform_job runs the worker", %{past_event: _past_event} do
      assert {:ok, "Processed scheduled events"} =
               perform_job(EventPublishWorker, %{})
    end
  end

  describe "publish_scheduled_events/0" do
    test "processes due scheduled events", %{past_event: past_event} do
      :ok = EventPublishWorker.publish_scheduled_events()
      assert Repo.get(Event, past_event.id).state == :published
    end

    test "continues when publish_event fails validation for a due event", %{
      past_event: past_event
    } do
      Repo.update_all(from(e in Event, where: e.id == ^past_event.id),
        set: [title: ""]
      )

      assert :ok = EventPublishWorker.publish_scheduled_events()

      assert Repo.get(Event, past_event.id).state == :scheduled
    end

    test "does not publish event when publish_at is invalid relative to start",
         %{
           organizer: organizer
         } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      bad =
        Repo.insert!(%Event{
          title: "Publish window invalid",
          reference_id: "EVT-BAD-PUBLISH-AT",
          state: :scheduled,
          publish_at: DateTime.add(now, -3600, :second),
          start_date: DateTime.add(now, -7 * 86_400, :second),
          start_time: ~T[10:00:00],
          end_date: DateTime.add(now, -6 * 86_400, :second),
          end_time: ~T[12:00:00],
          organizer_id: organizer.id
        })

      assert :ok = EventPublishWorker.publish_scheduled_events()
      assert Repo.get(Event, bad.id).state == :scheduled
    end

    test "publishes multiple due events in one run", %{
      past_event: past_event,
      organizer: organizer
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      other =
        Repo.insert!(%Event{
          title: "Second Past Scheduled",
          reference_id: "EVT-PAST-2",
          state: :scheduled,
          publish_at: DateTime.add(now, -7200, :second),
          start_date: DateTime.add(now, 86_400, :second),
          end_date: DateTime.add(now, 90_000, :second),
          organizer_id: organizer.id
        })

      assert :ok = EventPublishWorker.publish_scheduled_events()

      assert Repo.get(Event, past_event.id).state == :published
      assert Repo.get(Event, other.id).state == :published
    end
  end

  describe "timeout/1" do
    test "returns 60 seconds" do
      assert EventPublishWorker.timeout(%Oban.Job{}) == 60_000
    end
  end

  describe "publish_event/1 with stale lock" do
    test "raises StaleEntryError when lock_version no longer matches", %{
      past_event: past_event
    } do
      event = Repo.get!(Event, past_event.id)

      {1, _} =
        Repo.update_all(from(e in Event, where: e.id == ^event.id),
          inc: [lock_version: 1]
        )

      assert_raise Ecto.StaleEntryError, fn ->
        Ysc.Events.publish_event(event)
      end
    end
  end
end
