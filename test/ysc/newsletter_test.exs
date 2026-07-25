defmodule Ysc.NewsletterTest do
  use Ysc.DataCase

  alias Ysc.Newsletter
  alias Ysc.Newsletter.Edition
  alias Ysc.Newsletter.Subscriber
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
      assert {:ok, :not_subscribed} =
               Newsletter.handle_hard_bounce(
                 "nobody-#{System.unique_integer([:positive])}@example.com"
               )
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

      assert {:ok, updated} =
               Newsletter.handle_hard_bounce("hard-bounce@example.com")

      assert updated.id == sub.id
      refute updated.subscribed
      assert updated.metadata["unsubscribe_reason"] == "hard_bounce"
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
  end
end
