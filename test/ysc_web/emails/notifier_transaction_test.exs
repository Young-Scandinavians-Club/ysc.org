defmodule YscWeb.Emails.NotifierTransactionTest do
  use Ysc.DataCase, async: false

  import Ecto.Query

  alias Ecto.Multi
  alias Ysc.Repo
  alias YscWeb.Emails.Notifier

  test "commits the email job with the surrounding transaction" do
    key = "transactional_email_#{System.unique_integer([:positive])}"

    Oban.Testing.with_testing_mode(:manual, fn ->
      multi =
        Notifier.schedule_email_multi(
          Multi.new(),
          :email_job,
          %{
            recipient: "member@example.com",
            idempotency_key: key,
            subject: "Subject",
            template: "booking_confirmation",
            variables: %{},
            text_body: "Text body",
            user_id: nil
          }
        )

      assert {:ok, %{email_job: job}} = Repo.transaction(multi)
      assert job.args["idempotency_key"] == key
      assert job.queue == "transactional_mail"
    end)
  end

  test "rolls back the email job with the surrounding transaction" do
    key = "rolled_back_email_#{System.unique_integer([:positive])}"

    Oban.Testing.with_testing_mode(:manual, fn ->
      multi =
        Multi.new()
        |> Notifier.schedule_email_multi(
          :email_job,
          %{
            recipient: "member@example.com",
            idempotency_key: key,
            subject: "Subject",
            template: "booking_confirmation",
            variables: %{},
            text_body: "Text body",
            user_id: nil
          }
        )
        |> Multi.run(:force_rollback, fn _repo, _changes ->
          {:error, :rollback}
        end)

      assert {:error, :force_rollback, :rollback, _changes} =
               Repo.transaction(multi)

      assert Repo.aggregate(
               from(j in Oban.Job, where: j.args["idempotency_key"] == ^key),
               :count
             ) == 0
    end)
  end

  test "schedule_emails/1 inserts many jobs in one round trip" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      jobs =
        Notifier.schedule_emails([
          %{
            recipient: "one@example.com",
            idempotency_key: "blast_one_#{System.unique_integer([:positive])}",
            subject: "Subject",
            template: "event_notification",
            variables: %{first_name: "One"},
            text_body: "",
            user_id: nil
          },
          %{
            recipient: "two@example.com",
            idempotency_key: "blast_two_#{System.unique_integer([:positive])}",
            subject: "Subject",
            template: "event_notification",
            variables: %{first_name: "Two"},
            text_body: "",
            user_id: nil
          }
        ])

      assert length(jobs) == 2
      assert Enum.all?(jobs, &match?(%Oban.Job{}, &1))
      assert Enum.all?(jobs, &(&1.queue == "bulk_mail"))
    end)
  end

  test "schedule_emails/1 is a no-op for an empty list" do
    assert Notifier.schedule_emails([]) == []
  end
end
