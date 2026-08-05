defmodule YscWeb.Workers.NewsletterConfirmationReminderTest do
  use Ysc.DataCase, async: true

  alias Ysc.Newsletter
  alias Ysc.Repo
  alias YscWeb.Workers.NewsletterConfirmationReminder

  describe "perform/1" do
    test "sends a reminder for a still-pending subscriber" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, :pending} =
          Newsletter.request_confirmation("worker-pending@example.com",
            source: "public_signup"
          )

        subscriber =
          Newsletter.get_subscriber_by_email("worker-pending@example.com")

        assert :ok =
                 perform_job(NewsletterConfirmationReminder, %{
                   "subscriber_id" => subscriber.id
                 })

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => subscriber.email,
            "idempotency_key" =>
              "newsletter_confirmation_reminder_#{subscriber.id}",
            "template" => "newsletter_confirmation"
          }
        )
      end)
    end

    test "no-ops when the subscriber already confirmed" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, :pending} =
          Newsletter.request_confirmation("worker-confirmed@example.com",
            source: "public_signup"
          )

        subscriber =
          Newsletter.get_subscriber_by_email("worker-confirmed@example.com")

        {:ok, _} =
          Newsletter.confirm_subscription(subscriber.confirmation_token)

        assert :ok =
                 perform_job(NewsletterConfirmationReminder, %{
                   "subscriber_id" => subscriber.id
                 })

        # Only the reminder-specific send is skipped — the initial
        # confirmation email from request_confirmation/2 is unaffected.
        refute_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "idempotency_key" =>
              "newsletter_confirmation_reminder_#{subscriber.id}"
          }
        )
      end)
    end

    test "no-ops when the subscriber no longer exists" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, :pending} =
          Newsletter.request_confirmation("worker-deleted@example.com",
            source: "public_signup"
          )

        subscriber =
          Newsletter.get_subscriber_by_email("worker-deleted@example.com")

        Repo.delete!(subscriber)

        assert :ok =
                 perform_job(NewsletterConfirmationReminder, %{
                   "subscriber_id" => subscriber.id
                 })

        refute_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "idempotency_key" =>
              "newsletter_confirmation_reminder_#{subscriber.id}"
          }
        )
      end)
    end
  end

  describe "schedule/1" do
    test "enqueues a job scheduled ~24 hours from now" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, :pending} =
          Newsletter.request_confirmation("worker-schedule@example.com",
            source: "public_signup"
          )

        subscriber =
          Newsletter.get_subscriber_by_email("worker-schedule@example.com")

        assert_enqueued(
          worker: NewsletterConfirmationReminder,
          args: %{"subscriber_id" => subscriber.id}
        )

        [job] =
          all_enqueued(
            worker: NewsletterConfirmationReminder,
            args: %{"subscriber_id" => subscriber.id}
          )

        assert DateTime.diff(job.scheduled_at, DateTime.utc_now(), :second) >
                 23 * 60 * 60
      end)
    end

    test "calling it twice for the same subscriber does not stack duplicate jobs" do
      # A syntactically valid (but non-existent) ULID — schedule/1 never looks
      # the subscriber up, it only needs a well-formed id to avoid a cast error.
      subscriber_id = Ecto.ULID.generate()

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, job1} = NewsletterConfirmationReminder.schedule(subscriber_id)
        {:ok, job2} = NewsletterConfirmationReminder.schedule(subscriber_id)

        assert job1.id == job2.id
      end)
    end
  end
end
