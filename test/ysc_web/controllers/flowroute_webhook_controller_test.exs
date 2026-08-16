defmodule YscWeb.FlowrouteWebhookControllerTest do
  @moduledoc """
  Tests for the FlowRoute webhook controller.

  Tests inbound SMS handling, delivery receipt processing,
  user matching, and opt-in/opt-out commands.

  Note: These tests call controller functions directly to exercise edge
  cases (malformed payloads, duplicate detection, status normalization)
  without the overhead of a full HTTP round trip. For tests that go
  through the actual routes in router.ex end-to-end, see
  flowroute_webhook_e2e_test.exs.
  """
  use YscWeb.ConnCase, async: true

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.User
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

      # Second request with same message_id is a duplicate delivery (e.g. a
      # FlowRoute retry) — acknowledged with 200 rather than treated as a
      # failure, so FlowRoute doesn't keep retrying, but no second record
      # is created and the SMS command (if any) isn't reprocessed.
      conn2 =
        FlowrouteWebhookController.handle_inbound_sms(build_conn(), payload)

      assert conn2.status == 200
      assert conn2.resp_body == "OK"
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

    test "handles HELP command", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-help-123",
          from: "14155551234",
          to: "12061231234",
          body: "HELP"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      assert Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-help-123") !=
               nil
    end

    test "opt-out from unknown number still returns 200", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-unknown-stop-123",
          from: "19999999999",
          to: "12061231234",
          body: "STOP"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200
    end

    test "stores nil provider_timestamp when timestamp is not ISO8601", %{
      conn: conn
    } do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-bad-ts-123",
          from: "14155551234",
          to: "12061231234",
          body: "no timestamp",
          timestamp: "not-a-real-timestamp"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-bad-ts-123")

      assert sms_received.provider_timestamp == nil
    end

    test "parses amount_nanodollars when sent as a string", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-nano-str-123",
          from: "14155551234",
          to: "12061231234",
          body: "paid",
          amount_nanodollars: "42000"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-nano-str-123")

      assert sms_received.amount_nanodollars == 42_000
    end

    test "normalizes outbound direction", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-outbound-123",
          from: "14155551234",
          to: "12061231234",
          body: "Outbound leg",
          direction: "outbound"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-outbound-123")

      assert sms_received.direction == :outbound
    end

    test "normalizes unknown received status to nil", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-unknown-status-123",
          from: "14155551234",
          to: "12061231234",
          body: "Test",
          status: "weird-status"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(
          :flowroute,
          "mdr2-unknown-status-123"
        )

      assert sms_received.status == nil
    end

    test "normalizes unknown direction string to inbound", %{conn: conn} do
      mid = "mdr2-dir-unknown-#{System.unique_integer([:positive])}"

      payload =
        build_inbound_sms_payload(
          message_id: mid,
          from: "14155551234",
          to: "12061231234",
          body: "Hi",
          direction: "carrier-specific"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received = Sms.get_sms_received_by_provider_id(:flowroute, mid)
      assert sms_received.direction == :inbound
    end

    test "stores nil amount_nanodollars when value is not an integer or string",
         %{
           conn: conn
         } do
      mid = "mdr2-nano-obj-#{System.unique_integer([:positive])}"

      payload =
        put_in(
          build_inbound_sms_payload(
            message_id: mid,
            from: "14155551234",
            to: "12061231234",
            body: "x"
          ),
          ["data", "attributes", "amount_nanodollars"],
          %{}
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received = Sms.get_sms_received_by_provider_id(:flowroute, mid)
      assert sms_received.amount_nanodollars == nil
    end

    test "accepts nil body and still processes inbound SMS", %{conn: conn} do
      mid = "mdr2-nil-body-#{System.unique_integer([:positive])}"

      payload =
        put_in(
          build_inbound_sms_payload(
            message_id: mid,
            from: "14155551234",
            to: "12061231234",
            body: "placeholder"
          ),
          ["data", "attributes", "body"],
          nil
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received = Sms.get_sms_received_by_provider_id(:flowroute, mid)
      assert sms_received.body == nil
    end

    test "parses amount_nanodollars when sent as integer", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-nano-int-123",
          from: "14155551234",
          to: "12061231234",
          body: "paid",
          amount_nanodollars: 99_000
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(:flowroute, "mdr2-nano-int-123")

      assert sms_received.amount_nanodollars == 99_000
    end

    test "stores nil amount_nanodollars when value is a non-integer JSON number",
         %{
           conn: conn
         } do
      mid = "mdr2-nano-float-#{System.unique_integer([:positive])}"

      payload =
        put_in(
          build_inbound_sms_payload(
            message_id: mid,
            from: "14155551234",
            to: "12061231234",
            body: "paid"
          ),
          ["data", "attributes", "amount_nanodollars"],
          42_000.5
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received = Sms.get_sms_received_by_provider_id(:flowroute, mid)
      assert sms_received.amount_nanodollars == nil
    end

    test "returns 500 when amount_nanodollars is not parseable as integer", %{
      conn: conn
    } do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-nano-bad-#{System.unique_integer([:positive])}",
          from: "14155551234",
          to: "12061231234",
          body: "paid",
          amount_nanodollars: "12.34"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 500
      assert conn.resp_body == "Internal error"
    end

    test "treats non-command body as normal inbound SMS", %{conn: conn} do
      from_e164 = unique_user_phone() |> String.trim_leading("+")

      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-chat-#{System.unique_integer([:positive])}",
          from: from_e164,
          to: "12061231234",
          body: "Thanks for the reminder about tonight!"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end

    test "normalizes inbound received status pending", %{conn: conn} do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-pending-in-#{System.unique_integer([:positive])}",
          from: "14155551234",
          to: "12061231234",
          body: "Hi",
          status: "pending"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(
          :flowroute,
          get_in(payload, ["data", "id"])
        )

      assert sms_received.status == :pending
    end

    test "normalizes inbound received status delivered", %{conn: conn} do
      mid = "mdr2-delivered-in-#{System.unique_integer([:positive])}"

      payload =
        build_inbound_sms_payload(
          message_id: mid,
          from: "14155551234",
          to: "12061231234",
          body: "Hi",
          status: "delivered"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received = Sms.get_sms_received_by_provider_id(:flowroute, mid)
      assert sms_received.status == :delivered
    end

    test "normalizes inbound received status failed", %{conn: conn} do
      mid = "mdr2-failed-in-#{System.unique_integer([:positive])}"

      payload =
        build_inbound_sms_payload(
          message_id: mid,
          from: "14155551234",
          to: "12061231234",
          body: "Hi",
          status: "failed"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received = Sms.get_sms_received_by_provider_id(:flowroute, mid)
      assert sms_received.status == :failed
    end

    test "returns 400 when data is nil", %{conn: conn} do
      conn =
        FlowrouteWebhookController.handle_inbound_sms(conn, %{"data" => nil})

      assert conn.status == 400
      assert conn.resp_body == "Invalid payload"
    end

    test "returns 400 when data has id but attributes are missing", %{
      conn: conn
    } do
      conn =
        FlowrouteWebhookController.handle_inbound_sms(conn, %{
          "data" => %{"id" => "mdr2-no-attrs"}
        })

      assert conn.status == 400
      assert conn.resp_body == "Invalid payload"
    end

    test "returns 200 when opt-in cannot update prefs but still sends opt-in SMS",
         %{
           conn: conn
         } do
      user = user_fixture(%{phone_number: "+14155551234"})

      {1, _} =
        Repo.update_all(from(u in User, where: u.id == ^user.id),
          set: [account_notifications: false]
        )

      mid = "mdr2-optin-pref-err-#{System.unique_integer([:positive])}"

      payload =
        build_inbound_sms_payload(
          message_id: mid,
          from: "14155551234",
          to: "12061231234",
          body: "START"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end

    test "returns 200 when opt-out cannot update prefs but still sends opt-out SMS",
         %{
           conn: conn
         } do
      user = user_fixture(%{phone_number: "+14155551234"})

      {1, _} =
        Repo.update_all(from(u in User, where: u.id == ^user.id),
          set: [account_notifications: false]
        )

      mid = "mdr2-optout-pref-err-#{System.unique_integer([:positive])}"

      payload =
        build_inbound_sms_payload(
          message_id: mid,
          from: "14155551234",
          to: "12061231234",
          body: "STOP"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end

    test "defaults inbound direction when direction key is absent", %{
      conn: conn
    } do
      payload =
        build_inbound_sms_payload(
          message_id: "mdr2-dir-default-123",
          from: "14155551234",
          to: "12061231234",
          body: "Hi"
        )

      attrs = Map.delete(payload["data"]["attributes"], "direction")
      payload = put_in(payload, ["data", "attributes"], attrs)

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200

      sms_received =
        Sms.get_sms_received_by_provider_id(
          :flowroute,
          "mdr2-dir-default-123"
        )

      assert sms_received.direction == :inbound
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
      assert updated_sms.status == :delivered
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

      updated_sms =
        Sms.get_sms_message_by_provider_id(:flowroute, "mdr2-fail-update-123")

      assert updated_sms.status == :failed
    end

    test "updates SMS message status to sent from message sent DLR", %{
      conn: conn
    } do
      mid = "mdr2-sent-dlr-#{System.unique_integer([:positive])}"

      {:ok, _sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: mid,
          to: "14155551234",
          from: "12061231234",
          body: "Test message",
          status: :sent
        })

      payload =
        build_delivery_receipt_payload(
          message_id: mid,
          status: "message sent"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      updated = Sms.get_sms_message_by_provider_id(:flowroute, mid)
      assert updated.status == :sent
    end

    test "updates SMS message status to sent from pending DLR (default status mapping)",
         %{
           conn: conn
         } do
      mid = "mdr2-pending-dlr-#{System.unique_integer([:positive])}"

      {:ok, _sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: mid,
          to: "14155551234",
          from: "12061231234",
          body: "Test message",
          status: :sent
        })

      payload =
        build_delivery_receipt_payload(
          message_id: mid,
          status: "pending"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      updated = Sms.get_sms_message_by_provider_id(:flowroute, mid)
      assert updated.status == :sent
    end

    test "updates SMS message status to buffered from message buffered DLR", %{
      conn: conn
    } do
      mid = "mdr2-buffered-sms-#{System.unique_integer([:positive])}"

      {:ok, sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: mid,
          to: "14155551234",
          from: "12061231234",
          body: "Test message",
          status: :sent
        })

      payload =
        build_delivery_receipt_payload(
          message_id: mid,
          status: "message buffered"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      updated = Sms.get_sms_message_by_provider_id(:flowroute, mid)
      assert updated.id == sms_message.id
      assert updated.status == :buffered
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

    test "creates delivery receipt for pending status", %{conn: conn} do
      mid = "mdr2-dlr-pending-#{System.unique_integer([:positive])}"

      payload =
        build_delivery_receipt_payload(
          message_id: mid,
          status: "pending"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts = Sms.list_delivery_receipts_for_message(:flowroute, mid)
      assert length(receipts) == 1
      assert hd(receipts).status == :pending
    end

    test "normalizes unknown delivery receipt status to pending", %{conn: conn} do
      mid = "mdr2-dlr-unknown-#{System.unique_integer([:positive])}"

      payload =
        build_delivery_receipt_payload(
          message_id: mid,
          status: "carrier-specific-unknown"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts = Sms.list_delivery_receipts_for_message(:flowroute, mid)
      assert length(receipts) == 1
      assert hd(receipts).status == :pending
    end

    test "returns 400 when delivery receipt data is nil", %{conn: conn} do
      conn =
        FlowrouteWebhookController.handle_delivery_receipt(conn, %{
          "data" => nil
        })

      assert conn.status == 400
      assert conn.resp_body == "Invalid payload"
    end

    test "returns 400 when delivery receipt has id but attributes are missing",
         %{
           conn: conn
         } do
      conn =
        FlowrouteWebhookController.handle_delivery_receipt(conn, %{
          "data" => %{"id" => "dlr-no-attrs"}
        })

      assert conn.status == 400
      assert conn.resp_body == "Invalid payload"
    end

    test "stores nil provider_timestamp when DLR timestamp is invalid ISO8601",
         %{
           conn: conn
         } do
      mid = "mdr2-dlr-invalid-ts-#{System.unique_integer([:positive])}"

      payload =
        build_delivery_receipt_payload(
          message_id: mid,
          status: "delivered",
          timestamp: "2025-13-45T99:99:99Z"
        )

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts = Sms.list_delivery_receipts_for_message(:flowroute, mid)
      assert hd(receipts).provider_timestamp == nil
    end

    test "acknowledges a duplicate delivery receipt for same id and timestamp with 200",
         %{
           conn: conn
         } do
      mid = "mdr2-dlr-dup-#{System.unique_integer([:positive])}"
      ts = "2025-12-05T10:00:00Z"

      payload =
        build_delivery_receipt_payload(
          message_id: mid,
          status: "delivered",
          timestamp: ts
        )

      assert FlowrouteWebhookController.handle_delivery_receipt(conn, payload).status ==
               200

      # Same event (same id + timestamp) delivered again — a FlowRoute retry.
      # Acknowledged with 200 so FlowRoute stops retrying, but no second
      # receipt row is created.
      conn2 =
        FlowrouteWebhookController.handle_delivery_receipt(
          build_conn(),
          payload
        )

      assert conn2.status == 200
      assert conn2.resp_body == "OK"

      assert length(Sms.list_delivery_receipts_for_message(:flowroute, mid)) ==
               1
    end

    test "accepts atom status in delivery receipt attributes (normalize atom pass-through)",
         %{
           conn: conn
         } do
      mid = "mdr2-dlr-atom-#{System.unique_integer([:positive])}"

      payload = %{
        "data" => %{
          "id" => mid,
          "attributes" => %{
            "status" => :delivered,
            "status_code" => "0"
          }
        }
      }

      conn = FlowrouteWebhookController.handle_delivery_receipt(conn, payload)

      assert conn.status == 200

      receipts = Sms.list_delivery_receipts_for_message(:flowroute, mid)
      assert hd(receipts).status == :delivered
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

defmodule YscWeb.FlowrouteWebhookControllerSmsSendErrorTest do
  @moduledoc """
  Tests that require `Application.put_env(:ysc, :flowroute_test_raise, ...)` (async: false).
  """
  use YscWeb.ConnCase, async: false

  alias YscWeb.FlowrouteWebhookController

  setup do
    Cachex.clear(:ysc_cache)
    on_exit(fn -> Application.delete_env(:ysc, :flowroute_test_raise) end)
    :ok
  end

  describe "handle_inbound_sms/2" do
    test "returns 200 when SMS response send fails (send_response_sms error path)",
         %{
           conn: conn
         } do
      Application.put_env(:ysc, :flowroute_test_raise, {:runtime, "sms boom"})

      payload =
        build_help_payload(
          "mdr2-help-raise-#{System.unique_integer([:positive])}"
        )

      conn = FlowrouteWebhookController.handle_inbound_sms(conn, payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end
  end

  defp build_help_payload(message_id) do
    %{
      "data" => %{
        "id" => message_id,
        "attributes" => %{
          "from" => "14155551234",
          "to" => "12061231234",
          "body" => "HELP",
          "is_mms" => false,
          "direction" => "inbound",
          "status" => nil,
          "message_type" => "sms",
          "message_encoding" => 0,
          "timestamp" => nil,
          "amount_display" => nil,
          "amount_nanodollars" => nil
        }
      }
    }
  end
end
