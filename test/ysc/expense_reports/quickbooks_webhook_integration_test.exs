defmodule Ysc.ExpenseReports.QuickbooksWebhookIntegrationTest do
  @moduledoc """
  Integration tests for QuickBooks webhook flow.

  Tests the complete flow from webhook receipt to expense report status update.
  """
  use YscWeb.ConnCase, async: false

  import Mox
  import Ysc.AccountsFixtures
  import Ecto.Query

  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Webhooks
  alias Ysc.Quickbooks.ClientMock
  alias Ysc.Repo

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure the QuickBooks client to use the mock
    Application.put_env(:ysc, :quickbooks_client, ClientMock)

    Application.put_env(
      :ysc,
      :quickbooks_webhook_verifier_token,
      "test_verifier_token"
    )

    on_exit(fn ->
      Application.delete_env(:ysc, :quickbooks_webhook_verifier_token)
    end)

    user = user_fixture()

    %{user: user, conn: build_conn()}
  end

  describe "end-to-end webhook flow" do
    test "processes webhook from receipt to expense report update", %{
      user: user
    } do
      # Create expense report with QuickBooks bill ID
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Integration test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_integration_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      # Build QuickBooks webhook payload
      payload = %{
        "eventNotifications" => [
          %{
            "realmId" => "123456789",
            "dataChangeEvent" => %{
              "entities" => [
                %{
                  "name" => "BillPayment",
                  "id" => "bp_integration_123",
                  "operation" => "Create"
                }
              ]
            }
          }
        ]
      }

      # Mock QuickBooks client to return BillPayment with linked Bill
      expect(ClientMock, :get_bill_payment, fn "bp_integration_123" ->
        {:ok,
         %{
           "Id" => "bp_integration_123",
           "LinkedTxn" => [
             %{
               "TxnId" => "bill_integration_123",
               "TxnType" => "Bill"
             }
           ]
         }}
      end)

      # Simulate webhook receipt via controller
      conn =
        build_conn()
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/webhooks/quickbooks", payload)

      assert conn.status == 200

      # Verify webhook event was created
      event_id = "123456789:BillPayment:bp_integration_123:Create"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event != nil

      # With Oban in :inline mode, the job is processed immediately when enqueued
      # So we need to reload the webhook event to get its current state
      webhook_event = Repo.reload(webhook_event)

      # If the job hasn't been processed yet (shouldn't happen in inline mode, but handle it)
      if webhook_event.state == :pending do
        job = %Oban.Job{
          id: 1,
          args: %{
            "webhook_event_id" => webhook_event.id,
            "bill_payment_id" => "bp_integration_123"
          },
          worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
          queue: "default",
          state: "available",
          attempt: 1
        }

        assert :ok =
                 YscWeb.Workers.QuickbooksBillPaymentProcessorWorker.perform(
                   job
                 )
      end

      # Verify expense report was updated to paid
      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "paid"

      # Verify webhook event was marked as processed
      updated_webhook = Repo.reload(webhook_event)
      assert updated_webhook.state == :processed
    end

    test "handles duplicate webhook idempotently", %{user: user} do
      # Create expense report
      expense_report =
        %ExpenseReport{
          user_id: user.id,
          purpose: "Duplicate test expense report",
          status: "submitted",
          quickbooks_bill_id: "bill_duplicate_123",
          reimbursement_method: "check"
        }
        |> Repo.insert!()

      payload = %{
        "eventNotifications" => [
          %{
            "realmId" => "123456789",
            "dataChangeEvent" => %{
              "entities" => [
                %{
                  "name" => "BillPayment",
                  "id" => "bp_duplicate_123",
                  "operation" => "Create"
                }
              ]
            }
          }
        ]
      }

      # Mock QuickBooks client to return BillPayment with linked Bill
      expect(ClientMock, :get_bill_payment, fn "bp_duplicate_123" ->
        {:ok,
         %{
           "Id" => "bp_duplicate_123",
           "LinkedTxn" => [
             %{
               "TxnId" => "bill_duplicate_123",
               "TxnType" => "Bill"
             }
           ]
         }}
      end)

      # First webhook
      conn1 =
        build_conn()
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/webhooks/quickbooks", payload)

      assert conn1.status == 200

      # Second webhook (duplicate)
      conn2 =
        build_conn()
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/webhooks/quickbooks", payload)

      assert conn2.status == 200

      # Verify only one webhook event was created (duplicate was rejected)
      event_id = "123456789:BillPayment:bp_duplicate_123:Create"

      webhook_events =
        Repo.all(
          from(w in Ysc.Webhooks.WebhookEvent,
            where: w.provider == "quickbooks" and w.event_id == ^event_id
          )
        )

      assert length(webhook_events) == 1

      # Verify expense report was updated by the first webhook (job was processed)
      # The duplicate webhook was correctly rejected, so only one job ran
      updated_report = Repo.get!(ExpenseReport, expense_report.id)
      assert updated_report.status == "paid"
    end

    test "handles webhook for non-existent expense report gracefully", %{
      user: _user
    } do
      payload = %{
        "eventNotifications" => [
          %{
            "realmId" => "123456789",
            "dataChangeEvent" => %{
              "entities" => [
                %{
                  "name" => "BillPayment",
                  "id" => "bp_nonexistent_123",
                  "operation" => "Create"
                }
              ]
            }
          }
        ]
      }

      # Mock QuickBooks client
      expect(ClientMock, :get_bill_payment, fn "bp_nonexistent_123" ->
        {:ok,
         %{
           "Id" => "bp_nonexistent_123",
           "LinkedTxn" => [
             %{
               "TxnId" => "bill_nonexistent_123",
               "TxnType" => "Bill"
             }
           ]
         }}
      end)

      # Receive webhook
      conn =
        build_conn()
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/webhooks/quickbooks", payload)

      assert conn.status == 200

      # Verify webhook event was created
      event_id = "123456789:BillPayment:bp_nonexistent_123:Create"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event != nil

      # Process the job
      job = %Oban.Job{
        id: 1,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_nonexistent_123"
        },
        worker: "YscWeb.Workers.QuickbooksBillPaymentProcessorWorker",
        queue: "default",
        state: "available",
        attempt: 1
      }

      # Should complete successfully even though expense report doesn't exist
      assert :ok =
               YscWeb.Workers.QuickbooksBillPaymentProcessorWorker.perform(job)

      # Verify webhook event was marked as processed
      updated_webhook = Repo.get!(Ysc.Webhooks.WebhookEvent, webhook_event.id)
      assert updated_webhook.state == :processed
    end
  end
end
