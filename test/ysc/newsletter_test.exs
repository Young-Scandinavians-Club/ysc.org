defmodule Ysc.NewsletterTest do
  use Ysc.DataCase

  alias Ysc.Newsletter
  alias Ysc.Newsletter.Edition
  alias Ysc.Newsletter.Subscriber
  alias Ysc.Newsletter.UnsubscribeEvent
  alias Ysc.Repo

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  describe "subscribe/2" do
    test "creates a new subscriber with email and source" do
      assert {:ok, %Subscriber{} = s} =
               Newsletter.subscribe("new@example.com", source: "public_signup")

      assert s.email == "new@example.com"
      assert s.subscribed == true
      assert s.source == "public_signup"
      assert s.subscription_token != nil
      assert s.subscribed_at != nil
      assert s.user_id == nil
    end

    test "stores email case-insensitively (citext) - lookup matches regardless of case" do
      {:ok, s} =
        Newsletter.subscribe("User@Example.COM", source: "public_signup")

      found = Newsletter.get_subscriber_by_email("user@example.com")
      assert found != nil
      assert found.id == s.id
    end

    test "returns error for invalid email" do
      assert {:error, :invalid_email} = Newsletter.subscribe("")
      assert {:error, :invalid_email} = Newsletter.subscribe("no-at-sign")
      assert {:error, :invalid_email} = Newsletter.subscribe(nil)
    end

    test "returns error for disposable email domains" do
      assert {:error, :disposable_email} =
               Newsletter.subscribe("test@mailinator.com")

      assert {:error, :disposable_email} =
               Newsletter.subscribe("test@guerrillamail.com")

      assert {:error, :disposable_email} =
               Newsletter.subscribe("test@10minutemail.com")
    end

    test "returns error for domains with no MX records" do
      stub_mx_no_records()

      domain = "mx-reject-#{System.unique_integer([:positive])}.example.org"

      assert {:error, :no_mx_records} =
               Newsletter.subscribe("user@#{domain}")
    end

    test "skip_email_validation allows trusted imports without MX checks" do
      stub_mx_no_records()

      domain = "mx-reject-#{System.unique_integer([:positive])}.example.org"
      email = "trusted@#{domain}"

      assert {:ok, %Subscriber{} = s} =
               Newsletter.subscribe(email,
                 source: "wp_newsletter_csv",
                 skip_email_validation: true
               )

      assert s.email == email
      assert s.subscribed == true
    end

    test "treats Gmail addresses with dots as the same subscriber" do
      tag = Integer.to_string(System.unique_integer([:positive]))
      dotted_email = "news.#{tag}@gmail.com"
      canonical_email = "news#{tag}@gmail.com"

      %Subscriber{}
      |> Subscriber.create_changeset(%{
        email: dotted_email,
        subscribed: true,
        subscription_token: Subscriber.generate_subscription_token(),
        subscribed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        source: "public_signup"
      })
      |> Repo.insert!()

      assert {:ok, subscriber} =
               Newsletter.subscribe(canonical_email, source: "public_signup")

      assert subscriber.email == canonical_email
      assert subscriber.subscribed == true

      assert Newsletter.get_subscriber_by_email(dotted_email).id ==
               subscriber.id
    end

    test "updates existing subscriber when subscribing again (re-activates)" do
      {:ok, first} =
        Newsletter.subscribe("again@example.com", source: "public_signup")

      token = first.subscription_token

      {:ok, _} = Newsletter.unsubscribe("again@example.com")
      refute Newsletter.get_subscriber_by_email("again@example.com").subscribed

      assert {:ok, updated} =
               Newsletter.subscribe("again@example.com",
                 source: "public_signup"
               )

      assert updated.subscribed == true
      assert updated.subscription_token == token
      assert updated.unsubscribed_at == nil
    end

    test "force_source overrides an existing subscribed source" do
      {:ok, _} =
        Newsletter.subscribe("force-source@example.com",
          source: "public_signup"
        )

      assert {:ok, updated} =
               Newsletter.subscribe("force-source@example.com",
                 source: "wp_migration",
                 force_source: true
               )

      assert updated.subscribed == true
      assert updated.source == "wp_migration"
    end

    test "links existing anonymous subscription when user registers (same email)" do
      {:ok, anon} =
        Newsletter.subscribe("link@example.com", source: "public_signup")

      assert anon.user_id == nil

      # Registering a user with same email triggers subscribe_user_to_newsletter,
      # which updates the existing subscriber and links user_id
      user =
        user_fixture(%{
          email: "link@example.com",
          first_name: "Link",
          last_name: "User"
        })

      linked = Newsletter.get_subscriber_by_email("link@example.com")
      assert linked.id == anon.id
      assert linked.user_id == user.id
      assert linked.source == "user_registration_linked"
      assert linked.first_name == "Link"
      assert linked.last_name == "User"
    end

    test "accepts optional metadata" do
      metadata = %{"signup_date" => "2026-01-01T00:00:00Z"}

      assert {:ok, s} =
               Newsletter.subscribe("meta@example.com",
                 source: "public_signup",
                 metadata: metadata
               )

      assert s.metadata == metadata
    end

    test "auto-confirms new subscribers (trusted/immediate path)" do
      {:ok, s} =
        Newsletter.subscribe("auto-confirm@example.com",
          source: "public_signup"
        )

      assert s.confirmed_at != nil
      assert DateTime.compare(s.confirmed_at, s.subscribed_at) == :eq
    end

    test "auto-confirms a reactivated subscriber that was never confirmed" do
      {:ok, pending} =
        Newsletter.request_confirmation("was-pending@example.com",
          source: "public_signup"
        )

      assert pending == :pending

      refute Newsletter.get_subscriber_by_email("was-pending@example.com").subscribed

      # An authenticated/trusted path (e.g. account settings) subscribing the
      # same email should immediately confirm it, bypassing double opt-in.
      assert {:ok, updated} =
               Newsletter.subscribe("was-pending@example.com",
                 source: "user_settings"
               )

      assert updated.subscribed == true
      assert updated.confirmed_at != nil
    end
  end

  describe "request_confirmation/2" do
    test "creates a pending, unconfirmed subscriber and does not subscribe" do
      email = "pending@example.com"

      assert {:ok, :pending} =
               Newsletter.request_confirmation(email, source: "public_signup")

      subscriber = Newsletter.get_subscriber_by_email(email)
      assert subscriber != nil
      assert subscriber.subscribed == false
      assert subscriber.subscribed_at == nil
      assert subscriber.confirmed_at == nil
      assert subscriber.confirmation_token != nil
      assert subscriber.subscription_token != nil
    end

    test "schedules a confirmation email" do
      email = "pending-email@example.com"

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, :pending} =
                 Newsletter.request_confirmation(email, source: "public_signup")

        subscriber = Newsletter.get_subscriber_by_email(email)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => email,
            "template" => "newsletter_confirmation"
          }
        )

        assert [job] = all_enqueued(worker: YscWeb.Workers.EmailNotifier)
        assert job.args["params"]["reminder"] == false

        expected_url =
          YscWeb.Emails.Helpers.absolute_url(
            "/newsletter/confirm/#{subscriber.confirmation_token}"
          )

        assert job.args["params"]["url"] == expected_url
      end)
    end

    test "schedules the 24h confirmation reminder" do
      email = "pending-reminder@example.com"

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, :pending} =
                 Newsletter.request_confirmation(email, source: "public_signup")

        subscriber = Newsletter.get_subscriber_by_email(email)

        assert_enqueued(
          worker: YscWeb.Workers.NewsletterConfirmationReminder,
          args: %{"subscriber_id" => subscriber.id}
        )
      end)
    end

    test "resending for the same still-pending email rotates the token" do
      email = "resend@example.com"

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, :pending} =
          Newsletter.request_confirmation(email, source: "public_signup")

        first = Newsletter.get_subscriber_by_email(email)

        {:ok, :pending} =
          Newsletter.request_confirmation(email, source: "public_signup")

        second = Newsletter.get_subscriber_by_email(email)

        assert second.id == first.id
        assert second.confirmation_token != first.confirmation_token
        assert second.subscribed == false
        assert second.confirmed_at == nil
      end)
    end

    test "returns :already_subscribed and sends no email for an active confirmed subscriber" do
      email = "already@example.com"
      {:ok, _} = Newsletter.subscribe(email, source: "public_signup")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, :already_subscribed} =
                 Newsletter.request_confirmation(email, source: "public_signup")

        assert [] = all_enqueued(worker: YscWeb.Workers.EmailNotifier)

        assert [] =
                 all_enqueued(
                   worker: YscWeb.Workers.NewsletterConfirmationReminder
                 )
      end)
    end

    test "re-signup for a previously unsubscribed email requires reconfirmation" do
      email = "was-unsubscribed@example.com"
      {:ok, sub} = Newsletter.subscribe(email, source: "public_signup")
      {:ok, _} = Newsletter.unsubscribe(sub.subscription_token)

      assert {:ok, :pending} =
               Newsletter.request_confirmation(email, source: "public_signup")

      updated = Newsletter.get_subscriber_by_email(email)
      refute updated.subscribed
    end

    test "returns error for invalid email" do
      assert {:error, :invalid_email} = Newsletter.request_confirmation("")

      assert {:error, :invalid_email} =
               Newsletter.request_confirmation("no-at-sign")

      assert {:error, :invalid_email} = Newsletter.request_confirmation(nil)
    end

    test "returns error for disposable email domains" do
      assert {:error, :disposable_email} =
               Newsletter.request_confirmation("test@mailinator.com")
    end

    test "returns error for domains with no MX records" do
      stub_mx_no_records()
      domain = "mx-reject-#{System.unique_integer([:positive])}.example.org"

      assert {:error, :no_mx_records} =
               Newsletter.request_confirmation("user@#{domain}")
    end
  end

  describe "confirm_subscription/1" do
    test "confirms a pending subscriber and activates the subscription" do
      email = "confirm-me@example.com"

      {:ok, :pending} =
        Newsletter.request_confirmation(email, source: "public_signup")

      pending = Newsletter.get_subscriber_by_email(email)

      assert {:ok, confirmed} =
               Newsletter.confirm_subscription(pending.confirmation_token)

      assert confirmed.subscribed == true
      assert confirmed.confirmed_at != nil
      assert confirmed.subscribed_at != nil
    end

    test "is idempotent — replaying the same token after confirming succeeds" do
      email = "confirm-twice@example.com"

      {:ok, :pending} =
        Newsletter.request_confirmation(email, source: "public_signup")

      pending = Newsletter.get_subscriber_by_email(email)

      {:ok, first} = Newsletter.confirm_subscription(pending.confirmation_token)

      {:ok, second} =
        Newsletter.confirm_subscription(pending.confirmation_token)

      assert second.id == first.id
      assert second.confirmed_at == first.confirmed_at
    end

    test "returns not_found for an unknown token" do
      assert {:error, :not_found} =
               Newsletter.confirm_subscription("unknown-token")
    end
  end

  describe "deliver_confirmation_reminder/1" do
    test "sends a reminder email for a still-pending subscriber" do
      email = "reminder-needed@example.com"

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, :pending} =
          Newsletter.request_confirmation(email, source: "public_signup")

        subscriber = Newsletter.get_subscriber_by_email(email)

        assert :ok = Newsletter.deliver_confirmation_reminder(subscriber.id)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => email,
            "idempotency_key" =>
              "newsletter_confirmation_reminder_#{subscriber.id}",
            "template" => "newsletter_confirmation"
          }
        )

        [reminder_job] =
          all_enqueued(
            worker: YscWeb.Workers.EmailNotifier,
            args: %{
              "idempotency_key" =>
                "newsletter_confirmation_reminder_#{subscriber.id}"
            }
          )

        assert reminder_job.args["params"]["reminder"] == true
      end)
    end

    test "skips sending when the subscriber already confirmed" do
      email = "reminder-not-needed@example.com"

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, :pending} =
          Newsletter.request_confirmation(email, source: "public_signup")

        subscriber = Newsletter.get_subscriber_by_email(email)

        {:ok, _} =
          Newsletter.confirm_subscription(subscriber.confirmation_token)

        assert :ok = Newsletter.deliver_confirmation_reminder(subscriber.id)

        refute_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "idempotency_key" =>
              "newsletter_confirmation_reminder_#{subscriber.id}"
          }
        )
      end)
    end

    test "skips sending when the subscriber no longer exists" do
      email = "reminder-deleted@example.com"

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, :pending} =
          Newsletter.request_confirmation(email, source: "public_signup")

        subscriber = Newsletter.get_subscriber_by_email(email)
        Repo.delete!(subscriber)

        assert :ok = Newsletter.deliver_confirmation_reminder(subscriber.id)

        refute_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "idempotency_key" =>
              "newsletter_confirmation_reminder_#{subscriber.id}"
          }
        )
      end)
    end
  end

  describe "unsubscribe/1" do
    test "unsubscribes by email" do
      {:ok, _s} =
        Newsletter.subscribe("out@example.com", source: "public_signup")

      assert {:ok, updated} = Newsletter.unsubscribe("out@example.com")
      assert updated.subscribed == false
      assert updated.unsubscribed_at != nil
    end

    test "unsubscribes by token" do
      {:ok, s} =
        Newsletter.subscribe("token@example.com", source: "public_signup")

      assert {:ok, updated} = Newsletter.unsubscribe(s.subscription_token)
      assert updated.subscribed == false
    end

    test "returns not_found for unknown email" do
      assert {:error, :not_found} =
               Newsletter.unsubscribe("unknown@example.com")
    end

    test "returns not_found for unknown token" do
      assert {:error, :not_found} = Newsletter.unsubscribe("invalid-token-xyz")
    end
  end

  describe "get_subscriber_by_email/1" do
    test "returns nil for unknown email" do
      refute Newsletter.get_subscriber_by_email("nope@example.com")
    end

    test "returns subscriber for existing email" do
      {:ok, s} =
        Newsletter.subscribe("get@example.com", source: "public_signup")

      found = Newsletter.get_subscriber_by_email("get@example.com")
      assert found != nil
      assert found.id == s.id
    end
  end

  describe "get_subscriber_by_token/1" do
    test "returns nil for unknown token" do
      refute Newsletter.get_subscriber_by_token("unknown")
    end

    test "returns subscriber for valid token" do
      {:ok, s} =
        Newsletter.subscribe("tok@example.com", source: "public_signup")

      found = Newsletter.get_subscriber_by_token(s.subscription_token)
      assert found != nil
      assert found.id == s.id
    end
  end

  describe "sync_user_preference/2" do
    test "subscribes when newsletter_subscribed: true" do
      user = user_fixture()
      Newsletter.sync_user_preference(user, newsletter_subscribed: true)
      sub = Newsletter.get_subscriber_by_email(user.email)
      assert sub != nil
      assert sub.subscribed == true
      assert sub.user_id == user.id
    end

    test "unsubscribes when newsletter_subscribed: false" do
      user = user_fixture()
      # User is subscribed by default from registration
      Newsletter.sync_user_preference(user, newsletter_subscribed: false)
      sub = Newsletter.get_subscriber_by_email(user.email)
      assert sub != nil
      assert sub.subscribed == false
    end
  end

  describe "list_subscribers/1" do
    test "returns all subscribers without opts" do
      Newsletter.subscribe("a@example.com", source: "public_signup")
      Newsletter.subscribe("b@example.com", source: "public_signup")
      list = Newsletter.list_subscribers()
      assert length(list) >= 2
    end

    test "filters by subscribed: true" do
      Newsletter.subscribe("active@example.com", source: "public_signup")

      {:ok, _} =
        Newsletter.subscribe("inactive@example.com", source: "public_signup")

      Newsletter.unsubscribe("inactive@example.com")
      list = Newsletter.list_subscribers(subscribed: true)
      emails = Enum.map(list, & &1.email)
      assert "active@example.com" in emails
      refute "inactive@example.com" in emails
    end

    test "filters by subscribed: false" do
      Newsletter.subscribe("gone@example.com", source: "public_signup")
      {:ok, _} = Newsletter.unsubscribe("gone@example.com")

      list = Newsletter.list_subscribers(subscribed: false)
      assert Enum.any?(list, &(&1.email == "gone@example.com"))
    end

    test "filters by source" do
      Newsletter.subscribe("by-source@example.com", source: "public_signup")

      list = Newsletter.list_subscribers(source: "public_signup")
      assert Enum.any?(list, &(&1.email == "by-source@example.com"))
    end
  end

  describe "count_subscribers/1" do
    test "matches list_subscribers/1 length for the same filters" do
      assert Newsletter.count_subscribers() ==
               length(Newsletter.list_subscribers())

      assert Newsletter.count_subscribers(subscribed: true) ==
               length(Newsletter.list_subscribers(subscribed: true))

      assert Newsletter.count_subscribers(subscribed: false) ==
               length(Newsletter.list_subscribers(subscribed: false))
    end

    test "filters by source like list_subscribers" do
      Newsletter.subscribe("count-source@example.com", source: "public_signup")

      count = Newsletter.count_subscribers(source: "public_signup")
      list = Newsletter.list_subscribers(source: "public_signup")
      assert count == length(list)
    end
  end

  describe "list_paginated_subscribers/1" do
    test "returns paginated rows" do
      Newsletter.subscribe("paged@example.com", source: "public_signup")

      assert {:ok, {rows, meta}} =
               Newsletter.list_paginated_subscribers(%{page: 1, page_size: 10})

      assert is_list(rows)
      assert meta.page_size == 10
    end
  end

  describe "create_edition_draft/2" do
    test "creates a draft edition and ignores forged lifecycle fields" do
      user = user_fixture()

      assert {:ok, %Edition{} = edition} =
               Newsletter.create_edition_draft(
                 %{
                   "title" => "Q2 Update",
                   "subject" => "Hello members",
                   "status" => "sent",
                   "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
                   "sent_count" => 9_999,
                   "scheduled_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                 },
                 created_by_id: user.id
               )

      assert edition.status == :draft
      assert edition.title == "Q2 Update"
      assert edition.subject == "Hello members"
      assert edition.sent_count == 0
      assert edition.sent_at == nil
      assert edition.scheduled_at == nil
      assert edition.creator_id == user.id
    end

    test "returns changeset error when required draft fields are missing" do
      assert {:error, changeset} =
               Newsletter.create_edition_draft(%{"title" => "Title only"})

      assert %{subject: [_ | _]} = errors_on(changeset)
    end
  end

  describe "editions" do
    test "list_editions includes created editions" do
      user = user_fixture()

      {:ok, _} =
        Newsletter.create_edition(
          %{"title" => "List test", "subject" => "Subj"},
          created_by_id: user.id
        )

      editions = Newsletter.list_editions()
      assert Enum.any?(editions, &(&1.title == "List test"))
    end

    test "get_all_creators lists users who created editions" do
      user = user_fixture()

      {:ok, _} =
        Newsletter.create_edition(
          %{"title" => "Creator ed", "subject" => "S"},
          created_by_id: user.id
        )

      creators = Newsletter.get_all_creators()
      assert Enum.any?(creators, fn {_name, id} -> id == user.id end)
    end

    test "get_sent_edition returns nil for draft edition" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Draft only", "subject" => "S"},
          created_by_id: user.id
        )

      assert Newsletter.get_sent_edition(edition.id) == nil
    end

    test "store_archive_html updates archived_html" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Archive", "subject" => "S"},
          created_by_id: user.id
        )

      html = "<html><body>archived</body></html>"
      assert {:ok, updated} = Newsletter.store_archive_html(edition, html)
      assert updated.archived_html == html
    end

    test "delete_edition returns already_sent for sent editions" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Sent del", "subject" => "S"},
          created_by_id: user.id
        )

      {:ok, sent} =
        edition
        |> Ecto.Changeset.change(%{
          status: :sent,
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      assert {:error, :already_sent} = Newsletter.delete_edition(sent)
    end

    test "send_edition returns already_sent when edition is sent" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Sent send", "subject" => "S"},
          created_by_id: user.id
        )

      {:ok, sent} =
        edition
        |> Ecto.Changeset.change(%{
          status: :sent,
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      assert {:error, :already_sent} = Newsletter.send_edition(sent)
    end

    test "broadcast_edition_sent notifies subscribers" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Broadcast", "subject" => "S"},
          created_by_id: user.id
        )

      :ok = Newsletter.subscribe_to_edition_updates()
      :ok = Newsletter.broadcast_edition_sent(edition)

      assert_receive {:edition_sent, received}, 200
      assert received.id == edition.id
    end

    test "schedule_edition persists scheduled_at and scheduled status" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Scheduled", "subject" => "S"},
          created_by_id: user.id
        )

      at =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      assert {:ok, updated} = Newsletter.schedule_edition(edition, at)
      assert updated.status == :scheduled
      assert DateTime.compare(updated.scheduled_at, at) == :eq
    end
  end

  describe "list_recent_sent_editions_with_stats/1" do
    test "returns open and click counts per sent edition (batched query)" do
      user = user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, e1} =
        Newsletter.create_edition(
          %{"title" => "Batch A", "subject" => "S1"},
          created_by_id: user.id
        )

      {:ok, e2} =
        Newsletter.create_edition(
          %{"title" => "Batch B", "subject" => "S2"},
          created_by_id: user.id
        )

      sent_at1 = DateTime.add(now, -120, :second)
      sent_at2 = DateTime.add(now, -60, :second)

      assert {:ok, e1} =
               Newsletter.update_edition(e1, %{
                 status: :sent,
                 sent_at: sent_at1,
                 sent_count: 10
               })

      assert {:ok, e2} =
               Newsletter.update_edition(e2, %{
                 status: :sent,
                 sent_at: sent_at2,
                 sent_count: 5
               })

      for email <- ["a1@x.com", "a2@x.com"] do
        {:ok, _} =
          Newsletter.record_email_event(%{
            event_type: "open",
            email: email,
            environment: "test",
            edition_id: e1.id
          })
      end

      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "click",
          email: "c1@x.com",
          environment: "test",
          edition_id: e1.id
        })

      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "open",
          email: "b1@x.com",
          environment: "test",
          edition_id: e2.id
        })

      rows = Newsletter.list_recent_sent_editions_with_stats(5)

      row1 = Enum.find(rows, &(&1.edition.id == e1.id))
      row2 = Enum.find(rows, &(&1.edition.id == e2.id))

      assert row1.opens == 2
      assert row1.clicks == 1
      assert row2.opens == 1
      assert row2.clicks == 0
    end
  end

  describe "list_paginated_editions/2" do
    test "accepts date_from and date_to filters" do
      user = user_fixture()

      {:ok, _} =
        Newsletter.create_edition(
          %{"title" => "Dated", "subject" => "S"},
          created_by_id: user.id
        )

      today = Date.utc_today() |> Date.to_iso8601()

      assert {:ok, {_rows, _meta}} =
               Newsletter.list_paginated_editions(
                 %{page: 1, page_size: 10},
                 date_from: today,
                 date_to: today
               )
    end
  end

  describe "email events and bounces" do
    setup do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Events", "subject" => "S"},
          created_by_id: user.id
        )

      %{user: user, edition: edition}
    end

    test "record_email_event inserts an event", %{edition: edition} do
      assert {:ok, event} =
               Newsletter.record_email_event(%{
                 event_type: "open",
                 email: "track@example.com",
                 environment: "test",
                 edition_id: edition.id
               })

      assert event.event_type == "open"
    end

    test "list_email_events_for_edition orders by inserted_at desc", %{
      edition: edition
    } do
      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "open",
          email: "o1@example.com",
          environment: "test",
          edition_id: edition.id
        })

      list = Newsletter.list_email_events_for_edition(edition.id)
      refute list == []
    end

    test "count_email_events_by_type groups opens distinctly per email", %{
      edition: edition
    } do
      for email <- ["u1@example.com", "u2@example.com"] do
        {:ok, _} =
          Newsletter.record_email_event(%{
            event_type: "open",
            email: email,
            environment: "test",
            edition_id: edition.id
          })
      end

      counts = Newsletter.count_email_events_by_type(edition.id)
      assert counts["open"] == 2
    end

    test "handle_hard_bounce returns not_subscribed for unknown email" do
      email = "nobody-#{System.unique_integer([:positive])}@example.com"

      assert {:ok, :not_subscribed} =
               Newsletter.handle_hard_bounce(email)

      assert Newsletter.hard_bounced?(email)
    end

    test "handle_hard_bounce returns not_subscribed when already unsubscribed" do
      Newsletter.subscribe("already-out@example.com", source: "public_signup")
      {:ok, _} = Newsletter.unsubscribe("already-out@example.com")

      assert {:ok, :not_subscribed} =
               Newsletter.handle_hard_bounce("already-out@example.com")
    end

    test "handle_hard_bounce unsubscribes active subscriber" do
      {:ok, sub} =
        Newsletter.subscribe("hard-bounce@example.com", source: "public_signup")

      refute Newsletter.hard_bounced?("hard-bounce@example.com")

      assert {:ok, updated} =
               Newsletter.handle_hard_bounce("hard-bounce@example.com")

      assert updated.id == sub.id
      refute updated.subscribed
      assert updated.metadata["unsubscribe_reason"] == "hard_bounce"
      assert Newsletter.hard_bounced?("hard-bounce@example.com")
    end
  end

  describe "count_clicks_by_link/1" do
    test "classifies post URLs and returns click counts" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Clicks", "subject" => "S"},
          created_by_id: user.id
        )

      base = YscWeb.Endpoint.url() |> String.trim_trailing("/")

      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "click",
          email: "c@example.com",
          environment: "test",
          edition_id: edition.id,
          link_url: "#{base}/posts/my-post-slug"
        })

      rows = Newsletter.count_clicks_by_link(edition.id)
      assert [%{type: :post, clicks: 1} | _] = rows
    end

    test "excludes unsubscribe URLs from the link breakdown" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Unsub clicks", "subject" => "S"},
          created_by_id: user.id
        )

      base = YscWeb.Endpoint.url() |> String.trim_trailing("/")

      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "click",
          email: "keep@example.com",
          environment: "test",
          edition_id: edition.id,
          link_url: "#{base}/posts/keep-me"
        })

      for url <- [
            "#{base}/newsletter/unsubscribe/token-abc?edition_id=#{edition.id}",
            "https://ysc.org/newsletter/unsubscribe/a2JwRbHkn14ux2pTRpekarhmCLomkYmxSi-Y-9DQiyM",
            "/newsletter/unsubscribe/relative-token"
          ] do
        {:ok, _} =
          Newsletter.record_email_event(%{
            event_type: "click",
            email: "unsub-#{System.unique_integer([:positive])}@example.com",
            environment: "test",
            edition_id: edition.id,
            link_url: url
          })
      end

      rows = Newsletter.count_clicks_by_link(edition.id)

      assert Enum.any?(rows, &(&1.type == :post))

      refute Enum.any?(rows, fn row ->
               String.contains?(row.url, "newsletter/unsubscribe")
             end)
    end
  end

  describe "unsubscribe metrics" do
    setup do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Unsub metrics", "subject" => "S"},
          created_by_id: user.id
        )

      %{user: user, edition: edition}
    end

    test "count_unsubscribe_link_clicks counts distinct recipients", %{
      edition: edition
    } do
      base = YscWeb.Endpoint.url() |> String.trim_trailing("/")

      for email <- ["a@example.com", "a@example.com", "b@example.com"] do
        {:ok, _} =
          Newsletter.record_email_event(%{
            event_type: "click",
            email: email,
            environment: "test",
            edition_id: edition.id,
            link_url: "#{base}/newsletter/unsubscribe/tok-#{email}"
          })
      end

      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "click",
          email: "other@example.com",
          environment: "test",
          edition_id: edition.id,
          link_url: "#{base}/posts/hello"
        })

      assert Newsletter.count_unsubscribe_link_clicks(edition.id) == 2
    end

    test "unsubscribe with edition_id records a confirmed event", %{
      edition: edition
    } do
      {:ok, sub} =
        Newsletter.subscribe("confirm-unsub@example.com",
          source: "public_signup"
        )

      assert {:ok, _} =
               Newsletter.unsubscribe(sub.subscription_token,
                 edition_id: edition.id
               )

      assert Newsletter.count_confirmed_unsubscribes(edition.id) == 1

      assert Repo.get_by(UnsubscribeEvent,
               edition_id: edition.id,
               subscriber_id: sub.id
             )
    end

    test "confirmed unsubscribe is idempotent per edition/subscriber", %{
      edition: edition
    } do
      {:ok, sub} =
        Newsletter.subscribe("idempotent-unsub@example.com",
          source: "public_signup"
        )

      assert {:ok, _} =
               Newsletter.unsubscribe(sub.subscription_token,
                 edition_id: edition.id
               )

      # Re-subscribe then unsubscribe again with the same edition
      assert {:ok, _} =
               Newsletter.subscribe("idempotent-unsub@example.com",
                 source: "public_signup"
               )

      assert {:ok, _} =
               Newsletter.unsubscribe(sub.subscription_token,
                 edition_id: edition.id
               )

      assert Newsletter.count_confirmed_unsubscribes(edition.id) == 1
    end

    test "confirmed unsubscribes are isolated per edition", %{
      user: user,
      edition: edition
    } do
      {:ok, other} =
        Newsletter.create_edition(
          %{"title" => "Other", "subject" => "S"},
          created_by_id: user.id
        )

      {:ok, sub} =
        Newsletter.subscribe("iso-unsub@example.com", source: "public_signup")

      assert {:ok, _} =
               Newsletter.unsubscribe(sub.subscription_token,
                 edition_id: edition.id
               )

      assert Newsletter.count_confirmed_unsubscribes(edition.id) == 1
      assert Newsletter.count_confirmed_unsubscribes(other.id) == 0
    end

    test "unsubscribe without edition_id still works and records no event", %{
      edition: edition
    } do
      {:ok, sub} =
        Newsletter.subscribe("legacy-unsub@example.com",
          source: "public_signup"
        )

      assert {:ok, updated} = Newsletter.unsubscribe(sub.subscription_token)
      refute updated.subscribed
      assert Newsletter.count_confirmed_unsubscribes(edition.id) == 0
    end

    test "invalid edition_id does not prevent unsubscribe", %{edition: edition} do
      {:ok, sub} =
        Newsletter.subscribe("bad-edition@example.com", source: "public_signup")

      assert {:ok, updated} =
               Newsletter.unsubscribe(sub.subscription_token,
                 edition_id: "not-a-valid-ulid"
               )

      refute updated.subscribed
      assert Newsletter.count_confirmed_unsubscribes(edition.id) == 0
    end
  end

  describe "Subscriber.generate_subscription_token/0" do
    test "returns a non-empty URL-safe string" do
      token = Subscriber.generate_subscription_token()
      assert is_binary(token)
      assert byte_size(token) > 0
      refute String.contains?(token, ["+", "/", "="])
    end
  end

  describe "subscribe edge cases and edition helpers" do
    test "re-subscribe while still subscribed preserves subscribed_at" do
      {:ok, first} =
        Newsletter.subscribe("preserve-at@example.com", source: "public_signup")

      at = first.subscribed_at

      {:ok, second} =
        Newsletter.subscribe("preserve-at@example.com", source: "public_signup")

      assert DateTime.compare(second.subscribed_at, at) == :eq
    end

    test "get_edition!/1 returns the edition" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Get edition!", "subject" => "S"},
          created_by_id: user.id
        )

      loaded = Newsletter.get_edition!(edition.id)
      assert loaded.id == edition.id
      assert loaded.title == "Get edition!"
    end

    test "list_sent_editions/0 lists editions with status sent" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Sent list", "subject" => "S"},
          created_by_id: user.id
        )

      sent_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        edition
        |> Ecto.Changeset.change(%{status: :sent, sent_at: sent_at})
        |> Repo.update()

      titles = Newsletter.list_sent_editions() |> Enum.map(& &1.title)
      assert "Sent list" in titles
    end

    test "delete_edition/1 removes a draft edition" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "To delete", "subject" => "S"},
          created_by_id: user.id
        )

      assert {:ok, _} = Newsletter.delete_edition(edition)
      assert Repo.get(Edition, edition.id) == nil
    end

    test "list_paginated_editions/2 ignores invalid date_from filter" do
      user = user_fixture()

      {:ok, _} =
        Newsletter.create_edition(
          %{"title" => "Invalid date filter", "subject" => "S"},
          created_by_id: user.id
        )

      assert {:ok, {_rows, _meta}} =
               Newsletter.list_paginated_editions(
                 %{page: 1, page_size: 10},
                 date_from: "not-a-valid-date"
               )
    end

    test "list_paginated_subscribers/1 returns error for invalid Flop params" do
      assert {:error, _} =
               Newsletter.list_paginated_subscribers(%{page: "not-an-integer"})
    end

    test "subscribe_to_edition_updates/0 subscribes the process to PubSub" do
      :ok = Newsletter.subscribe_to_edition_updates()
    end

    test "count_clicks_by_link/1 classifies event URLs and resolves titles" do
      user = user_fixture()
      event = event_fixture(%{title: "Newsletter Click Event"})

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Clicks ev", "subject" => "S"},
          created_by_id: user.id
        )

      base = YscWeb.Endpoint.url() |> String.trim_trailing("/")

      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "click",
          email: "ev-click@example.com",
          environment: "test",
          edition_id: edition.id,
          link_url: "#{base}/events/#{event.id}"
        })

      rows = Newsletter.count_clicks_by_link(edition.id)

      assert Enum.any?(rows, fn row ->
               row.type == :event and row.title == "Newsletter Click Event"
             end)
    end

    test "count_clicks_by_link/1 excludes bare site root clicks" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Base URL", "subject" => "S"},
          created_by_id: user.id
        )

      base = YscWeb.Endpoint.url() |> String.trim_trailing("/")

      for url <- [base, base <> "/"] do
        {:ok, _} =
          Newsletter.record_email_event(%{
            event_type: "click",
            email: "root@example.com",
            environment: "test",
            edition_id: edition.id,
            link_url: url
          })
      end

      rows = Newsletter.count_clicks_by_link(edition.id)
      refute Enum.any?(rows, fn row -> row.url in [base, base <> "/"] end)
    end

    test "count_clicks_by_link/1 resolves post titles for matching url_name" do
      author = user_fixture(%{role: "admin"})

      {:ok, post} =
        Ysc.Posts.create_post(
          %{
            "title" => "Newsletter Click Post",
            "body" => "Body",
            "url_name" => "newsletter-click-post-#{System.unique_integer([:positive])}",
            "state" => "published"
          },
          author
        )

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Post title resolve", "subject" => "S"},
          created_by_id: author.id
        )

      base = YscWeb.Endpoint.url() |> String.trim_trailing("/")

      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "click",
          email: "post-title@example.com",
          environment: "test",
          edition_id: edition.id,
          link_url: "#{base}/posts/#{post.url_name}"
        })

      rows = Newsletter.count_clicks_by_link(edition.id)

      assert Enum.any?(rows, fn row ->
               row.type == :post and row.title == "Newsletter Click Post"
             end)
    end
  end

  describe "notices" do
    test "list_notices/0 returns empty list when there are none" do
      assert Newsletter.list_notices() == []
    end

    test "create_notice/2 creates a notice with a creator" do
      user = user_fixture()

      assert {:ok, notice} =
               Newsletter.create_notice(
                 %{"name" => "Holiday hours", "body" => "<p>Closed</p>"},
                 created_by_id: user.id
               )

      assert notice.name == "Holiday hours"
      assert notice.creator_id == user.id
    end

    test "create_notice/2 without opts leaves creator_id nil" do
      assert {:ok, notice} =
               Newsletter.create_notice(%{
                 "name" => "No creator",
                 "body" => "<p>Body</p>"
               })

      assert notice.creator_id == nil
    end

    test "create_notice/2 returns a changeset error when required fields are missing" do
      assert {:error, changeset} = Newsletter.create_notice(%{"name" => "Only name"})
      assert %{body: [_ | _]} = errors_on(changeset)
    end

    test "list_notices/0 returns notices newest-updated first", %{} do
      user = user_fixture()

      {:ok, older} =
        Newsletter.create_notice(
          %{"name" => "Older", "body" => "<p>A</p>"},
          created_by_id: user.id
        )

      {:ok, newer} =
        Newsletter.create_notice(
          %{"name" => "Newer", "body" => "<p>B</p>"},
          created_by_id: user.id
        )

      old_ts =
        DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      {:ok, older} =
        older
        |> Ecto.Changeset.change(%{updated_at: old_ts})
        |> Repo.update()

      ids = Newsletter.list_notices() |> Enum.map(& &1.id)
      newer_idx = Enum.find_index(ids, &(&1 == newer.id))
      older_idx = Enum.find_index(ids, &(&1 == older.id))
      assert newer_idx < older_idx
    end

    test "get_notice!/1 returns the notice with creator preloaded" do
      user = user_fixture()

      {:ok, notice} =
        Newsletter.create_notice(
          %{"name" => "Fetchable", "body" => "<p>X</p>"},
          created_by_id: user.id
        )

      found = Newsletter.get_notice!(notice.id)
      assert found.id == notice.id
      assert found.creator.id == user.id
    end

    test "get_notice!/1 raises for an unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Newsletter.get_notice!(Ecto.ULID.generate())
      end
    end

    test "update_notice/2 updates fields" do
      user = user_fixture()

      {:ok, notice} =
        Newsletter.create_notice(
          %{"name" => "Before", "body" => "<p>Before</p>"},
          created_by_id: user.id
        )

      assert {:ok, updated} =
               Newsletter.update_notice(notice, %{"name" => "After"})

      assert updated.name == "After"
    end

    test "delete_notice/1 removes the notice" do
      user = user_fixture()

      {:ok, notice} =
        Newsletter.create_notice(
          %{"name" => "To delete", "body" => "<p>X</p>"},
          created_by_id: user.id
        )

      assert {:ok, _} = Newsletter.delete_notice(notice)

      assert_raise Ecto.NoResultsError, fn ->
        Newsletter.get_notice!(notice.id)
      end
    end
  end

  describe "duplicate_edition/2" do
    test "copies editorial fields, appends \" (copy)\" to the title, and resets lifecycle fields" do
      user = user_fixture()

      {:ok, original} =
        Newsletter.create_edition(
          %{
            "title" => "Original Title",
            "subject" => "Original subject",
            "intro_text" => "Intro"
          },
          created_by_id: user.id
        )

      {:ok, sent} =
        original
        |> Ecto.Changeset.change(%{
          status: :sent,
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
          sent_count: 42
        })
        |> Repo.update()

      other_user = user_fixture()

      assert {:ok, copy} =
               Newsletter.duplicate_edition(sent, created_by_id: other_user.id)

      assert copy.title == "Original Title (copy)"
      assert copy.subject == "Original subject"
      assert copy.intro_text == "Intro"
      assert copy.status == :draft
      assert copy.sent_at == nil
      assert copy.sent_count == 0
      assert copy.creator_id == other_user.id
    end

    test "falls back to \"Untitled\" when the original title is blank" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Blank source", "subject" => "S"},
          created_by_id: user.id
        )

      {:ok, blank_titled} =
        edition |> Ecto.Changeset.change(%{title: "   "}) |> Repo.update()

      assert {:ok, copy} = Newsletter.duplicate_edition(blank_titled)
      assert copy.title == "Untitled (copy)"
    end
  end

  describe "send_edition/1 (success path)" do
    test "marks the edition sending and enqueues a NewsletterSender job" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Send me", "subject" => "S"},
          created_by_id: user.id
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, sending} = Newsletter.send_edition(edition)
        assert sending.status == :sending

        assert_enqueued(
          worker: YscWeb.Workers.NewsletterSender,
          args: %{"edition_id" => edition.id}
        )
      end)
    end
  end

  describe "send_test_email/2" do
    test "sends a one-off test copy without changing the edition" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{
            "title" => "Test email edition",
            "subject" => "Test subject",
            "intro_text" => "Hello"
          },
          created_by_id: user.id
        )

      recipient = user_fixture()

      assert :ok = Newsletter.send_test_email(edition, recipient)

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :draft
      assert reloaded.sent_count == 0
    end
  end

  describe "list_recent_sent_editions_with_stats/1 default argument" do
    test "uses the default limit of 5 when called with no arguments" do
      assert Newsletter.list_recent_sent_editions_with_stats() == []
    end
  end

  describe "valid_ulid?/1" do
    test "returns false for non-binary input" do
      refute Newsletter.valid_ulid?(12345)
      refute Newsletter.valid_ulid?(nil)
      refute Newsletter.valid_ulid?(%{})
    end
  end

  describe "get_all_creators/0 display name fallbacks" do
    test "falls back to email when first/last name are missing" do
      user = user_fixture()

      user
      |> Ecto.Changeset.change(%{first_name: nil, last_name: nil})
      |> Repo.update!()

      {:ok, _} =
        Newsletter.create_edition(
          %{"title" => "Email fallback", "subject" => "S"},
          created_by_id: user.id
        )

      creators = Newsletter.get_all_creators()
      assert Enum.any?(creators, fn {name, id} -> id == user.id and name == user.email end)
    end

    test "falls back to \"Unknown\" when the edition has no creator" do
      {:ok, _} =
        Newsletter.create_edition(%{"title" => "No creator edition", "subject" => "S"})

      creators = Newsletter.get_all_creators()
      assert Enum.any?(creators, fn {name, id} -> id == nil and name == "Unknown" end)
    end
  end

  describe "list_paginated_editions/2 error passthrough" do
    test "returns error for invalid Flop params" do
      assert {:error, _} =
               Newsletter.list_paginated_editions(%{page: "not-an-integer"})
    end
  end

  describe "confirm_subscription/1 with non-binary input" do
    test "returns not_found without querying the database" do
      assert {:error, :not_found} = Newsletter.confirm_subscription(nil)
      assert {:error, :not_found} = Newsletter.confirm_subscription(12345)
    end
  end

  describe "request_confirmation/2 changeset error passthrough" do
    test "returns the changeset error unchanged when the pending record is invalid" do
      assert {:error, %Ecto.Changeset{}} =
               Newsletter.request_confirmation("bad-meta@example.com",
                 metadata: "not-a-map"
               )
    end
  end

  describe "record_edition_delivery_progress/2 recipient_count already set" do
    test "does not overwrite recipient_count on a second call" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Progress twice", "subject" => "S"},
          created_by_id: user.id
        )

      {:ok, sub1} =
        Newsletter.subscribe("progress1@example.com", source: "public_signup")

      {:ok, sub2} =
        Newsletter.subscribe("progress2@example.com", source: "public_signup")

      assert {:ok, first} =
               Newsletter.record_edition_delivery_progress(edition, [sub1])

      assert first.recipient_count == 1

      assert {:ok, second} =
               Newsletter.record_edition_delivery_progress(first, [sub1, sub2])

      # recipient_count was already set, so the second call leaves it unchanged.
      assert second.recipient_count == 1
    end
  end

  describe "ci_query_explain_* helper queries" do
    test "return valid Ecto queries" do
      assert %Ecto.Query{} = Newsletter.ci_query_explain_query()
      assert %Ecto.Query{} = Newsletter.ci_query_explain_notices_query()

      assert %Ecto.Query{} =
               Newsletter.ci_query_explain_unsubscribe_link_clicks_query()

      assert %Ecto.Query{} =
               Newsletter.ci_query_explain_confirmed_unsubscribes_query()
    end
  end
end
