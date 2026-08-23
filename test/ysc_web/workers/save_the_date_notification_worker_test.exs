defmodule YscWeb.Workers.SaveTheDateNotificationWorkerTest do
  @moduledoc """
  Tests for SaveTheDateNotificationWorker.
  """
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.SaveTheDateNotificationWorker
  alias Ysc.Events
  alias Ysc.Events.Event
  alias YscWeb.Emails.{Notifier, SaveTheDateAvailable}
  import Ysc.AccountsFixtures

  defp make_job(event_id) do
    %Oban.Job{
      id: System.unique_integer([:positive]),
      args: %{"event_id" => event_id},
      worker: "YscWeb.Workers.SaveTheDateNotificationWorker",
      queue: "mailers",
      state: "available",
      attempt: 1
    }
  end

  defp tbd_event(user) do
    {:ok, event} =
      Events.create_event(%{
        title: "Save the Date #{System.unique_integer()}",
        state: :published,
        organizer_id: user.id,
        start_date:
          DateTime.add(DateTime.utc_now(), 30, :day)
          |> DateTime.truncate(:second),
        published_at: DateTime.utc_now() |> DateTime.truncate(:second),
        tickets_tbd: true
      })

    event
  end

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    organizer = user_fixture()
    %{organizer: organizer}
  end

  describe "perform/1" do
    test "sends to multiple subscribers and completes successfully", %{
      organizer: organizer
    } do
      sub_a = user_fixture(%{event_notifications: true})
      sub_b = user_fixture(%{event_notifications: true})
      event = tbd_event(organizer)

      Events.subscribe_to_event_notification(
        event,
        sub_a.id,
        "save_the_date"
      )

      Events.subscribe_to_event_notification(
        event,
        sub_b.id,
        "save_the_date"
      )

      event
      |> Event.changeset(%{tickets_tbd: false})
      |> Ysc.Repo.update!()

      assert :ok = SaveTheDateNotificationWorker.perform(make_job(event.id))

      assert Events.get_event_notification_subscribers(
               event.id,
               "save_the_date"
             ) == []

      for subscriber <- [sub_a, sub_b] do
        idempotency_key =
          "save_the_date_available_#{event.id}_#{subscriber.id}"

        assert Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
                 idempotency_key: idempotency_key
               )
      end
    end

    test "returns :ok and sends emails to subscribers", %{organizer: organizer} do
      subscriber = user_fixture(%{event_notifications: true})
      event = tbd_event(organizer)

      Events.subscribe_to_event_notification(
        event,
        subscriber.id,
        "save_the_date"
      )

      # Clear the TBD flag before performing so the guard passes
      event
      |> Event.changeset(%{tickets_tbd: false})
      |> Ysc.Repo.update!()

      result = SaveTheDateNotificationWorker.perform(make_job(event.id))
      assert result == :ok
    end

    test "deletes subscriptions after sending", %{organizer: organizer} do
      subscriber = user_fixture(%{event_notifications: true})
      event = tbd_event(organizer)

      Events.subscribe_to_event_notification(
        event,
        subscriber.id,
        "save_the_date"
      )

      event
      |> Event.changeset(%{tickets_tbd: false})
      |> Ysc.Repo.update!()

      SaveTheDateNotificationWorker.perform(make_job(event.id))

      assert Events.get_event_notification_subscribers(
               event.id,
               "save_the_date"
             ) == []
    end

    test "skips sending when event still has tickets_tbd true", %{
      organizer: organizer
    } do
      subscriber = user_fixture(%{event_notifications: true})
      event = tbd_event(organizer)

      Events.subscribe_to_event_notification(
        event,
        subscriber.id,
        "save_the_date"
      )

      # Do NOT clear the flag — worker should bail out
      result = SaveTheDateNotificationWorker.perform(make_job(event.id))
      assert result == :ok

      # Subscriptions should still exist since no emails were sent
      assert length(
               Events.get_event_notification_subscribers(
                 event.id,
                 "save_the_date"
               )
             ) == 1
    end

    test "returns :ok and skips gracefully when no subscribers", %{
      organizer: organizer
    } do
      event = tbd_event(organizer)

      event
      |> Event.changeset(%{tickets_tbd: false})
      |> Ysc.Repo.update!()

      result = SaveTheDateNotificationWorker.perform(make_job(event.id))
      assert result == :ok
    end

    test "returns :ok when subscriber email already has idempotent job (duplicate insert)",
         %{organizer: organizer} do
      subscriber = user_fixture(%{event_notifications: true})
      event = tbd_event(organizer)

      Events.subscribe_to_event_notification(
        event,
        subscriber.id,
        "save_the_date"
      )

      event
      |> Event.changeset(%{tickets_tbd: false})
      |> Ysc.Repo.update!()

      email_data = SaveTheDateAvailable.prepare_email_data(event, subscriber)

      assert %Oban.Job{} =
               Notifier.schedule_email(
                 subscriber.email,
                 "save_the_date_available_#{event.id}_#{subscriber.id}",
                 SaveTheDateAvailable.get_subject(event),
                 SaveTheDateAvailable.get_template_name(),
                 email_data,
                 "",
                 subscriber.id
               )

      assert :ok = SaveTheDateNotificationWorker.perform(make_job(event.id))
    end

    test "handles missing event gracefully" do
      result =
        SaveTheDateNotificationWorker.perform(make_job(Ecto.ULID.generate()))

      assert result == :ok
    end

    test "only sends to subscribers of save_the_date type, not other types", %{
      organizer: organizer
    } do
      subscriber_a = user_fixture(%{event_notifications: true})
      subscriber_b = user_fixture(%{event_notifications: true})

      event = tbd_event(organizer)

      Events.subscribe_to_event_notification(
        event,
        subscriber_a.id,
        "save_the_date"
      )

      # subscriber_b does NOT subscribe

      event
      |> Event.changeset(%{tickets_tbd: false})
      |> Ysc.Repo.update!()

      SaveTheDateNotificationWorker.perform(make_job(event.id))

      # Both subscriptions should be gone (only save_the_date ones are cleaned up)
      remaining =
        Events.get_event_notification_subscribers(event.id, "save_the_date")

      assert remaining == []

      # subscriber_b was never subscribed
      assert Events.subscribed_to_event_notification?(
               event,
               subscriber_b.id,
               "save_the_date"
             ) ==
               false
    end
  end

  describe "integration: set_tickets_tbd schedules the worker" do
    test "clearing tickets_tbd on an event with subscribers runs the worker inline and clears subscriptions",
         %{organizer: organizer} do
      subscriber = user_fixture()
      event = tbd_event(organizer)

      Events.subscribe_to_event_notification(
        event,
        subscriber.id,
        "save_the_date"
      )

      {:ok, updated} = Events.set_tickets_tbd(event, false)
      assert updated.tickets_tbd == false

      # In :inline Oban mode the worker runs immediately and deletes subscriptions
      assert Events.get_event_notification_subscribers(
               event.id,
               "save_the_date"
             ) == []
    end

    test "setting tickets_tbd to true does not clear subscriptions", %{
      organizer: organizer
    } do
      subscriber = user_fixture()

      {:ok, event} =
        Events.create_event(%{
          title: "No-TBD Event",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 30, :day)
            |> DateTime.truncate(:second),
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      Events.subscribe_to_event_notification(
        event,
        subscriber.id,
        "save_the_date"
      )

      {:ok, _} = Events.set_tickets_tbd(event, true)

      # No worker triggered, subscriptions untouched
      assert length(
               Events.get_event_notification_subscribers(
                 event.id,
                 "save_the_date"
               )
             ) == 1
    end

    test "adding the first ticket tier clears tbd and runs the worker inline",
         %{organizer: organizer} do
      subscriber = user_fixture()
      event = tbd_event(organizer)

      Events.subscribe_to_event_notification(
        event,
        subscriber.id,
        "save_the_date"
      )

      {:ok, _tier} =
        Events.create_ticket_tier(%{
          name: "General Admission",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      updated = Events.get_event!(event.id)
      assert updated.tickets_tbd == false

      # Worker ran inline, subscriptions cleaned up
      assert Events.get_event_notification_subscribers(
               event.id,
               "save_the_date"
             ) == []
    end
  end
end
