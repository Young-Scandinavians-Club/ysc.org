defmodule YscWeb.QuickbooksWebhookControllerTest do
  @moduledoc """
  Tests for the QuickBooks webhook controller.

  Tests webhook signature verification, webhook event creation,
  and response handling for QuickBooks BillPayment notifications.
  """
  use YscWeb.ConnCase, async: false

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

      conn = signed_webhook_post(conn, payload)

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

      conn = signed_webhook_post(conn, payload)

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

      conn = signed_webhook_post(conn, payload)

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

      conn = signed_webhook_post(conn, payload)

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

    test "creates webhook event for Bill Delete notification", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "Bill",
          entity_id: "bill_deleted_123",
          operation: "Delete"
        )

      conn = signed_webhook_post(conn, payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"

      event_id = "123456789:Bill:bill_deleted_123:Delete"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event != nil
      assert webhook_event.event_type == "Bill.Delete"
    end

    test "creates webhook event for Bill Void notification", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "Bill",
          entity_id: "bill_voided_123",
          operation: "Void"
        )

      conn = signed_webhook_post(conn, payload)

      assert conn.status == 200

      event_id = "123456789:Bill:bill_voided_123:Void"

      webhook_event =
        Webhooks.get_webhook_event_by_provider_and_event_id(
          "quickbooks",
          event_id
        )

      assert webhook_event != nil
      assert webhook_event.event_type == "Bill.Void"
    end

    test "skips Bill Create/Update operations (only Delete/Void are handled)",
         %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "Bill",
          entity_id: "bill_created_123",
          operation: "Create"
        )

      conn = signed_webhook_post(conn, payload)

      assert conn.status == 200

      event_id = "123456789:Bill:bill_created_123:Create"

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
      conn1 = signed_webhook_post(conn, payload)

      assert conn1.status == 200

      # Second request with same payload (duplicate)
      # The duplicate will be rejected, so no worker will execute
      conn2 = signed_webhook_post(build_conn(), payload)

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

      conn = signed_webhook_post(conn, payload)

      assert conn.status == 200
    end

    test "handles missing event notifications key", %{conn: conn} do
      payload = %{"otherKey" => "value"}

      conn = signed_webhook_post(conn, payload)

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

      conn = signed_webhook_post(conn, payload)

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

      conn = signed_webhook_post(conn, payload)

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

      conn = signed_webhook_post(conn, payload)

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

  describe "HMAC signature verification (security)" do
    test "accepts request with correct HMAC-SHA256 signature", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "999",
          entity_name: "BillPayment",
          entity_id: "bp_hmac",
          operation: "Create"
        )

      expect(ClientMock, :get_bill_payment, fn "bp_hmac" ->
        {:error, :not_found}
      end)

      conn = signed_webhook_post(conn, payload)

      assert conn.status == 200
    end

    test "rejects request with wrong HMAC (tampered body)", %{conn: conn} do
      real_payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_real",
          operation: "Create"
        )

      tampered_payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_injected",
          operation: "Create"
        )

      # Sign the REAL payload body, but send the TAMPERED body — simulates message tampering.
      token = Application.get_env(:ysc, :quickbooks_webhook_verifier_token)
      real_body = Jason.encode!(real_payload)
      sig = :crypto.mac(:hmac, :sha256, token, real_body) |> Base.encode64()

      tampered_body = Jason.encode!(tampered_payload)

      conn =
        conn
        |> put_req_header("intuit-signature", sig)
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", tampered_body)

      assert conn.status == 401
      assert conn.resp_body == "Unauthorized"
    end

    test "rejects request with a completely forged signature", %{conn: conn} do
      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_forged",
          operation: "Create"
        )

      conn =
        conn
        |> put_req_header(
          "intuit-signature",
          "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", Jason.encode!(payload))

      assert conn.status == 401
    end

    test "rejects request when verifier token is not configured", %{conn: conn} do
      # Remove the verifier token to simulate misconfiguration
      Application.delete_env(:ysc, :quickbooks_webhook_verifier_token)

      payload =
        build_quickbooks_webhook_payload(
          realm_id: "123456789",
          entity_name: "BillPayment",
          entity_id: "bp_notoken",
          operation: "Create"
        )

      conn =
        conn
        |> put_req_header("intuit-signature", "any_signature")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/quickbooks", Jason.encode!(payload))

      assert conn.status == 401
    end
  end

  # Sends a POST to the QuickBooks webhook endpoint with a correctly signed body.
  # We pre-encode to a JSON string so the signature and the raw request body are
  # guaranteed to be the same bytes. Passing the body as a binary (not a map)
  # tells Phoenix.ConnTest to use it verbatim, preventing any re-encoding.
  defp signed_webhook_post(conn, payload_map) do
    token = Application.get_env(:ysc, :quickbooks_webhook_verifier_token)
    body = Jason.encode!(payload_map)
    sig = :crypto.mac(:hmac, :sha256, token, body) |> Base.encode64()

    conn
    |> put_req_header("intuit-signature", sig)
    |> put_req_header("content-type", "application/json")
    |> post("/webhooks/quickbooks", body)
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
