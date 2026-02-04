defmodule YscWeb.Workers.MembershipPaymentReminderWorkerTest do
  @moduledoc """
  Tests for MembershipPaymentReminderWorker.
  """
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.MembershipPaymentReminderWorker
  import Ysc.AccountsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()
    %{user: user}
  end

  describe "perform/1" do
    test "sends 7-day reminder for user without membership", %{user: user} do
      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => user.id, "reminder_type" => "7day"},
        worker: "YscWeb.Workers.MembershipPaymentReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = MembershipPaymentReminderWorker.perform(job)
      assert result == :ok
    end

    test "sends 30-day reminder for user without membership", %{user: user} do
      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => user.id, "reminder_type" => "30day"},
        worker: "YscWeb.Workers.MembershipPaymentReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = MembershipPaymentReminderWorker.perform(job)
      assert result == :ok
    end

    test "skips reminder for user with active membership", %{user: user} do
      # Give user lifetime membership
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => user.id, "reminder_type" => "7day"},
        worker: "YscWeb.Workers.MembershipPaymentReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = MembershipPaymentReminderWorker.perform(job)
      assert result == :ok
    end

    test "handles missing user gracefully" do
      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => Ecto.ULID.generate(), "reminder_type" => "7day"},
        worker: "YscWeb.Workers.MembershipPaymentReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = MembershipPaymentReminderWorker.perform(job)
      assert result == :ok
    end

    test "returns error for unknown reminder type", %{user: user} do
      job = %Oban.Job{
        id: 1,
        args: %{"user_id" => user.id, "reminder_type" => "unknown"},
        worker: "YscWeb.Workers.MembershipPaymentReminderWorker",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = MembershipPaymentReminderWorker.perform(job)
      assert {:error, _} = result
    end
  end

  describe "schedule_7day_reminder/1" do
    test "schedules 7-day reminder", %{user: user} do
      result = MembershipPaymentReminderWorker.schedule_7day_reminder(user.id)
      # Oban.Testing.perform_job returns {:ok, job} tuple
      assert {:ok, %Oban.Job{}} = result
    end
  end

  describe "schedule_30day_reminder/1" do
    test "schedules 30-day reminder", %{user: user} do
      result = MembershipPaymentReminderWorker.schedule_30day_reminder(user.id)
      # Oban.Testing.perform_job returns {:ok, job} tuple
      assert {:ok, %Oban.Job{}} = result
    end
  end
end
