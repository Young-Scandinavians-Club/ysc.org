defmodule YscWeb.FlowrouteWebhookControllerTest do
  @moduledoc """
  Tests for the FlowRoute webhook controller.

  Tests inbound SMS handling, delivery receipt processing,
  user matching, and opt-in/opt-out commands.

  Note: These tests call controller functions directly since the routes
  may not be configured yet. In production, routes would be added to router.ex.
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.FlowrouteWebhookController
  alias Ysc.Sms
  alias Ysc.Repo

  describe "handle_inbound_sms/2" do
    test "creates SMS received record for valid inbound SMS", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-test-message-123",
          from: "14155551234",
          to: "12061231234",
          body: "Hello, this is a test message"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"

      # Verify the SMS was stored
      sms_received =
        Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-test-message-123")

      assert sms_received != nil
      assert sms_received.from == "14155551234"
      assert sms_received.to == "12061231234"
      assert sms_received.body == "Hello, this is a test message"
      assert sms_received.provider == :flowroute
    end

    test "matches inbound SMS to user by phone number", %{conn: conn} do
      # Create a user with a phone number
      user = user_fixture(%{phone_number: "+14155551234"})

      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-user-match-123",
          from: "14155551234",
          to: "12061231234",
          body: "Message from known user"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      # Verify the SMS was matched to the user
      sms_received =
        Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-user-match-123")

      assert sms_received.user_id == user.id
    end

    test "handles STOP opt-out command", %{conn: conn} do
      # Create a user with SMS notifications enabled
      user = user_fixture(%{phone_number: "+14155551234"})

      user
      |> Ecto.Changeset.change(account_notifications_sms: true)
      |> Repo.update!()

      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-stop-123",
          from: "14155551234",
          to: "12061231234",
          body: "STOP"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      # Verify the user's SMS notifications were disabled
      updated_user = Repo.get!(Ysc.Accounts.User, user.id)
      refute updated_user.account_notifications_sms
    end

    test "handles START opt-in command", %{conn: conn} do
      # Create a user with SMS notifications disabled
      user = user_fixture(%{phone_number: "+14155551234"})

      user
      |> Ecto.Changeset.change(account_notifications_sms: false)
      |> Repo.update!()

      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-start-123",
          from: "14155551234",
          to: "12061231234",
          body: "START"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      # Verify the user's SMS notifications were enabled
      updated_user = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated_user.account_notifications_sms
    end

    test "handles SUBSCRIBE opt-in command", %{conn: conn} do
      user = user_fixture(%{phone_number: "+14155551234"})

      user
      |> Ecto.Changeset.change(account_notifications_sms: false)
      |> Repo.update!()

      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-subscribe-123",
          from: "14155551234",
          to: "12061231234",
          body: "SUBSCRIBE"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      updated_user = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated_user.account_notifications_sms
    end

    test "handles case-insensitive commands", %{conn: conn} do
      user = user_fixture(%{phone_number: "+14155551234"})

      user
      |> Ecto.Changeset.change(account_notifications_sms: true)
      |> Repo.update!()

      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-lowercase-stop-123",
          from: "14155551234",
          to: "12061231234",
          body: "stop"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      updated_user = Repo.get!(Ysc.Accounts.User, user.id)
      refute updated_user.account_notifications_sms
    end

    test "handles commands with whitespace", %{conn: conn} do
      user = user_fixture(%{phone_number: "+14155551234"})

      user
      |> Ecto.Changeset.change(account_notifications_sms: true)
      |> Repo.update!()

      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-whitespace-stop-123",
          from: "14155551234",
          to: "12061231234",
          body: "  STOP  "
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      updated_user = Repo.get!(Ysc.Accounts.User, user.id)
      refute updated_user.account_notifications_sms
    end

    test "stores raw payload", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-raw-payload-123",
          from: "14155551234",
          to: "12061231234",
          body: "Test message"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-raw-payload-123")

      assert sms_received.raw_payload == payload
    end

    test "parses timestamp correctly", %{conn: conn} do
      timestamp = "2025-12-05T10:30:00Z"

      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-timestamp-123",
          from: "14155551234",
          to: "12061231234",
          body: "Test message",
          timestamp: timestamp
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-timestamp-123")

      assert sms_received.provider_timestamp == ~U[2025-12-05 10:30:00Z]
    end

    test "returns 400 for invalid payload - missing data", %{conn: conn} do
      payload = %{"invalid" => "payload"}

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 400
      assert conn.resp_body == "Invalid payload"
    end

    test "returns 400 for invalid payload - missing message ID", %{conn: conn} do
      payload = %{
        "data" => %{
          "attributes" => %{
            "from" => "14155551234",
            "to" => "12061231234",
            "body" => "Test"
          }
        }
      }

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 400
      assert conn.resp_body == "Invalid payload"
    end

    test "prevents duplicate SMS records", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-duplicate-123",
          from: "14155551234",
          to: "12061231234",
          body: "Test message"
        )

      # First request should succeed
      conn1 = FlowrouteWebhookController.handle_inbound_sms(conn, payload)
      assert conn1.status == 200

      # Second request with same message_id should fail
      conn2 =
        FlowrouteWebhookController.handle_inbound_sms(build_conn(), payload)

      assert conn2.status == 400
      assert conn2.resp_body == "Failed to process"
    end

    test "stores MMS flag correctly", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-mms-123",
          from: "14155551234",
          to: "12061231234",
          body: "MMS message",
          is_mms: true
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-mms-123")

      assert sms_received.is_mms == true
    end
  end

  describe "handle_delivery_receipt/2" do
    test "creates delivery receipt for delivered status", %{conn: conn} do
      payload =
        build_delivery_receipt_payload(
          message_id: "mdr2-dlr-delivered-123",
          status: "delivered",
          status_code: "0",
          status_code_description: "Message delivered"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts =
        Sms.list_delivery_receipts_for_message(
          :flowroute,
          "mdr2-dlr-delivered-123"
        )

      assert length(receipts) == 1
      assert hd(receipts).status == :delivered
      assert hd(receipts).status_code == "0"
    end

    test "creates delivery receipt for failed status", %{conn: conn} do
      payload =
        build_delivery_receipt_payload(
          message_id: "mdr2-dlr-failed-123",
          status: "failed",
          status_code: "100",
          status_code_description: "Carrier rejected"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts =
        Sms.list_delivery_receipts_for_message(
          :flowroute,
          "mdr2-dlr-failed-123"
        )

      assert length(receipts) == 1
      assert hd(receipts).status == :failed
      assert hd(receipts).status_code == "100"
      assert hd(receipts).status_code_description == "Carrier rejected"
    end

    test "creates delivery receipt for message buffered status", %{conn: conn} do
      payload =
        build_delivery_receipt_payload(
          message_id: "mdr2-dlr-buffered-123",
          status: "message buffered"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts =
        Sms.list_delivery_receipts_for_message(
          :flowroute,
          "mdr2-dlr-buffered-123"
        )

      assert length(receipts) == 1
      assert hd(receipts).status == :message_buffered
    end

    test "creates delivery receipt for message sent status", %{conn: conn} do
      payload =
        build_delivery_receipt_payload(
          message_id: "mdr2-dlr-sent-123",
          status: "message sent"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts =
        Sms.list_delivery_receipts_for_message(:flowroute, "mdr2-dlr-sent-123")

      assert length(receipts) == 1
      assert hd(receipts).status == :message_sent
    end

    test "links delivery receipt to existing SMS message", %{conn: conn} do
      # First, create an SMS message record
      {:ok, sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: "mdr2-link-123",
          to: "14155551234",
          from: "12061231234",
          body: "Test message",
          status: :sent
        })

      payload =
        build_delivery_receipt_payload(
          message_id: "mdr2-link-123",
          status: "delivered"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts =
        Sms.list_delivery_receipts_for_message(:flowroute, "mdr2-link-123")

      assert length(receipts) == 1
      assert hd(receipts).sms_message_id == sms_message.id
    end

    test "updates SMS message status from delivery receipt", %{conn: conn} do
      # Create an SMS message in 'sent' status
      {:ok, _sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: "mdr2-status-update-123",
          to: "14155551234",
          from: "12061231234",
          body: "Test message",
          status: :sent
        })

      payload =
        build_delivery_receipt_payload(
          message_id: "mdr2-status-update-123",
          status: "delivered"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      # Verify delivery receipt was created and linked
      receipts =
        Sms.list_delivery_receipts_for_message(
          :flowroute,
          "mdr2-status-update-123"
        )

      assert length(receipts) == 1
      assert hd(receipts).status == :delivered
      # Verify linking occurred
      updated_sms =
        Sms.get_sms_message_by_provider_id(:flowroute, "mdr2-status-update-123")

      assert hd(receipts).sms_message_id == updated_sms.id
    end

    test "updates SMS message status to failed from delivery receipt", %{
      conn: conn
    } do
      {:ok, _sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: "mdr2-fail-update-123",
          to: "14155551234",
          from: "12061231234",
          body: "Test message",
          status: :sent
        })

      payload =
        build_delivery_receipt_payload(
          message_id: "mdr2-fail-update-123",
          status: "failed"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      # Verify delivery receipt was created and linked
      receipts =
        Sms.list_delivery_receipts_for_message(
          :flowroute,
          "mdr2-fail-update-123"
        )

      assert length(receipts) == 1
      assert hd(receipts).status == :failed
    end

    test "returns 400 for invalid delivery receipt payload", %{conn: conn} do
      payload = %{"invalid" => "payload"}

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 400
      assert conn.resp_body == "Invalid payload"
    end

    test "stores raw payload in delivery receipt", %{conn: conn} do
      payload =
        build_delivery_receipt_payload(
          message_id: "mdr2-dlr-raw-123",
          status: "delivered"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts =
        Sms.list_delivery_receipts_for_message(:flowroute, "mdr2-dlr-raw-123")

      assert hd(receipts).raw_payload == payload
    end

    test "parses delivery receipt timestamp correctly", %{conn: conn} do
      timestamp = "2025-12-05T14:30:00Z"

      payload =
        build_delivery_receipt_payload(
          message_id: "mdr2-dlr-timestamp-123",
          status: "delivered",
          timestamp: timestamp
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts =
        Sms.list_delivery_receipts_for_message(
          :flowroute,
          "mdr2-dlr-timestamp-123"
        )

      assert hd(receipts).provider_timestamp == ~U[2025-12-05 14:30:00Z]
    end
  end

  # Helper functions to build FlowRoute webhook payloads

  defp build_inbound_sms_payload(opts) do
    %{
      "data" => %{
        "id" => Keyword.fetch!(opts, :message_id),
        "attributes" => %{
          "from" => Keyword.fetch!(opts, :from),
          "to" => Keyword.fetch!(opts, :to),
          "body" => Keyword.fetch!(opts, :body),
          "is_mms" => Keyword.get(opts, :is_mms, false),
          "direction" => Keyword.get(opts, :direction, "inbound"),
          "status" => Keyword.get(opts, :status),
          "message_type" => Keyword.get(opts, :message_type, "sms"),
          "message_encoding" => Keyword.get(opts, :message_encoding, 0),
          "timestamp" => Keyword.get(opts, :timestamp),
          "amount_display" => Keyword.get(opts, :amount_display),
          "amount_nanodollars" => Keyword.get(opts, :amount_nanodollars)
        }
      }
    }
  end

  defp build_delivery_receipt_payload(opts) do
    %{
      "data" => %{
        "id" => Keyword.fetch!(opts, :message_id),
        "attributes" => %{
          "status" => Keyword.fetch!(opts, :status),
          "status_code" => Keyword.get(opts, :status_code),
          "status_code_description" =>
            Keyword.get(opts, :status_code_description),
          "body" => Keyword.get(opts, :body),
          "level" => Keyword.get(opts, :level),
          "timestamp" => Keyword.get(opts, :timestamp)
        }
      }
    }
  end
end
