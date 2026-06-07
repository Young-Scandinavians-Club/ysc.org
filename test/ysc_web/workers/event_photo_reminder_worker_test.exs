defmodule YscWeb.Workers.EventPhotoReminderWorkerTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.EventPhotos
  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.Repo
  alias YscWeb.Workers.EventPhotoReminderWorker

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id, state: :published})
    {:ok, collection} = EventPhotos.ensure_collection_for_event(event)
    %{organizer: organizer, event: event, collection: collection}
  end

  describe "perform/1" do
    test "sends reminders and marks collection", %{
      event: event,
      collection: collection
    } do
      buyer = user_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: buyer.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      job = %Oban.Job{
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventPhotoReminderWorker"
      }

      assert :ok = EventPhotoReminderWorker.perform(job)

      updated = Repo.get!(EventPhotos.Collection, collection.id)
      assert updated.reminder_sent_at != nil
      assert updated.reminder_recipient_count == 1
    end

    test "marks collection with zero recipients when event has no attendees", %{
      event: event,
      collection: collection
    } do
      job = %Oban.Job{
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventPhotoReminderWorker"
      }

      assert :ok = EventPhotoReminderWorker.perform(job)

      updated = Repo.get!(EventPhotos.Collection, collection.id)
      assert updated.reminder_sent_at != nil
      assert updated.reminder_recipient_count == 0
    end

    test "excludes donation-only ticket holders from photo reminders", %{
      event: event,
      collection: collection
    } do
      donor = user_fixture()

      donation_tier =
        ticket_tier_fixture(%{event_id: event.id, type: :donation})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: donor.id,
        ticket_tier_id: donation_tier.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      job = %Oban.Job{
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventPhotoReminderWorker"
      }

      assert :ok = EventPhotoReminderWorker.perform(job)

      updated = Repo.get!(EventPhotos.Collection, collection.id)
      assert updated.reminder_recipient_count == 0
    end

    test "skips when reminder already sent", %{
      event: event,
      collection: collection
    } do
      {:ok, _} = EventPhotos.mark_reminder_sent(collection, 1)

      job = %Oban.Job{
        args: %{"event_id" => event.id},
        worker: "YscWeb.Workers.EventPhotoReminderWorker"
      }

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EventPhotoReminderWorker.perform(job)

        refute_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template_name" => "event_photo_upload_reminder"}
        )
      end)
    end
  end

  describe "send_reminders/2" do
    test "schedules one mailer job per non-donation attendee", %{
      event: event,
      collection: collection
    } do
      buyer = user_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: buyer.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      assert :ok = EventPhotoReminderWorker.send_reminders(event, collection)

      updated = Repo.get!(EventPhotos.Collection, collection.id)
      assert updated.reminder_recipient_count == 1

      idempotency_key =
        "event_photo_reminder_#{event.id}_#{String.downcase(buyer.email)}"

      assert Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: idempotency_key
             )
    end
  end

  describe "schedule_reminder/1" do
    test "schedules a future job for published events", %{event: event} do
      {:ok, future_event} =
        Events.update_event(event, %{
          start_date:
            DateTime.add(DateTime.utc_now(), 30, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 31, :day)
            |> DateTime.truncate(:second)
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EventPhotoReminderWorker.schedule_reminder(future_event)

        assert_enqueued(
          worker: EventPhotoReminderWorker,
          args: %{"event_id" => future_event.id}
        )
      end)
    end

    test "sends immediately when reminder time has already passed", %{
      event: event,
      collection: collection
    } do
      buyer = user_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: buyer.id,
        ticket_tier_id: tier.id,
        status: :confirmed,
        expires_at:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      {:ok, past_event} =
        Events.update_event(event, %{
          start_date:
            DateTime.add(DateTime.utc_now(), -5, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), -4, :day)
            |> DateTime.truncate(:second)
        })

      assert :ok = EventPhotoReminderWorker.schedule_reminder(past_event)

      updated = Repo.get!(EventPhotos.Collection, collection.id)
      assert updated.reminder_sent_at != nil
      assert updated.reminder_recipient_count == 1
    end
  end
end
