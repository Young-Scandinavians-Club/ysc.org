defmodule YscWeb.Workers.QuickbooksBillDeletedProcessorWorkerTest do
  @moduledoc """
  Tests for QuickBooks Bill deletion/void processor worker.

  Tests the flow of rejecting an expense report when its linked QuickBooks
  Bill is deleted or voided, keeping our records in sync with QuickBooks.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Workers.QuickbooksBillDeletedProcessorWorker
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Repo

  setup do
    user = user_fixture()
    %{user: user}
  end

  defp create_webhook_event(event_id, event_type, opts \\ []) do
    %Ysc.Webhooks.WebhookEvent{}
    |> Ysc.Webhooks.WebhookEvent.changeset(%{
      provider: "quickbooks",
      event_id: event_id,
      event_type: event_type,
      payload: %{},
      state: Keyword.get(opts, :state, :pending)
    })
    |> Repo.insert!()
  end

  defp deletion_job(webhook_event_id, bill_id) do
    %Oban.Job{
      id: 1,
      args: %{
        "webhook_event_id" => webhook_event_id,
        "bill_id" => bill_id
      },
      worker: "YscWeb.Workers.QuickbooksBillDeletedProcessorWorker",
      queue: "default",
      state: "available",
      attempt: 1
    }
  end

  describe "perform/1" do
    test "successfully rejects expense report when Bill is deleted", %{
      user: user
    } do
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "approved",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        create_webhook_event("123456789:Bill:bill_123:Delete", "Bill.Delete")

      job = deletion_job(webhook_event.id, "bill_123")

      assert :ok = QuickbooksBillDeletedProcessorWorker.perform(job)

      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "rejected"
      assert updated_report.quickbooks_sync_error =~ "bill_123"

      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "successfully rejects expense report when Bill is voided", %{
      user: user
    } do
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_456",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        create_webhook_event("123456789:Bill:bill_456:Void", "Bill.Void")

      job = deletion_job(webhook_event.id, "bill_456")

      assert :ok = QuickbooksBillDeletedProcessorWorker.perform(job)

      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "rejected"

      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "handles webhook event not found" do
      job = deletion_job(Ecto.ULID.generate(), "bill_123")

      assert {:error, :webhook_not_found} =
               QuickbooksBillDeletedProcessorWorker.perform(job)
    end

    test "skips webhook event already being processed", %{user: user} do
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "approved",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        create_webhook_event("123456789:Bill:bill_123:Delete", "Bill.Delete",
          state: :processing
        )

      job = deletion_job(webhook_event.id, "bill_123")

      assert :ok = QuickbooksBillDeletedProcessorWorker.perform(job)

      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "approved"
    end

    test "handles no expense report found for Bill ID" do
      webhook_event =
        create_webhook_event(
          "123456789:Bill:bill_nonexistent:Delete",
          "Bill.Delete"
        )

      job = deletion_job(webhook_event.id, "bill_nonexistent")

      assert :ok = QuickbooksBillDeletedProcessorWorker.perform(job)

      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "is idempotent when expense report is already rejected", %{
      user: user
    } do
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "rejected",
          quickbooks_bill_id: "bill_already_rejected",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        create_webhook_event(
          "123456789:Bill:bill_already_rejected:Delete",
          "Bill.Delete"
        )

      job = deletion_job(webhook_event.id, "bill_already_rejected")

      assert :ok = QuickbooksBillDeletedProcessorWorker.perform(job)

      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "rejected"

      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "does not overwrite an expense report already marked paid", %{
      user: user
    } do
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "paid",
          quickbooks_bill_id: "bill_already_paid",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        create_webhook_event(
          "123456789:Bill:bill_already_paid:Delete",
          "Bill.Delete"
        )

      job = deletion_job(webhook_event.id, "bill_already_paid")

      assert :ok = QuickbooksBillDeletedProcessorWorker.perform(job)

      # Left untouched for manual review rather than silently flipped either way.
      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "paid"

      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end
  end
end
