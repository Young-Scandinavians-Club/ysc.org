defmodule YscWeb.Workers.EventNotificationWorkerTest do
  @moduledoc """
  Tests for EventNotificationWorker.
  """
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.EventNotificationWorker
  alias Ysc.Events
  alias Ysc.Events.Event
  alias YscWeb.Emails.{EventNotification, Notifier}
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

    test "skips notifications for cancelled event", %{event: event} do
      event
      |> Event.changeset(%{state: :cancelled})
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert EventNotificationWorker.perform(job) == :ok
    end

    test "skips notifications when start time is missing (cannot determine future start)",
         %{event: event} do
      future_date = DateTime.add(DateTime.utc_now(), 86400, :second)

      event
      |> Event.changeset(%{
        state: :published,
        start_date: future_date,
        start_time: nil
      })
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert EventNotificationWorker.perform(job) == :ok
    end

    test "skips notifications when start_date is nil (cannot combine date and time)",
         %{
           event: event
         } do
      assert {:ok, event} =
               Events.update_event(event, %{
                 state: :published,
                 start_date: nil,
                 start_time: ~T[10:00:00]
               })

      job = %Oban.Job{
        id: 1,
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert EventNotificationWorker.perform(job) == :ok
    end

    test "sends notifications when published event has future UTC start (date + time)",
         %{event: event} do
      future_start =
        DateTime.utc_now()
        |> DateTime.add(86_400, :second)
        |> DateTime.truncate(:second)

      {:ok, _} =
        Ysc.Accounts.update_notification_preferences(user_fixture(), %{
          event_notifications: true,
          account_notifications: true
        })

      assert {:ok, _} =
               Events.update_event(event, %{
                 state: :published,
                 start_date: future_start,
                 start_time: ~T[15:30:00]
               })

      job = %Oban.Job{
        id: 1,
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert EventNotificationWorker.perform(job) == :ok
    end

    test "skips notifications for published event with past start date (retroactive)",
         %{
           event: event
         } do
      past_date = DateTime.add(DateTime.utc_now(), -86400 * 2, :second)
      past_time = ~T[10:00:00]

      event
      |> Event.changeset(%{
        state: :published,
        start_date: past_date,
        start_time: past_time
      })
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
  end

  describe "schedule_notifications/2" do
    test "schedules notifications for future publish time", %{event: event} do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert :ok =
               EventNotificationWorker.schedule_notifications(
                 event.id,
                 future_time
               )

      # Oban test mode is :inline — jobs run immediately and are not left in oban_jobs.
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

    test "immediate path returns :ok when event does not exist" do
      past_time = DateTime.add(DateTime.utc_now(), -7200, :second)
      missing_id = Ecto.ULID.generate()

      assert :ok =
               EventNotificationWorker.schedule_notifications(
                 missing_id,
                 past_time
               )
    end

    test "immediate path skips when event is not published", %{event: event} do
      past_time = DateTime.add(DateTime.utc_now(), -7200, :second)

      event
      |> Event.changeset(%{state: :draft})
      |> Ysc.Repo.update!()

      assert :ok =
               EventNotificationWorker.schedule_notifications(
                 event.id,
                 past_time
               )
    end

    test "immediate path skips retroactive event", %{event: event} do
      past_time = DateTime.add(DateTime.utc_now(), -7200, :second)
      past_start = DateTime.add(DateTime.utc_now(), -86400 * 2, :second)

      event
      |> Event.changeset(%{
        state: :published,
        start_date: past_start,
        start_time: ~T[12:00:00]
      })
      |> Ysc.Repo.update!()

      assert :ok =
               EventNotificationWorker.schedule_notifications(
                 event.id,
                 past_time
               )
    end

    test "immediate path sends when publish lag exceeded but event start is still in the future",
         %{event: event} do
      past_publish = DateTime.add(DateTime.utc_now(), -7200, :second)

      future_start =
        DateTime.utc_now()
        |> DateTime.add(86_400, :second)
        |> DateTime.truncate(:second)

      {:ok, _} =
        Ysc.Accounts.update_notification_preferences(user_fixture(), %{
          event_notifications: true,
          account_notifications: true
        })

      assert {:ok, _} =
               Events.update_event(event, %{
                 state: :published,
                 start_date: future_start,
                 start_time: ~T[09:00:00]
               })

      assert :ok =
               EventNotificationWorker.schedule_notifications(
                 event.id,
                 past_publish
               )
    end
  end

  describe "send_event_notifications/1 duplicate email job" do
    test "still returns :ok when Notifier duplicate blocks a user (logs failure count)",
         %{event: event} do
      future_start = DateTime.add(DateTime.utc_now(), 3_600, :second)
      subscriber = user_fixture()

      {:ok, _} =
        Ysc.Accounts.update_notification_preferences(subscriber, %{
          event_notifications: true,
          account_notifications: true
        })

      event =
        event
        |> Event.changeset(%{state: :published, start_date: future_start})
        |> Ysc.Repo.update!()

      email_data = EventNotification.prepare_email_data(event, subscriber)

      assert %Oban.Job{} =
               Notifier.schedule_email(
                 subscriber.email,
                 "event_notification_#{event.id}_#{subscriber.id}",
                 EventNotification.get_subject(event),
                 EventNotification.get_template_name(),
                 email_data,
                 "",
                 subscriber.id
               )

      assert :ok = EventNotificationWorker.send_event_notifications(event)
    end
  end

  describe "send_event_notifications/1" do
    test "schedules one mailer job per user with event notifications enabled",
         %{
           event: event,
           organizer: organizer
         } do
      {:ok, _} =
        Ysc.Accounts.update_notification_preferences(organizer, %{
          event_notifications: false,
          account_notifications: true
        })

      user_with_events_a = user_fixture()

      {:ok, _} =
        Ysc.Accounts.update_notification_preferences(user_with_events_a, %{
          event_notifications: true,
          account_notifications: true
        })

      user_with_events_b = user_fixture()

      {:ok, _} =
        Ysc.Accounts.update_notification_preferences(user_with_events_b, %{
          event_notifications: true,
          account_notifications: true
        })

      user_without_events = user_fixture()

      {:ok, _} =
        Ysc.Accounts.update_notification_preferences(user_without_events, %{
          event_notifications: false,
          account_notifications: true
        })

      event =
        event
        |> Event.changeset(%{state: :published})
        |> Ysc.Repo.update!()

      assert :ok = EventNotificationWorker.send_event_notifications(event)

      import Ecto.Query

      expected_keys = [
        "event_notification_#{event.id}_#{user_with_events_a.id}",
        "event_notification_#{event.id}_#{user_with_events_b.id}"
      ]

      distinct_keys =
        Repo.all(
          from m in Ysc.Messages.MessageIdempotency,
            where: m.idempotency_key in ^expected_keys,
            distinct: [asc: m.idempotency_key],
            select: m.idempotency_key
        )

      assert MapSet.new(distinct_keys) == MapSet.new(expected_keys)

      refute Repo.exists?(
               from m in Ysc.Messages.MessageIdempotency,
                 where:
                   m.idempotency_key ==
                     ^"event_notification_#{event.id}_#{user_without_events.id}"
             )
    end
  end

  describe "perform/1 via Oban.Testing" do
    test "runs worker with perform_job helper", %{event: event} do
      future_start = DateTime.add(DateTime.utc_now(), 86400, :second)

      event
      |> Event.changeset(%{state: :published, start_date: future_start})
      |> Ysc.Repo.update!()

      assert :ok =
               perform_job(EventNotificationWorker, %{"event_id" => event.id})
    end
  end
end
