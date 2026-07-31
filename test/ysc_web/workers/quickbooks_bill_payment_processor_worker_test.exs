defmodule YscWeb.Workers.QuickbooksBillPaymentProcessorWorkerTest do
  @moduledoc """
  Tests for QuickBooks BillPayment processor worker.

  Tests the full flow of:
  - Fetching BillPayment from QuickBooks
  - Finding linked Bill
  - Finding expense report
  - Updating expense report status to paid
  """
  # async: false — setup pins :quickbooks_client for the whole module.
  use Ysc.DataCase, async: false

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
           "TotalAmt" => 100.0,
           "Line" => [
             %{
               "Amount" => 100.0,
               "LinkedTxn" => [
                 %{
                   "TxnId" => "bill_123",
                   "TxnType" => "Bill"
                 }
               ]
             }
           ]
         }}
      end)

      # Worker now confirms the Bill is fully paid (Balance == 0) before
      # marking the expense report paid.
      expect(ClientMock, :get_bill, fn "bill_123" ->
        {:ok, %{"Id" => "bill_123", "Balance" => 0}}
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
           "Line" => [%{"Amount" => 0.0, "LinkedTxn" => []}]
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
           "Line" => [
             %{
               "Amount" => 100.0,
               "LinkedTxn" => [
                 %{
                   "TxnId" => "inv_123",
                   "TxnType" => "Invoice"
                 }
               ]
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
           "Line" => [
             %{
               "Amount" => 100.0,
               "LinkedTxn" => [
                 %{
                   "TxnId" => "bill_nonexistent",
                   "TxnType" => "Bill"
                 }
               ]
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
           "TotalAmt" => 100.0,
           "Line" => [
             %{
               "Amount" => 100.0,
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
             }
           ]
         }}
      end)

      expect(ClientMock, :get_bill, fn "bill_123" ->
        {:ok, %{"Id" => "bill_123", "Balance" => 0}}
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

    test "handles expense report deleted between webhook receipt and processing",
         %{user: user} do
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
           "Line" => [
             %{
               "Amount" => 100.0,
               "LinkedTxn" => [
                 %{
                   "TxnId" => "bill_123",
                   "TxnType" => "Bill"
                 }
               ]
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

      # The report is gone by the time the job runs, so this hits the
      # report-not-found branch and is treated as nothing to do (not an
      # error) - there's no report left to leave in a stuck state.
      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "does not mark expense report as paid when Bill still has a remaining balance (partial payment)",
         %{user: user} do
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Partially paid report",
          status: "submitted",
          quickbooks_bill_id: "bill_partial",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_partial:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      expect(ClientMock, :get_bill_payment, fn "bp_partial" ->
        {:ok,
         %{
           "Id" => "bp_partial",
           "TotalAmt" => 50.0,
           "Line" => [
             %{
               "Amount" => 50.0,
               "LinkedTxn" => [
                 %{"TxnId" => "bill_partial", "TxnType" => "Bill"}
               ]
             }
           ]
         }}
      end)

      # Bill still has an outstanding balance - only part of it was paid.
      expect(ClientMock, :get_bill, fn "bill_partial" ->
        {:ok, %{"Id" => "bill_partial", "Balance" => 100.0}}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_partial"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "submitted"

      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "does not mark expense report as paid when BillPayment is voided (TotalAmt zero)",
         %{user: user} do
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Voided payment report",
          status: "submitted",
          quickbooks_bill_id: "bill_voided",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_voided:Update",
          event_type: "BillPayment.Update",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      # QuickBooks returns a voided BillPayment with the same Id/LinkedTxn
      # but TotalAmt reset to 0.
      expect(ClientMock, :get_bill_payment, fn "bp_voided" ->
        {:ok,
         %{
           "Id" => "bp_voided",
           "TotalAmt" => 0,
           "Line" => [
             %{
               "Amount" => 0,
               "LinkedTxn" => [%{"TxnId" => "bill_voided", "TxnType" => "Bill"}]
             }
           ]
         }}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_voided"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "submitted"

      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "marks multiple expense reports paid when one BillPayment settles multiple Bills",
         %{user: user} do
      report_a =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Report A",
          status: "submitted",
          quickbooks_bill_id: "bill_a",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      report_b =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Report B",
          status: "approved",
          quickbooks_bill_id: "bill_b",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_split:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      expect(ClientMock, :get_bill_payment, fn "bp_split" ->
        {:ok,
         %{
           "Id" => "bp_split",
           "TotalAmt" => 200.0,
           "Line" => [
             %{
               "Amount" => 100.0,
               "LinkedTxn" => [%{"TxnId" => "bill_a", "TxnType" => "Bill"}]
             },
             %{
               "Amount" => 100.0,
               "LinkedTxn" => [%{"TxnId" => "bill_b", "TxnType" => "Bill"}]
             }
           ]
         }}
      end)

      # Order-independent: the worker doesn't guarantee it processes linked
      # Bills in any particular order.
      expect(ClientMock, :get_bill, 2, fn bill_id ->
        assert bill_id in ["bill_a", "bill_b"]
        {:ok, %{"Id" => bill_id, "Balance" => 0}}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_split"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      assert Repo.get!(ExpenseReport, report_a.id).status == "paid"
      assert Repo.get!(ExpenseReport, report_b.id).status == "paid"
    end

    test "is idempotent when expense report is already marked paid", %{
      user: user
    } do
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Already paid report",
          status: "paid",
          quickbooks_bill_id: "bill_already_paid",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_already_paid:Update",
          event_type: "BillPayment.Update",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      expect(ClientMock, :get_bill_payment, fn "bp_already_paid" ->
        {:ok,
         %{
           "Id" => "bp_already_paid",
           "TotalAmt" => 100.0,
           "Line" => [
             %{
               "Amount" => 100.0,
               "LinkedTxn" => [
                 %{"TxnId" => "bill_already_paid", "TxnType" => "Bill"}
               ]
             }
           ]
         }}
      end)

      expect(ClientMock, :get_bill, fn "bill_already_paid" ->
        {:ok, %{"Id" => "bill_already_paid", "Balance" => 0}}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_already_paid"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      assert Repo.get!(ExpenseReport, expense_report.id).status == "paid"

      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end

    test "does not automatically flip a rejected report to paid", %{
      user: user
    } do
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Rejected report",
          status: "rejected",
          quickbooks_bill_id: "bill_rejected",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      webhook_event =
        %Ysc.Webhooks.WebhookEvent{}
        |> Ysc.Webhooks.WebhookEvent.changeset(%{
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_rejected:Create",
          event_type: "BillPayment.Create",
          payload: %{},
          state: :pending
        })
        |> Repo.insert!()

      expect(ClientMock, :get_bill_payment, fn "bp_rejected" ->
        {:ok,
         %{
           "Id" => "bp_rejected",
           "TotalAmt" => 100.0,
           "Line" => [
             %{
               "Amount" => 100.0,
               "LinkedTxn" => [
                 %{"TxnId" => "bill_rejected", "TxnType" => "Bill"}
               ]
             }
           ]
         }}
      end)

      expect(ClientMock, :get_bill, fn "bill_rejected" ->
        {:ok, %{"Id" => "bill_rejected", "Balance" => 0}}
      end)

      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_rejected"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksBillPaymentProcessorWorker.perform(job)

      assert Repo.get!(ExpenseReport, expense_report.id).status == "rejected"
    end
  end
end
