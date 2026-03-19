defmodule YscWeb.SesWebhookControllerTest do
  @moduledoc """
  Tests for the SES webhook controller.

  Tests SNS message type handling, environment filtering, event recording,
  hard bounce unsubscription, and signature bypass in test mode.
  """
  use YscWeb.ConnCase, async: true

  alias Ysc.Newsletter
  alias Ysc.Newsletter.EmailEvent
  alias Ysc.Repo

  # Signature verification is skipped in test via config :ysc, :sns_skip_signature_verification, true

  describe "webhook/2 - SubscriptionConfirmation" do
    test "confirms SNS subscription by fetching SubscribeURL", %{conn: conn} do
      # Req.get is called for the SubscribeURL in production, but in tests we
      # don't have a real URL to confirm. We just verify the endpoint returns 200.
      # The Req.get call will fail gracefully and the controller still returns 200.
      payload =
        build_sns_wrapper("SubscriptionConfirmation", %{}, %{
          "SubscribeURL" => "https://sns.amazonaws.com/confirm?token=test",
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

  describe "webhook/2 - Notification - open event" do
    test "records an open event in the database", %{conn: conn} do
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
  end

  describe "webhook/2 - Notification - bounce event (hard)" do
    test "records a hard bounce and unsubscribes the subscriber", %{conn: conn} do
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

  describe "webhook/2 - invalid payloads" do
    test "returns 400 for invalid JSON", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "Notification")
        |> put_req_header("content-type", "text/plain")
        |> post("/webhooks/ses", "not-json-at-all{{{")

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
      email = "counts@example.com"

      Newsletter.record_email_event(%{
        event_type: "open",
        email: email,
        environment: "test",
        edition_id: edition.id
      })

      Newsletter.record_email_event(%{
        event_type: "open",
        email: email,
        environment: "test",
        edition_id: edition.id
      })

      Newsletter.record_email_event(%{
        event_type: "click",
        email: email,
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
        "timestamp" => "2026-03-19T12:00:00.000Z",
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
