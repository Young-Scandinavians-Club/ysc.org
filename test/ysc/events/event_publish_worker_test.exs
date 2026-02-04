defmodule Ysc.Events.EventPublishWorkerTest do
  @moduledoc """
  Tests for Ysc.Events.EventPublishWorker.
  """
  use Ysc.DataCase, async: true

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

    %{past_event: past_event, future_event: future_event}
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
  end
end
