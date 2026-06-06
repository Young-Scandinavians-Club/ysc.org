defmodule YscWeb.Workers.EventUpdateNotificationWorkerTest do
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.EventUpdateNotificationWorker
  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.Repo
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})
    %{organizer: organizer, event: event}
  end

  describe "perform/1" do
    test "sends notifications and marks update as sent", %{
      event: event,
      organizer: organizer
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

      {:ok, update} =
        Events.create_event_update(event, %{
          title: "Test Update",
          raw_body: "<p>Important info</p>",
          rendered_body: "<p>Important info</p>",
          sent_by_id: organizer.id
        })

      job = %Oban.Job{
        id: 1,
        args: %{"event_update_id" => update.id},
        worker: "YscWeb.Workers.EventUpdateNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert :ok = EventUpdateNotificationWorker.perform(job)

      updated = Repo.get!(Events.EventUpdate, update.id)
      assert updated.sent_at != nil
      assert updated.recipient_count == 1
    end

    test "handles missing event update gracefully" do
      job = %Oban.Job{
        id: 1,
        args: %{"event_update_id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.EventUpdateNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert :ok = EventUpdateNotificationWorker.perform(job)
    end

    test "excludes donation-only ticket holders from update notifications", %{
      event: event,
      organizer: organizer
    } do
      donor = user_fixture()
      donation_tier = ticket_tier_fixture(%{event_id: event.id, type: :donation})

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

      {:ok, update} =
        Events.create_event_update(event, %{
          title: "Donation-only",
          raw_body: "<p>Should not reach donors</p>",
          rendered_body: "<p>Should not reach donors</p>",
          sent_by_id: organizer.id
        })

      job = %Oban.Job{
        id: 1,
        args: %{"event_update_id" => update.id},
        worker: "YscWeb.Workers.EventUpdateNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert :ok = EventUpdateNotificationWorker.perform(job)

      updated = Repo.get!(Events.EventUpdate, update.id)
      assert updated.recipient_count == 0

      idempotency_key =
        "event_update_#{update.id}_#{String.downcase(donor.email)}"

      refute Repo.get_by(Ysc.Messages.MessageIdempotency, idempotency_key: idempotency_key)
    end

    test "handles event with no recipients", %{
      event: event,
      organizer: organizer
    } do
      {:ok, update} =
        Events.create_event_update(event, %{
          title: "Empty",
          raw_body: "No one to send to",
          rendered_body: "No one to send to",
          sent_by_id: organizer.id
        })

      job = %Oban.Job{
        id: 1,
        args: %{"event_update_id" => update.id},
        worker: "YscWeb.Workers.EventUpdateNotificationWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert :ok = EventUpdateNotificationWorker.perform(job)

      updated = Repo.get!(Events.EventUpdate, update.id)
      assert updated.recipient_count == 0
    end
  end
end
