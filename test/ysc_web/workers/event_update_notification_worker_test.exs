defmodule YscWeb.Workers.EventUpdateNotificationWorkerTest do
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.EventUpdateNotificationWorker
  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.Repo
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  defmodule NotificationsDisabledSmsNotifier do
    def schedule_smses(_entries), do: []

    def schedule_sms(_phone, _key, _template, _vars, _user_id) do
      {:error, :notifications_disabled}
    end
  end

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

    test "schedules one mailer job per attendee", %{
      event: event,
      organizer: organizer
    } do
      buyer_a = user_fixture()
      buyer_b = user_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

      for buyer <- [buyer_a, buyer_b] do
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
      end

      {:ok, update} =
        Events.create_event_update(event, %{
          title: "Batch Update",
          raw_body: "<p>Hello everyone</p>",
          rendered_body: "<p>Hello everyone</p>",
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
      assert updated.recipient_count == 2

      for buyer <- [buyer_a, buyer_b] do
        idempotency_key =
          "event_update_#{update.id}_#{String.downcase(buyer.email)}"

        assert Repo.get_by(Ysc.Messages.MessageIdempotency,
                 idempotency_key: idempotency_key
               )
      end
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

      refute Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: idempotency_key
             )
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

    test "schedules SMS when send_sms is enabled", %{
      event: event,
      organizer: organizer
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        buyer =
          user_fixture()
          |> Ecto.Changeset.change(event_notifications_sms: true)
          |> Repo.update!()

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

        sms_body = "[YSC] Blast: Tables in the back"

        {:ok, update} =
          Events.create_event_update(event, %{
            title: "Blast",
            raw_body: "<p>Tables in the back</p>",
            rendered_body: "<p>Tables in the back</p>",
            send_sms: true,
            sms_body: sms_body,
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
        assert updated.recipient_count == 1
        assert updated.sms_recipient_count == 1
        assert updated.sms_body == sms_body

        assert_enqueued(
          worker: YscWeb.Workers.SmsNotifier,
          args: %{
            "idempotency_key" =>
              "event_update_sms_#{update.id}_#{buyer.phone_number}",
            "template" => "event_update_notification"
          }
        )
      end)
    end

    test "does not schedule SMS when send_sms is false", %{
      event: event,
      organizer: organizer
    } do
      buyer =
        user_fixture()
        |> Ecto.Changeset.change(event_notifications_sms: true)
        |> Repo.update!()

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
          title: "Email only",
          raw_body: "<p>Hello</p>",
          rendered_body: "<p>Hello</p>",
          send_sms: false,
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
      assert updated.recipient_count == 1
      assert is_nil(updated.sms_recipient_count)

      refute_enqueued(worker: YscWeb.Workers.SmsNotifier)
    end

    test "skips SMS for opted-out purchasers", %{
      event: event,
      organizer: organizer
    } do
      buyer =
        user_fixture()
        |> Ecto.Changeset.change(event_notifications_sms: false)
        |> Repo.update!()

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
          title: "Blast",
          raw_body: "<p>Hello</p>",
          rendered_body: "<p>Hello</p>",
          send_sms: true,
          sms_body: "[YSC] Blast: Hello",
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
      assert updated.recipient_count == 1
      assert updated.sms_recipient_count == 0
      refute_enqueued(worker: YscWeb.Workers.SmsNotifier)
    end

    test "does not count skipped SMS recipients when notifier disables notifications",
         %{
           event: event,
           organizer: organizer
         } do
      previous =
        Application.get_env(:ysc, :event_update_sms_notifier)

      Application.put_env(
        :ysc,
        :event_update_sms_notifier,
        NotificationsDisabledSmsNotifier
      )

      on_exit(fn ->
        if previous do
          Application.put_env(:ysc, :event_update_sms_notifier, previous)
        else
          Application.delete_env(:ysc, :event_update_sms_notifier)
        end
      end)

      Oban.Testing.with_testing_mode(:manual, fn ->
        buyer =
          user_fixture()
          |> Ecto.Changeset.change(event_notifications_sms: true)
          |> Repo.update!()

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

        assert [_] = Events.list_event_update_sms_recipients(event.id)

        {:ok, update} =
          Events.create_event_update(event, %{
            title: "Blast",
            raw_body: "<p>Hello</p>",
            rendered_body: "<p>Hello</p>",
            send_sms: true,
            sms_body: "[YSC] Blast: Hello",
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
        assert updated.recipient_count == 1
        assert updated.sms_recipient_count == 0
        refute_enqueued(worker: YscWeb.Workers.SmsNotifier)
      end)
    end

    test "schedules one SMS job per opted-in purchaser", %{
      event: event,
      organizer: organizer
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        buyers =
          for _ <- 1..2 do
            user_fixture()
            |> Ecto.Changeset.change(event_notifications_sms: true)
            |> Repo.update!()
          end

        tier = ticket_tier_fixture(%{event_id: event.id, type: :paid})

        for buyer <- buyers do
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
        end

        {:ok, update} =
          Events.create_event_update(event, %{
            title: "Blast",
            raw_body: "<p>Hello everyone</p>",
            rendered_body: "<p>Hello everyone</p>",
            send_sms: true,
            sms_body: "[YSC] Blast: Hello everyone",
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
        assert updated.sms_recipient_count == 2

        for buyer <- buyers do
          assert_enqueued(
            worker: YscWeb.Workers.SmsNotifier,
            args: %{
              "idempotency_key" =>
                "event_update_sms_#{update.id}_#{buyer.phone_number}",
              "template" => "event_update_notification"
            }
          )
        end
      end)
    end
  end
end
