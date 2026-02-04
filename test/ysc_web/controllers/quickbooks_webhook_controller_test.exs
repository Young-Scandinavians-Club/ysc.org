defmodule YscWeb.QuickbooksWebhookControllerTest do
  @moduledoc """
  Tests for the QuickBooks webhook controller.

  Tests webhook signature verification, webhook event creation,
  and response handling for QuickBooks BillPayment notifications.
  """
  use YscWeb.ConnCase, async: false

  require Logger
  import Ecto.Query
  import Mox

  alias Ysc.Webhooks
  alias Ysc.Quickbooks.ClientMock
  alias Ysc.Repo

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set up webhook verifier token for tests
    Application.put_env(
      :ysc,
      :quickbooks_webhook_verifier_token,
      "test_verifier_token"
    )

    # Configure the QuickBooks client to use the mock
    Application.put_env(:ysc, :quickbooks_client, ClientMock)

    on_exit(fn ->
      Application.delete_env(:ysc, :quickbooks_webhook_verifier_token)
    end)

    :ok
  end

  describe "webhook/2" do
    test "creates webhook event for valid BillPayment Create notification", %{
      conn: conn
    } do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_123",
          operation: "Create"
        )

      # Mock the client call that will be made by the worker when it executes
      # With Oban in :inline mode, jobs execute immediately
      expect(ClientMock, :get_bill_payment, fn "bp_123" ->
        {:error, :not_found}
      end)

      conn =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"

      # Verify webhook event was created
      event_id = "123456789:BillPayment:bp_123:Create"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event != nil
      assert webhook_event.provider == :quickbooks
      assert webhook_event.event_type == "BillPayment.Create"
      # With Oban in :inline mode, the worker executes immediately
      # The state may be :pending, :processing, :processed, or :failed depending on worker execution
      assert webhook_event.state in [:pending, :processing, :processed, :failed]
    end

    test "creates webhook event for valid BillPayment Update notification", %{
      conn: conn
    } do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_456",
          operation: "Update"
        )

      # Mock the client call that will be made by the worker when it executes
      # With Oban in :inline mode, jobs execute immediately
      expect(ClientMock, :get_bill_payment, fn "bp_456" ->
        {:error, :not_found}
      end)

      conn =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 200

      # Verify webhook event was created
      event_id = "123456789:BillPayment:bp_456:Update"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event != nil
      assert webhook_event.event_type == "BillPayment.Update"
    end

    test "skips non-BillPayment entities", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "Invoice",
          entity_id: "inv_123",
          operation: "Create"
        )

      conn =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 200

      # Verify no webhook event was created for non-BillPayment
      event_id = "123456789:Invoice:inv_123:Create"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event == nil
    end

    test "skips non-Create/Update operations", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_123",
          operation: "Delete"
        )

      conn =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 200

      # Verify no webhook event was created for Delete operation
      event_id = "123456789:BillPayment:bp_123:Delete"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event == nil
    end

    test "handles duplicate webhook events idempotently", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_duplicate",
          operation: "Create"
        )

      # Mock the client call that will be made by the worker when it executes
      # With Oban in :inline mode, jobs execute immediately
      expect(ClientMock, :get_bill_payment, fn "bp_duplicate" ->
        {:error, :not_found}
      end)

      # First request
      conn1 =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn1.status == 200

      # Second request with same payload (duplicate)
      # The duplicate will be rejected, so no worker will execute
      conn2 =
        build_conn()
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn2.status == 200
      assert conn2.resp_body == "OK"

      # Verify only one webhook event exists
      event_id = "123456789:BillPayment:bp_duplicate:Create"

      webhook_events =
        Repo.all(
          from(w in Ysc.Webhooks.WebhookEvent,
            where: w.provider == "quickbooks" and w.event_id == ^event_id
          )
        )

      assert length(webhook_events) == 1
    end

    test "returns 401 when signature header is missing", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_123",
          operation: "Create"
        )

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 401
      assert conn.resp_body == "Unauthorized"
    end

    test "returns 401 when signature header is empty", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_123",
          operation: "Create"
        )

      conn =
        conn
        |> put_req_header("intuit-signature", "")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 401
    end

    test "handles empty event notifications array", %{conn: conn} do
      payload = %{"eventNotifications" => []}

      conn =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 200
    end

    test "handles missing event notifications key", %{conn: conn} do
      payload = %{"otherKey" => "value"}

      conn =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 200
    end

    test "handles notification with no entities", %{conn: conn} do
      payload = %{
        "eventNotifications" => [
          %{
            "realmId" => "123456789",
            "dataChangeEvent" => %{
              "entities" => []
            }
          }
        ]
      }

      conn =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 200
    end

    test "stores full payload in webhook event", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_123",
          operation: "Create"
        )

      # Mock the client call that will be made by the worker when it executes
      # With Oban in :inline mode, jobs execute immediately
      expect(ClientMock, :get_bill_payment, fn "bp_123" ->
        {:error, :not_found}
      end)

      conn =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 200

      event_id = "123456789:BillPayment:bp_123:Create"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event.payload == payload
    end

    test "handles multiple notifications in single webhook", %{conn: conn} do
      payload = %{
        "eventNotifications" => [
          %{
            "realmId" => "123456789",
            "dataChangeEvent" => %{
              "entities" => [
                %{
                  "name" => "BillPayment",
                  "id" => "bp_first",
                  "operation" => "Create"
                }
              ]
            }
          },
          %{
            "realmId" => "123456789",
            "dataChangeEvent" => %{
              "entities" => [
                %{
                  "name" => "BillPayment",
                  "id" => "bp_second",
                  "operation" => "Create"
                }
              ]
            }
          }
        ]
      }

      # Mock the client call that will be made by the worker when it executes
      # With Oban in :inline mode, jobs execute immediately
      # The controller only processes the first notification
      expect(ClientMock, :get_bill_payment, fn "bp_first" ->
        {:error, :not_found}
      end)

      conn =
        conn
        |> put_req_header("intuit-signature", "test_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", payload)

      assert conn.status == 200

      # Should process the first notification
      event_id = "123456789:BillPayment:bp_first:Create"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event != nil
    end
  end

  # Helper function to build QuickBooks webhook payloads
  defp build_quickbooks_webhook_payload(opts) do
    realm_id = Keyword.fetch!(opts, :realm_id)
    entity_name = Keyword.fetch!(opts, :entity_name)
    entity_id = Keyword.fetch!(opts, :entity_id)
    operation = Keyword.fetch!(opts, :operation)

    %{
      "eventNotifications" => [
        %{
          "realmId" => realm_id,
          "dataChangeEvent" => %{
            "entities" => [
              %{
                "name" => entity_name,
                "id" => entity_id,
                "operation" => operation
              }
            ]
          }
        }
      ]
    }
  end
end
