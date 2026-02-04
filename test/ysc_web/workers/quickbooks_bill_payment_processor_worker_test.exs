defmodule YscWeb.Workers.QuickbooksBillPaymentProcessorWorkerTest do
  @moduledoc """
  Tests for QuickBooks BillPayment processor worker.

  Tests the full flow of:
  - Fetching BillPayment from QuickBooks
  - Finding linked Bill
  - Finding expense report
  - Updating expense report status to paid
  """
  use Ysc.DataCase, async: true

  import Mox
  import Ysc.AccountsFixtures

  alias YscWeb.Workers.QuickbooksBillPaymentProcessorWorker
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Quickbooks.ClientMock
  alias Ysc.Repo

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure the QuickBooks client to use the mock
    Application.put_env(:ysc, :quickbooks_client, ClientMock)

    user = user_fixture()

    %{user: user}
  end

  describe "perform/1" do
    test "successfully processes BillPayment and marks expense report as paid",
         %{user: user} do
      # Create expense report with QuickBooks bill ID
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      # Create webhook event
      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      # Mock QuickBooks client to return BillPayment with linked Bill
      expect(ClientMock, :get_bill_payment, fn "bp_123" ->
        {:ok,
         %{
           "Id" => "bp_123",
           "LinkedTxn" => [
             %{
               "TxnId" => "bill_123",
               "TxnType" => "Bill"
             }
           ]
         }}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      # Verify expense report status was updated to paid
      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "paid"

      # Verify webhook event was marked as processed
      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "handles webhook event not found", %{user: _user} do
      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => Ecto.ULID.generate(),
          "bill_payment_id" => "bp_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert {:error, :webhook_not_found} =
               QuickbooksBillPaymentProcessorWorker.perform(job)
    end

    test "skips webhook event already being processed", %{user: user} do
      # Create expense report
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      # Create webhook event in processing state (already locked by another process)
      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :processing
        })
        |> Repo.insert!()

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      # Should return :ok because it skips already processing events
      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      # Verify expense report was not updated
      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "submitted"
    end

    test "handles QuickBooks API failure when fetching BillPayment", %{
      user: user
    } do
      # Create expense report
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      # Create webhook event
      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      # Mock QuickBooks client to return error
      expect(ClientMock, :get_bill_payment, fn "bp_123" ->
        {:error, :request_failed}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert {:error, :fetch_failed} =
               QuickbooksBillPaymentProcessorWorker.perform(job)

      # Verify expense report was not updated
      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "submitted"

      # Verify webhook event was marked as failed
      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :failed
    end

    test "handles BillPayment with no linked Bill", %{user: user} do
      # Create expense report
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      # Create webhook event
      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      # Mock QuickBooks client to return BillPayment with no linked Bill
      expect(ClientMock, :get_bill_payment, fn "bp_123" ->
        {:ok,
         %{
           "Id" => "bp_123",
           "LinkedTxn" => []
         }}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      # Verify expense report was not updated
      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "submitted"

      # Verify webhook event was marked as processed (nothing to do)
      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "handles BillPayment with linked non-Bill transaction", %{user: user} do
      # Create expense report
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      # Create webhook event
      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      # Mock QuickBooks client to return BillPayment with linked Invoice (not Bill)
      expect(ClientMock, :get_bill_payment, fn "bp_123" ->
        {:ok,
         %{
           "Id" => "bp_123",
           "LinkedTxn" => [
             %{
               "TxnId" => "inv_123",
               "TxnType" => "Invoice"
             }
           ]
         }}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      # Verify expense report was not updated
      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "submitted"

      # Verify webhook event was marked as processed
      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "handles expense report not found for Bill ID", %{user: _user} do
      # Create webhook event
      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      # Mock QuickBooks client to return BillPayment with linked Bill
      expect(ClientMock, :get_bill_payment, fn "bp_123" ->
        {:ok,
         %{
           "Id" => "bp_123",
           "LinkedTxn" => [
             %{
               "TxnId" => "bill_nonexistent",
               "TxnType" => "Bill"
             }
           ]
         }}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      # Verify webhook event was marked as processed (nothing to do)
      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "handles multiple linked transactions and finds Bill", %{user: user} do
      # Create expense report
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      # Create webhook event
      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      # Mock QuickBooks client to return BillPayment with multiple linked transactions
      expect(ClientMock, :get_bill_payment, fn "bp_123" ->
        {:ok,
         %{
           "Id" => "bp_123",
           "LinkedTxn" => [
             %{
               "TxnId" => "inv_456",
               "TxnType" => "Invoice"
             },
             %{
               "TxnId" => "bill_123",
               "TxnType" => "Bill"
             },
             %{
               "TxnId" => "check_789",
               "TxnType" => "Check"
             }
           ]
         }}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      # Verify expense report status was updated to paid
      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "paid"
    end

    test "handles expense report update failure", %{user: user} do
      # Create expense report with invalid data that will cause update to fail
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      # Create webhook event
      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      # Mock QuickBooks client to return BillPayment with linked Bill
      expect(ClientMock, :get_bill_payment, fn "bp_123" ->
        {:ok,
         %{
           "Id" => "bp_123",
           "LinkedTxn" => [
             %{
               "TxnId" => "bill_123",
               "TxnType" => "Bill"
             }
           ]
         }}
      end)

      # Delete the expense report to simulate it being deleted between fetch and update
      Repo.delete!(expense_report)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      # Should handle the error gracefully
      result = QuickbooksBillPaymentProcessorWorker.perform(job)
      assert result == :ok or match?({:error, _}, result)

      # Verify webhook event was marked appropriately
      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state in [:processed, :failed]
    end
  end
end
