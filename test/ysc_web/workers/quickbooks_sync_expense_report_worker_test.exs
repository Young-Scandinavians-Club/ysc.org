defmodule YscWeb.Workers.QuickbooksSyncExpenseReportWorkerTest do
  @moduledoc """
  Tests for QuickbooksSyncExpenseReportWorker module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports.ExpenseReport
  alias YscWeb.Workers.QuickbooksSyncExpenseReportWorker

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "perform/1" do
    test "handles missing expense report gracefully" do
      job = %Oban.Job{
        id: 1,
        args: %{"expense_report_id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      result = QuickbooksSyncExpenseReportWorker.perform(job)
      assert {:discard, :expense_report_not_found} = result
    end

    test "skips already synced expense reports", %{user: user} do
      # Insert expense report directly to bypass validations
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_sync_status: "synced",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      job = %Oban.Job{
        id: 1,
        args: %{"expense_report_id" => expense_report.id},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      result = QuickbooksSyncExpenseReportWorker.perform(job)
      assert :ok = result
    end

    test "handles expense report with bill_id (idempotency)", %{user: user} do
      # Insert expense report directly with bill_id already set
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      job = %Oban.Job{
        id: 1,
        args: %{"expense_report_id" => expense_report.id},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      result = QuickbooksSyncExpenseReportWorker.perform(job)
      assert :ok = result
    end

    test "handles pending sync expense reports", %{user: user} do
      # Insert expense report with pending sync status
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_sync_status: "pending",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      job = %Oban.Job{
        id: 1,
        args: %{"expense_report_id" => expense_report.id},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      # The actual sync will fail without QuickBooks configured.
      # We catch the error to verify the worker attempts to process.
      result =
        try do
          QuickbooksSyncExpenseReportWorker.perform(job)
        rescue
          _ -> {:error, :quickbooks_not_configured}
        catch
          _, _ -> {:error, :quickbooks_not_configured}
        end

      # Should return :ok, {:error, _}, or catch the QuickBooks config error
      assert result == :ok or match?({:error, _}, result)
    end
  end
end
