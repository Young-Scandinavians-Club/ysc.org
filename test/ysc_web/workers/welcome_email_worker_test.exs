defmodule YscWeb.Workers.WelcomeEmailWorkerTest do
  @moduledoc """
  Tests for WelcomeEmailWorker.
  """
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.WelcomeEmailWorker
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Swoosh.TestAssertions

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    clear_seasons!()
    user = user_fixture()
    %{user: user}
  end

  describe "perform/1" do
    test "sends welcome email for user with active membership", %{user: user} do
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => user.id},
        worker: "YscWeb.Workers.WelcomeEmailWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert WelcomeEmailWorker.perform(job) == :ok
      assert_email_sent(subject: YscWeb.Emails.WelcomeEmail.get_subject())
    end

    test "skips user without an active membership", %{user: user} do
      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => user.id},
        worker: "YscWeb.Workers.WelcomeEmailWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert WelcomeEmailWorker.perform(job) == :ok

      welcome_subject = YscWeb.Emails.WelcomeEmail.get_subject()
      refute_email_sent(subject: ^welcome_subject)
    end

    test "skips a WP-migrated user even with an active membership", %{
      user: user
    } do
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second),
        post_migration_onboarding_completed_at: nil
      )
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => user.id},
        worker: "YscWeb.Workers.WelcomeEmailWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert WelcomeEmailWorker.perform(job) == :ok
    end

    test "handles missing user gracefully" do
      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.WelcomeEmailWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      assert WelcomeEmailWorker.perform(job) == :ok
    end

    test "does not SELECT password hashes or bios for a lifetime member", %{
      user: user
    } do
      user
      |> Ecto.Changeset.change(%{
        board_bio: "must not load this bio",
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      })
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => user.id},
        worker: "YscWeb.Workers.WelcomeEmailWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      {result, password_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> WelcomeEmailWorker.perform(job) end,
          pattern: ~r/hashed_password|board_bio/i,
          caller_pids: [self()]
        )

      assert result == :ok
      assert password_cols == 0
      assert_email_sent(subject: YscWeb.Emails.WelcomeEmail.get_subject())
    end

    test "skips subscription lookup for a lifetime member", %{user: user} do
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => user.id},
        worker: "YscWeb.Workers.WelcomeEmailWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      {_result, subscription_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn -> WelcomeEmailWorker.perform(job) end,
          pattern: ~r/FROM "subscriptions"/i,
          caller_pids: [self()]
        )

      assert subscription_queries == 0
    end
  end

  describe "schedule_welcome_email/1" do
    test "schedules the welcome email", %{user: user} do
      assert {:ok, %Oban.Job{}} =
               WelcomeEmailWorker.schedule_welcome_email(user.id)
    end
  end
end
