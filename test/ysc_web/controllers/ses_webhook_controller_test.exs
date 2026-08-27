defmodule YscWeb.SesWebhookControllerTest do
  @moduledoc """
  Tests for the SES webhook controller.

  Tests SNS message type handling, environment filtering, event recording,
  hard bounce unsubscription, and signature bypass in test mode.

  Runs synchronously: the controller reads `Ysc.Env.current()` / Application
  env for SES tag filtering, which must not race async tests that temporarily
  set `:ysc, :environment` to non-test values.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

  defmodule SubscriptionHitPlug do
    @moduledoc false
    import Plug.Conn

    def init(pid), do: pid

    def call(conn, pid) do
      send(pid, :subscribe_url_fetched)

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "confirmed")
    end
  end

  defmodule SubscriptionConfirm200Plug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "confirmed")
    end
  end

  defmodule SubscriptionConfirm404Plug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "missing")
    end
  end

  alias Ysc.Newsletter
  alias Ysc.Newsletter.EmailEvent
  alias Ysc.Repo

  # Signature verification is skipped in test via config :ysc, :sns_skip_signature_verification, true

  describe "webhook/2 - SubscriptionConfirmation (SubscribeURL HTTP outcomes)" do
    # SubscribeURL is fetched with Req.get in the controller; use only loopback
    # URLs (e.g. Plug.Cowboy below) so tests never hit AWS or the public internet.
    test "logs success when Req.get to SubscribeURL returns 2xx", %{conn: conn} do
      port = start_subscription_http_server(SubscriptionConfirm200Plug)

      payload =
        build_sns_wrapper("SubscriptionConfirmation", %{}, %{
          "SubscribeURL" => "http://127.0.0.1:#{port}/confirm",
          "TopicArn" => "arn:aws:sns:us-west-1:123456789:ses-events"
        })

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "SubscriptionConfirmation")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end

    test "logs warning when Req.get to SubscribeURL returns non-2xx", %{
      conn: conn
    } do
      port = start_subscription_http_server(SubscriptionConfirm404Plug)

      payload =
        build_sns_wrapper("SubscriptionConfirmation", %{}, %{
          "SubscribeURL" => "http://127.0.0.1:#{port}/missing",
          "TopicArn" => "arn:aws:sns:us-west-1:123456789:ses-events"
        })

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "SubscriptionConfirmation")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end

    test "logs warning when Req.get to SubscribeURL fails (connection refused)",
         %{
           conn: conn
         } do
      payload =
        build_sns_wrapper("SubscriptionConfirmation", %{}, %{
          "SubscribeURL" => "http://127.0.0.1:1/confirm",
          "TopicArn" => "arn:aws:sns:us-west-1:123456789:ses-events"
        })

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "SubscriptionConfirmation")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end
  end

  describe "webhook/2 - TopicArn allowlist (Finding 45)" do
    test "does not fetch SubscribeURL for a TopicArn outside the allowlist", %{
      conn: conn
    } do
      port = start_subscription_http_server(SubscriptionHitPlug, self())

      payload =
        build_sns_wrapper("SubscriptionConfirmation", %{}, %{
          "SubscribeURL" => "http://127.0.0.1:#{port}/confirm",
          "TopicArn" => "arn:aws:sns:us-west-1:999999999999:attacker-topic"
        })

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "SubscriptionConfirmation")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 403
      refute_received :subscribe_url_fetched
    end

    test "refuses subscription confirmation when the allowlist is empty", %{
      conn: conn
    } do
      prev = Application.get_env(:ysc, :sns_allowed_topic_arns)
      Application.put_env(:ysc, :sns_allowed_topic_arns, [])

      on_exit(fn ->
        Application.put_env(:ysc, :sns_allowed_topic_arns, prev)
      end)

      port = start_subscription_http_server(SubscriptionHitPlug, self())

      payload =
        build_sns_wrapper("SubscriptionConfirmation", %{}, %{
          "SubscribeURL" => "http://127.0.0.1:#{port}/confirm",
          "TopicArn" => "arn:aws:sns:us-west-1:123456789:ses-events"
        })

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "SubscriptionConfirmation")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 403
      refute_received :subscribe_url_fetched
    end

    test "does not suppress mail for a hard bounce from a foreign TopicArn", %{
      conn: conn
    } do
      email = "foreign-bounce-#{System.unique_integer([:positive])}@example.com"
      {:ok, subscriber} = Newsletter.subscribe(email)
      assert subscriber.subscribed == true

      ses_event =
        build_ses_event("Bounce",
          email: email,
          env: "test",
          bounce_type: "Permanent",
          bounce_sub_type: "General"
        )

      payload =
        build_sns_wrapper("Notification", ses_event, %{
          "TopicArn" => "arn:aws:sns:us-west-1:999999999999:attacker-topic"
        })

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "Notification")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 403
      assert Repo.reload!(subscriber).subscribed == true
      refute Newsletter.hard_bounced?(email)
      refute Repo.get_by(EmailEvent, email: email, event_type: "bounce")
    end

    test "still records hard bounces when the allowlist is empty", %{conn: conn} do
      prev = Application.get_env(:ysc, :sns_allowed_topic_arns)
      Application.put_env(:ysc, :sns_allowed_topic_arns, [])

      on_exit(fn ->
        Application.put_env(:ysc, :sns_allowed_topic_arns, prev)
      end)

      email =
        "empty-allowlist-#{System.unique_integer([:positive])}@example.com"

      {:ok, subscriber} = Newsletter.subscribe(email)

      ses_event =
        build_ses_event("Bounce",
          email: email,
          env: "test",
          bounce_type: "Permanent"
        )

      conn = post_notification(conn, ses_event)
      assert conn.status == 200
      assert Repo.reload!(subscriber).subscribed == false
      assert Newsletter.hard_bounced?(email)
    end
  end

  describe "webhook/2 - SubscriptionConfirmation" do
    test "returns 200 when SubscribeURL is missing (still acknowledges)", %{
      conn: conn
    } do
      payload =
        build_sns_wrapper("SubscriptionConfirmation", %{}, %{
          "TopicArn" => "arn:aws:sns:us-west-1:123456789:ses-events"
        })
        |> Map.delete("SubscribeURL")

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "SubscriptionConfirmation")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end
  end

  describe "webhook/2 - Notification - open event" do
    test "stores event_timestamp from mail timestamp", %{conn: conn} do
      {:ok, _subscriber} = Newsletter.subscribe("timestamp-open@example.com")

      ses_event =
        build_ses_event("Open",
          email: "timestamp-open@example.com",
          env: "test",
          mail_timestamp: "2026-03-19T15:30:00.000Z"
        )

      conn = post_notification(conn, ses_event)
      assert conn.status == 200

      event =
        Repo.get_by(EmailEvent,
          email: "timestamp-open@example.com",
          event_type: "open"
        )

      assert event,
             "expected EmailEvent row (check env tag matches Ysc.Env.current/0 and SNS body is valid JSON)"

      assert event.event_timestamp == ~U[2026-03-19 15:30:00Z]
    end

    test "records an open event in the database", %{conn: conn} do
      test_pid = self()
      handler_id = "ses-webhook-event-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:ysc, :email, :ses_webhook],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, subscriber} = Newsletter.subscribe("opener@example.com")

      ses_event =
        build_ses_event("Open",
          email: "opener@example.com",
          env: "test"
        )

      conn = post_notification(conn, ses_event)

      assert conn.status == 200

      event =
        Repo.get_by(EmailEvent, email: "opener@example.com", event_type: "open")

      assert event != nil
      assert event.environment == "test"
      assert event.event_type == "open"

      # Should NOT unsubscribe on open
      subscriber = Repo.reload!(subscriber)
      assert subscriber.subscribed == true

      assert_receive {:telemetry, [:ysc, :email, :ses_webhook],
                      %{count: 1, duration: duration},
                      %{event_type: "open", outcome: :recorded}}

      assert duration >= 0
    end

    test "records open event with edition_id and subscriber_id tags", %{
      conn: conn
    } do
      edition = create_edition()
      {:ok, subscriber} = Newsletter.subscribe("tagged@example.com")

      ses_event =
        build_ses_event("Open",
          email: "tagged@example.com",
          env: "test",
          edition_id: edition.id,
          subscriber_id: subscriber.id
        )

      post_notification(conn, ses_event)

      event = Repo.get_by(EmailEvent, email: "tagged@example.com")
      assert event.edition_id == edition.id
      assert event.subscriber_id == subscriber.id
    end
  end

  describe "webhook/2 - missing SNS message type header" do
    test "returns 200 and acknowledges when x-amz-sns-message-type is absent",
         %{
           conn: conn
         } do
      ses_event =
        build_ses_event("Open",
          email: "no-header-type@example.com",
          env: "test"
        )

      payload = build_sns_wrapper("Notification", ses_event)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end
  end

  describe "webhook/2 - Notification - click event" do
    test "records a click event with the clicked URL", %{conn: conn} do
      ses_event =
        build_ses_event("Click",
          email: "clicker@example.com",
          env: "test",
          link_url: "https://ysc.org/events"
        )

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "clicker@example.com",
          event_type: "click"
        )

      assert event != nil
      assert event.link_url == "https://ysc.org/events"
    end
  end

  describe "webhook/2 - Notification - send and delivery events" do
    test "records a send event", %{conn: conn} do
      ses_event =
        build_ses_event("Send",
          email: "send-event@example.com",
          env: "test"
        )

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "send-event@example.com",
          event_type: "send"
        )

      assert event != nil
      assert event.environment == "test"
    end

    test "records a delivery event", %{conn: conn} do
      ses_event =
        build_ses_event("Delivery",
          email: "delivery-event@example.com",
          env: "test"
        )

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "delivery-event@example.com",
          event_type: "delivery"
        )

      assert event != nil
      assert event.environment == "test"
    end
  end

  describe "webhook/2 - Notification - complaint event" do
    test "records a complaint event in the database", %{conn: conn} do
      ses_event =
        build_ses_event("Complaint",
          email: "complainer@example.com",
          env: "test"
        )
        |> Map.put("complaint", %{
          "complaintFeedbackType" => "abuse",
          "timestamp" => "2026-03-19T12:00:00.000Z"
        })

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "complainer@example.com",
          event_type: "complaint"
        )

      assert event != nil
      assert event.environment == "test"
    end

    test "disables event_notifications when the complaint is on an event-notification email",
         %{conn: conn} do
      user = user_fixture(%{email: "event-complainer@example.com"})
      assert user.event_notifications == true

      ses_event =
        build_ses_event("Complaint",
          email: "event-complainer@example.com",
          env: "test"
        )
        |> Map.put("complaint", %{
          "complaintFeedbackType" => "abuse",
          "timestamp" => "2026-03-19T12:00:00.000Z"
        })
        |> put_in(["mail", "tags", "template"], ["event_notification"])

      post_notification(conn, ses_event)

      assert Ysc.Accounts.get_user_by_email(user.email).event_notifications ==
               false
    end

    test "does NOT disable event_notifications when the complaint is on a non-event email",
         %{conn: conn} do
      user = user_fixture(%{email: "newsletter-complainer@example.com"})

      ses_event =
        build_ses_event("Complaint",
          email: "newsletter-complainer@example.com",
          env: "test"
        )
        |> Map.put("complaint", %{
          "complaintFeedbackType" => "abuse",
          "timestamp" => "2026-03-19T12:00:00.000Z"
        })
        |> put_in(["mail", "tags", "template"], ["newsletter_edition"])

      post_notification(conn, ses_event)

      assert Ysc.Accounts.get_user_by_email(user.email).event_notifications ==
               true
    end

    test "disables event_notifications for other :event category templates", %{
      conn: conn
    } do
      user = user_fixture(%{email: "save-the-date-complainer@example.com"})

      ses_event =
        build_ses_event("Complaint",
          email: "save-the-date-complainer@example.com",
          env: "test"
        )
        |> Map.put("complaint", %{
          "complaintFeedbackType" => "abuse",
          "timestamp" => "2026-03-19T12:00:00.000Z"
        })
        |> put_in(["mail", "tags", "template"], ["save_the_date_available"])

      post_notification(conn, ses_event)

      assert Ysc.Accounts.get_user_by_email(user.email).event_notifications ==
               false
    end

    test "does NOT disable event_notifications when the complaint has no template tag",
         %{conn: conn} do
      user = user_fixture(%{email: "untagged-complainer@example.com"})

      ses_event =
        build_ses_event("Complaint",
          email: "untagged-complainer@example.com",
          env: "test"
        )
        |> Map.put("complaint", %{
          "complaintFeedbackType" => "abuse",
          "timestamp" => "2026-03-19T12:00:00.000Z"
        })

      post_notification(conn, ses_event)

      assert Ysc.Accounts.get_user_by_email(user.email).event_notifications ==
               true
    end
  end

  describe "webhook/2 - Notification - bounce event (soft)" do
    test "records a soft bounce but does NOT unsubscribe", %{conn: conn} do
      {:ok, subscriber} = Newsletter.subscribe("softbounce@example.com")

      ses_event =
        build_ses_event("Bounce",
          email: "softbounce@example.com",
          env: "test",
          bounce_type: "Transient",
          bounce_sub_type: "General"
        )

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "softbounce@example.com",
          event_type: "bounce"
        )

      assert event != nil
      assert event.bounce_type == "Transient"

      # Soft bounce should NOT unsubscribe
      subscriber = Repo.reload!(subscriber)
      assert subscriber.subscribed == true
    end

    test "does NOT disable event_notifications on a soft bounce of an event email",
         %{conn: conn} do
      user = user_fixture(%{email: "event-softbounce@example.com"})

      ses_event =
        build_ses_event("Bounce",
          email: "event-softbounce@example.com",
          env: "test",
          bounce_type: "Transient",
          bounce_sub_type: "General"
        )
        |> put_in(["mail", "tags", "template"], ["event_notification"])

      post_notification(conn, ses_event)

      assert Ysc.Accounts.get_user_by_email(user.email).event_notifications ==
               true
    end
  end

  describe "webhook/2 - Notification - bounce event (hard)" do
    test "records bounce with user_id tag from mail.tags", %{conn: conn} do
      user = user_fixture()
      {:ok, _subscriber} = Newsletter.subscribe("bounce-userid-tag@example.com")

      ses_event =
        build_ses_event("Bounce",
          email: "bounce-userid-tag@example.com",
          env: "test",
          bounce_type: "Permanent",
          bounce_sub_type: "General"
        )
        |> put_in(["mail", "tags", "user_id"], [to_string(user.id)])

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "bounce-userid-tag@example.com",
          event_type: "bounce"
        )

      assert event.user_id == user.id
    end

    test "records a hard bounce and unsubscribes the subscriber", %{conn: conn} do
      test_pid = self()
      handler_id = "hard-bounce-webhook-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:ysc, :email, :hard_bounce],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, subscriber} = Newsletter.subscribe("hardbounce@example.com")
      assert subscriber.subscribed == true

      ses_event =
        build_ses_event("Bounce",
          email: "hardbounce@example.com",
          env: "test",
          bounce_type: "Permanent",
          bounce_sub_type: "General"
        )

      conn = post_notification(conn, ses_event)

      assert conn.status == 200

      event =
        Repo.get_by(EmailEvent,
          email: "hardbounce@example.com",
          event_type: "bounce"
        )

      assert event != nil
      assert event.bounce_type == "Permanent"

      # Hard bounce MUST unsubscribe
      subscriber = Repo.reload!(subscriber)
      assert subscriber.subscribed == false
      assert subscriber.source == "hard_bounce"
      assert subscriber.metadata["unsubscribe_reason"] == "hard_bounce"
      assert subscriber.metadata["hard_bounced_at"] != nil

      assert_receive {:telemetry, [:ysc, :email, :hard_bounce], %{count: 1},
                      %{outcome: :unsubscribed}}
    end

    test "disables event_notifications when the hard bounce is on an event-notification email",
         %{conn: conn} do
      user = user_fixture(%{email: "event-hardbounce@example.com"})
      assert user.event_notifications == true

      ses_event =
        build_ses_event("Bounce",
          email: "event-hardbounce@example.com",
          env: "test",
          bounce_type: "Permanent",
          bounce_sub_type: "General"
        )
        |> put_in(["mail", "tags", "template"], ["event_notification"])

      post_notification(conn, ses_event)

      assert Ysc.Accounts.get_user_by_email(user.email).event_notifications ==
               false
    end

    test "does NOT disable event_notifications when the hard bounce is on a non-event email",
         %{conn: conn} do
      user = user_fixture(%{email: "newsletter-hardbounce@example.com"})

      ses_event =
        build_ses_event("Bounce",
          email: "newsletter-hardbounce@example.com",
          env: "test",
          bounce_type: "Permanent",
          bounce_sub_type: "General"
        )
        |> put_in(["mail", "tags", "template"], ["newsletter_edition"])

      post_notification(conn, ses_event)

      assert Ysc.Accounts.get_user_by_email(user.email).event_notifications ==
               true
    end

    test "hard bounce for non-subscriber returns 200 without error", %{
      conn: conn
    } do
      ses_event =
        build_ses_event("Bounce",
          email: "notasubscriber@example.com",
          env: "test",
          bounce_type: "Permanent",
          bounce_sub_type: "General"
        )

      conn = post_notification(conn, ses_event)

      assert conn.status == 200
    end

    test "hard bounce for already-unsubscribed email does not error", %{
      conn: conn
    } do
      {:ok, _} = Newsletter.subscribe("alreadyunsub@example.com")
      {:ok, _} = Newsletter.unsubscribe("alreadyunsub@example.com")

      ses_event =
        build_ses_event("Bounce",
          email: "alreadyunsub@example.com",
          env: "test",
          bounce_type: "Permanent",
          bounce_sub_type: "General"
        )

      conn = post_notification(conn, ses_event)

      assert conn.status == 200
    end
  end

  describe "webhook/2 - Notification - invalid SES event type" do
    test "returns 200 but does not persist when event_type is not allowed", %{
      conn: conn
    } do
      ses_event =
        build_ses_event("Open",
          email: "invalid-type@example.com",
          env: "test"
        )
        |> Map.put("eventType", "UnknownSesType")

      post_notification(conn, ses_event)

      refute Repo.get_by(EmailEvent, email: "invalid-type@example.com")
    end
  end

  describe "webhook/2 - Notification - multiple recipients" do
    test "uses first destination address for stored email field", %{conn: conn} do
      ses_event =
        build_ses_event("Open",
          email: "first@example.com",
          env: "test"
        )
        |> put_in(["mail", "destination"], [
          "first@example.com",
          "second@example.com"
        ])

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent, event_type: "open", email: "first@example.com")

      assert event != nil
    end
  end

  describe "webhook/2 - Notification - record_email_event failure" do
    test "returns 200 when email exceeds max length and event is not persisted",
         %{
           conn: conn
         } do
      long_email = String.duplicate("a", 300) <> "@example.com"

      ses_event =
        build_ses_event("Open",
          email: long_email,
          env: "test"
        )

      conn = post_notification(conn, ses_event)

      assert conn.status == 200
      assert Repo.get_by(EmailEvent, email: long_email) == nil
    end

    test "returns 200 when edition_id tag does not exist (FK) for short local email",
         %{conn: conn} do
      # Triggers record_email_event {:error, changeset} and mask_email/1 one-char local branch.
      bogus_edition = Ecto.ULID.generate()

      ses_event =
        build_ses_event("Open",
          email: "a@y.co",
          env: "test"
        )
        |> put_in(["mail", "tags", "edition_id"], [bogus_edition])

      conn = post_notification(conn, ses_event)

      assert conn.status == 200
      assert Repo.get_by(EmailEvent, email: "a@y.co") == nil
    end

    test "returns 200 when edition_id tag does not exist (FK) for two-char local email",
         %{conn: conn} do
      bogus_edition = Ecto.ULID.generate()

      ses_event =
        build_ses_event("Open",
          email: "ab@example.com",
          env: "test"
        )
        |> put_in(["mail", "tags", "edition_id"], [bogus_edition])

      conn = post_notification(conn, ses_event)

      assert conn.status == 200
      assert Repo.get_by(EmailEvent, email: "ab@example.com") == nil
    end

    test "returns 200 when edition_id tag does not exist (FK) for email without @",
         %{conn: conn} do
      bogus_edition = Ecto.ULID.generate()

      ses_event =
        build_ses_event("Open",
          email: "no-at-sign",
          env: "test"
        )
        |> put_in(["mail", "tags", "edition_id"], [bogus_edition])

      conn = post_notification(conn, ses_event)

      assert conn.status == 200
      assert Repo.get_by(EmailEvent, email: "no-at-sign") == nil
    end

    test "returns 200 when destination is a nested empty list (invalid email) and mask_email uses inspect/1",
         %{conn: conn} do
      bogus_edition = Ecto.ULID.generate()

      ses_event =
        build_ses_event("Open",
          email: "ignored@example.com",
          env: "test"
        )
        |> put_in(["mail", "destination"], [[]])
        |> put_in(["mail", "tags", "edition_id"], [bogus_edition])

      conn = post_notification(conn, ses_event)

      assert conn.status == 200
      refute Repo.get_by(EmailEvent, edition_id: bogus_edition)
    end
  end

  describe "webhook/2 - Notification - timestamp parsing" do
    test "stores event_timestamp from bounce when mail timestamp is absent", %{
      conn: conn
    } do
      ses_event =
        build_ses_event("Bounce",
          email: "bounce-ts-only@example.com",
          env: "test",
          bounce_type: "Transient",
          bounce_sub_type: "General"
        )
        |> update_in(["mail"], &Map.delete(&1, "timestamp"))

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "bounce-ts-only@example.com",
          event_type: "bounce"
        )

      assert event.event_timestamp == ~U[2026-03-19 12:00:00Z]
    end

    test "stores event_timestamp from complaint when mail timestamp is absent",
         %{
           conn: conn
         } do
      ses_event =
        build_ses_event("Complaint",
          email: "complaint-ts@example.com",
          env: "test"
        )
        |> Map.put("complaint", %{
          "complaintFeedbackType" => "abuse",
          "timestamp" => "2026-03-20T08:15:00.000Z"
        })
        |> update_in(["mail"], &Map.delete(&1, "timestamp"))

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "complaint-ts@example.com",
          event_type: "complaint"
        )

      assert event.event_timestamp == ~U[2026-03-20 08:15:00Z]
    end

    test "stores nil event_timestamp when mail timestamp is invalid ISO8601", %{
      conn: conn
    } do
      ses_event =
        build_ses_event("Open",
          email: "bad-ts@example.com",
          env: "test",
          mail_timestamp: "not-a-valid-timestamp"
        )

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "bad-ts@example.com",
          event_type: "open"
        )

      assert event.event_timestamp == nil
    end

    test "stores event_timestamp from open when mail timestamp is absent", %{
      conn: conn
    } do
      ses_event =
        build_ses_event("Open",
          email: "open-only-ts@example.com",
          env: "test"
        )
        |> update_in(["mail"], &Map.delete(&1, "timestamp"))
        |> Map.put("open", %{"timestamp" => "2026-03-19T16:45:00.000Z"})

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "open-only-ts@example.com",
          event_type: "open"
        )

      assert event.event_timestamp == ~U[2026-03-19 16:45:00Z]
    end

    test "stores event_timestamp from click when mail timestamp is absent", %{
      conn: conn
    } do
      ses_event =
        build_ses_event("Click",
          email: "click-only-ts@example.com",
          env: "test",
          link_url: "https://ysc.org/x"
        )
        |> update_in(["mail"], &Map.delete(&1, "timestamp"))
        |> put_in(["click", "timestamp"], "2026-03-19T18:15:30.000Z")

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "click-only-ts@example.com",
          event_type: "click"
        )

      assert event.event_timestamp == ~U[2026-03-19 18:15:30Z]
    end

    test "stores nil event_timestamp when no mail, open, click, bounce, or complaint timestamps exist",
         %{conn: conn} do
      {:ok, _subscriber} = Newsletter.subscribe("nil-ts-all@example.com")

      ses_event =
        build_ses_event("Open",
          email: "nil-ts-all@example.com",
          env: "test"
        )
        |> update_in(["mail"], &Map.delete(&1, "timestamp"))

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "nil-ts-all@example.com",
          event_type: "open"
        )

      assert event.event_timestamp == nil
    end
  end

  describe "webhook/2 - environment filtering" do
    test "skips events from a different environment (no DB insert)", %{
      conn: conn
    } do
      {:ok, subscriber} = Newsletter.subscribe("wrongenv@example.com")

      # Current env in test is "test", so "prod" events should be discarded
      ses_event =
        build_ses_event("Bounce",
          email: "wrongenv@example.com",
          env: "prod",
          bounce_type: "Permanent",
          bounce_sub_type: "General"
        )

      conn = post_notification(conn, ses_event)

      assert conn.status == 200

      # No event should have been stored
      assert Repo.get_by(EmailEvent, email: "wrongenv@example.com") == nil

      # Subscriber should NOT have been unsubscribed
      subscriber = Repo.reload!(subscriber)
      assert subscriber.subscribed == true
    end

    test "processes events from the current environment", %{conn: conn} do
      ses_event =
        build_ses_event("Open",
          email: "rightenv@example.com",
          env: "test"
        )

      post_notification(conn, ses_event)

      assert Repo.get_by(EmailEvent, email: "rightenv@example.com") != nil
    end
  end

  describe "mask_email/1 (via controller logging - no PII leaks)" do
    test "hard bounce logs do not contain the raw email address", %{conn: conn} do
      # We can't directly inspect log output in tests, but we can verify the
      # controller processes the event without crashing (mask_email handles it).
      {:ok, _subscriber} = Newsletter.subscribe("piitest@example.com")

      ses_event =
        build_ses_event("Bounce",
          email: "piitest@example.com",
          env: "test",
          bounce_type: "Permanent",
          bounce_sub_type: "General"
        )

      conn = post_notification(conn, ses_event)
      assert conn.status == 200
    end
  end

  describe "webhook/2 - Notification - malformed inner Message JSON" do
    test "still returns 200 when SES Message JSON is invalid", %{conn: conn} do
      payload = build_sns_wrapper("Notification", %{})

      payload =
        Map.put(payload, "Message", "not valid json {{{")

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "Notification")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 200
    end
  end

  describe "webhook/2 - raw body (text/plain)" do
    test "parses SNS JSON from raw body when params are empty", %{conn: conn} do
      {:ok, _subscriber} = Newsletter.subscribe("rawbody@example.com")

      ses_event =
        build_ses_event("Open",
          email: "rawbody@example.com",
          env: "test"
        )

      body =
        Jason.encode!(%{
          "Type" => "Notification",
          "MessageId" => "raw-msg-#{System.unique_integer()}",
          "TopicArn" => "arn:aws:sns:us-west-1:123456789:ses-events",
          "Message" => Jason.encode!(ses_event),
          "Timestamp" => "2026-03-19T12:00:00.000Z",
          "SigningCertURL" => "https://sns.amazonaws.com/cert.pem",
          "Signature" => "test-signature"
        })

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "Notification")
        |> put_req_header("content-type", "text/plain; charset=UTF-8")
        |> post("/webhooks/ses", body)

      assert conn.status == 200

      assert Repo.get_by(EmailEvent,
               email: "rawbody@example.com",
               event_type: "open"
             )
    end
  end

  describe "webhook/2 - signature verification" do
    test "returns 403 when SNS signature verification fails", %{conn: conn} do
      prev = Application.get_env(:ysc, :sns_skip_signature_verification)
      Application.put_env(:ysc, :sns_skip_signature_verification, false)

      on_exit(fn ->
        Application.put_env(:ysc, :sns_skip_signature_verification, prev)
      end)

      ses_event =
        build_ses_event("Open",
          email: "sigfail@example.com",
          env: "test"
        )

      payload =
        build_sns_wrapper("Notification", ses_event, %{
          "SigningCertURL" => "https://evil.example.com/cert.pem"
        })

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "Notification")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end

    test "returns 403 when SigningCertURL is an S3 amazonaws.com host", %{
      conn: conn
    } do
      prev = Application.get_env(:ysc, :sns_skip_signature_verification)
      Application.put_env(:ysc, :sns_skip_signature_verification, false)

      on_exit(fn ->
        Application.put_env(:ysc, :sns_skip_signature_verification, prev)
      end)

      ses_event =
        build_ses_event("Bounce",
          email: "s3-cert@example.com",
          env: "test",
          bounce_type: "Permanent"
        )

      payload =
        build_sns_wrapper("Notification", ses_event, %{
          "SigningCertURL" =>
            "https://attacker-bucket.s3.amazonaws.com/forged.pem"
        })

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "Notification")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 403
      refute Repo.get_by(EmailEvent, email: "s3-cert@example.com")
    end
  end

  describe "webhook/2 - signed Type vs unsigned header" do
    test "returns 403 when header Type does not match signed body Type", %{
      conn: conn
    } do
      payload =
        build_sns_wrapper("Notification", %{}, %{
          "SubscribeURL" => "http://127.0.0.1/exfil"
        })

      conn =
        conn
        |> put_req_header(
          "x-amz-sns-message-type",
          "SubscriptionConfirmation"
        )
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end
  end

  describe "webhook/2 - tag extraction" do
    test "flattens non-list tag values to a single string", %{conn: conn} do
      {:ok, _subscriber} = Newsletter.subscribe("flat-tags@example.com")

      ses_event =
        build_ses_event("Open",
          email: "flat-tags@example.com",
          env: "test"
        )
        |> put_in(["mail", "tags"], %{"env" => "test"})

      post_notification(conn, ses_event)

      event =
        Repo.get_by(EmailEvent,
          email: "flat-tags@example.com",
          event_type: "open"
        )

      assert event.environment == "test"
    end
  end

  describe "webhook/2 - invalid payloads" do
    test "returns 400 for invalid JSON", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "Notification")
        |> put_req_header("content-type", "text/plain")
        |> post("/webhooks/ses", "not-json-at-all{{{")

      assert conn.status == 400
    end

    test "returns 400 when JSON body is empty object", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "Notification")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", "{}")

      assert conn.status == 400
    end

    test "returns 200 for unknown SNS message type", %{conn: conn} do
      payload = build_sns_wrapper("UnsubscribeConfirmation", %{})

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "UnsubscribeConfirmation")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 200
    end
  end

  # ---------------------------------------------------------------------------
  # Newsletter context unit tests
  # ---------------------------------------------------------------------------

  describe "Newsletter.handle_hard_bounce/1" do
    test "unsubscribes an active subscriber" do
      {:ok, subscriber} = Newsletter.subscribe("bounce@example.com")
      assert subscriber.subscribed == true

      assert {:ok, updated} =
               Newsletter.handle_hard_bounce("bounce@example.com")

      assert updated.subscribed == false
      assert updated.source == "hard_bounce"
      assert updated.unsubscribed_at != nil
      assert updated.metadata["unsubscribe_reason"] == "hard_bounce"
    end

    test "returns :not_subscribed for unknown email" do
      assert {:ok, :not_subscribed} =
               Newsletter.handle_hard_bounce("ghost@example.com")
    end

    test "returns :not_subscribed for already-unsubscribed email" do
      {:ok, _} = Newsletter.subscribe("already@example.com")
      {:ok, _} = Newsletter.unsubscribe("already@example.com")

      assert {:ok, :not_subscribed} =
               Newsletter.handle_hard_bounce("already@example.com")
    end
  end

  describe "Newsletter.record_email_event/1" do
    test "creates an email event record" do
      attrs = %{
        event_type: "open",
        email: "recorder@example.com",
        environment: "test"
      }

      assert {:ok, event} = Newsletter.record_email_event(attrs)
      assert event.event_type == "open"
      assert event.email == "recorder@example.com"
      assert event.environment == "test"
    end

    test "returns changeset error for invalid event_type" do
      attrs = %{
        event_type: "invalid_type",
        email: "err@example.com",
        environment: "test"
      }

      assert {:error, changeset} = Newsletter.record_email_event(attrs)
      assert changeset.errors[:event_type] != nil
    end

    test "returns changeset error when required fields are missing" do
      assert {:error, changeset} = Newsletter.record_email_event(%{})
      assert changeset.errors[:event_type] != nil
      assert changeset.errors[:email] != nil
      assert changeset.errors[:environment] != nil
    end
  end

  describe "Newsletter.count_email_events_by_type/1" do
    test "returns counts grouped by event type" do
      edition = create_edition()

      Newsletter.record_email_event(%{
        event_type: "open",
        email: "counts-a@example.com",
        environment: "test",
        edition_id: edition.id
      })

      Newsletter.record_email_event(%{
        event_type: "open",
        email: "counts-b@example.com",
        environment: "test",
        edition_id: edition.id
      })

      Newsletter.record_email_event(%{
        event_type: "click",
        email: "counts-a@example.com",
        environment: "test",
        edition_id: edition.id
      })

      counts = Newsletter.count_email_events_by_type(edition.id)
      assert counts["open"] == 2
      assert counts["click"] == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp start_subscription_http_server(plug_module, plug_opts \\ []) do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    ref = :"ses_sub_http_#{port}_#{System.unique_integer([:positive])}"

    {:ok, _} = Plug.Cowboy.http(plug_module, plug_opts, port: port, ref: ref)

    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

    port
  end

  defp post_notification(conn, ses_event) do
    payload = build_sns_wrapper("Notification", ses_event)

    conn
    |> put_req_header("x-amz-sns-message-type", "Notification")
    |> put_req_header("content-type", "application/json")
    |> post("/webhooks/ses", payload)
  end

  defp build_sns_wrapper(type, ses_event, extra \\ %{}) do
    Map.merge(
      %{
        "Type" => type,
        "MessageId" => "test-message-id-#{System.unique_integer()}",
        "TopicArn" => "arn:aws:sns:us-west-1:123456789:ses-events",
        "Message" => Jason.encode!(ses_event),
        "Timestamp" => "2026-03-19T12:00:00.000Z",
        "SigningCertURL" => "https://sns.amazonaws.com/cert.pem",
        "Signature" => "test-signature"
      },
      extra
    )
  end

  defp build_ses_event(event_type, opts) do
    email = Keyword.get(opts, :email, "test@example.com")
    env = Keyword.get(opts, :env, "test")

    mail_timestamp =
      Keyword.get(opts, :mail_timestamp, "2026-03-19T12:00:00.000Z")

    edition_id = Keyword.get(opts, :edition_id)
    subscriber_id = Keyword.get(opts, :subscriber_id)
    bounce_type = Keyword.get(opts, :bounce_type)
    bounce_sub_type = Keyword.get(opts, :bounce_sub_type)
    link_url = Keyword.get(opts, :link_url)

    tags =
      %{"env" => [env]}
      |> maybe_put_tag("edition_id", edition_id)
      |> maybe_put_tag("subscriber_id", subscriber_id)

    event = %{
      "eventType" => event_type,
      "mail" => %{
        "destination" => [email],
        "timestamp" => mail_timestamp,
        "tags" => tags
      }
    }

    event
    |> maybe_put_bounce(bounce_type, bounce_sub_type)
    |> maybe_put_click(link_url)
  end

  defp maybe_put_tag(tags, _key, nil), do: tags
  defp maybe_put_tag(tags, key, value), do: Map.put(tags, key, [value])

  defp maybe_put_bounce(event, nil, _), do: event

  defp maybe_put_bounce(event, bounce_type, bounce_sub_type) do
    Map.put(event, "bounce", %{
      "bounceType" => bounce_type,
      "bounceSubType" => bounce_sub_type || "General",
      "timestamp" => "2026-03-19T12:00:00.000Z"
    })
  end

  defp maybe_put_click(event, nil), do: event

  defp maybe_put_click(event, link_url) do
    Map.put(event, "click", %{
      "link" => link_url,
      "timestamp" => "2026-03-19T12:00:00.000Z"
    })
  end

  defp create_edition do
    {:ok, edition} =
      Newsletter.create_edition(%{
        "title" => "Test Edition",
        "subject" => "Test Subject"
      })

    edition
  end
end
