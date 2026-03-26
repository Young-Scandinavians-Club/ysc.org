defmodule YscWeb.Workers.NewsletterSenderTest do
  # async: false because Task.async_stream spawns processes that share the sandbox.
  use Ysc.DataCase, async: false

  import Swoosh.TestAssertions
  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Newsletter
  alias Ysc.Newsletter.Edition
  alias Ysc.Messages.MessageIdempotency
  alias Ysc.Repo
  alias YscWeb.Workers.NewsletterSender

  # Task.async_stream spawns concurrent processes that need their own sandbox
  # connections. Shared mode allows every spawned process to check out its own
  # connection from the pool without requiring explicit allow/3 calls.
  #
  # Also flush any leftover {:email, _} messages that previous tests (which share
  # this process's mailbox in async: false mode) may have left behind, so that
  # Swoosh assertions in each test only see emails sent during that test.
  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Ysc.Repo, {:shared, self()})
    flush_mailbox()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp setup_edition(_context) do
    # Create admin user first (registration auto-subscribes them).
    admin = user_fixture(%{role: "admin"})

    {:ok, edition} =
      Newsletter.create_edition(
        %{"title" => "Weekly", "subject" => "This week"},
        created_by_id: admin.id
      )

    %{edition: edition, admin: admin}
  end

  defp subscribe(email) do
    {:ok, sub} = Newsletter.subscribe(email, source: "test")
    sub
  end

  defp active_subscriber_count do
    Newsletter.list_subscribers(subscribed: true) |> length()
  end

  defp flush_mailbox do
    receive do
      {:email, _} -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  defp idempotency_records_for(edition) do
    Repo.all(
      from m in MessageIdempotency,
        where: m.message_template == "newsletter_edition",
        where: like(m.idempotency_key, ^"newsletter_#{edition.id}_%")
    )
  end

  defp pre_insert_idempotency(edition, subscriber) do
    Repo.insert!(
      MessageIdempotency.changeset(%MessageIdempotency{}, %{
        message_type: :email,
        idempotency_key: "newsletter_#{edition.id}_#{subscriber.id}",
        message_template: "newsletter_edition",
        params: %{edition_id: edition.id},
        email: subscriber.email
      })
    )
  end

  # ---------------------------------------------------------------------------
  # perform/1
  # ---------------------------------------------------------------------------

  describe "perform/1" do
    setup :setup_edition

    test "sends emails to all active subscribers and marks edition as :sent",
         %{edition: edition} do
      subscribe("alice@example.com")
      subscribe("bob@example.com")

      expected_count = active_subscriber_count()

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :sent
      assert reloaded.sent_count == expected_count
      assert reloaded.sent_at != nil
    end

    test "skips unsubscribed subscribers and only counts active ones",
         %{edition: edition} do
      subscribe("active@example.com")
      {:ok, _} = Newsletter.subscribe("inactive@example.com", source: "test")
      Newsletter.unsubscribe("inactive@example.com")

      expected_count = active_subscriber_count()

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.sent_count == expected_count
    end

    test "sends to a :scheduled edition as well as :draft editions",
         %{edition: edition} do
      {:ok, scheduled} =
        Newsletter.update_edition(edition, %{"status" => :scheduled})

      assert scheduled.status == :scheduled

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :sent
    end

    test "processes a :sending edition the same as draft/scheduled", %{
      edition: edition
    } do
      subscribe("sending-status@example.com")

      {:ok, sending} =
        Newsletter.update_edition(edition, %{"status" => :sending})

      assert sending.status == :sending

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :sent
    end

    test "skips a :sent edition and does not double-send", %{edition: edition} do
      {:ok, _} = Newsletter.update_edition(edition, %{"status" => :sent})
      subscribe("member@example.com")

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      reloaded = Repo.get!(Edition, edition.id)
      assert reloaded.sent_count == 0
    end

    test "returns :ok when edition_id is missing" do
      assert :ok = perform_job(NewsletterSender, %{})
    end

    test "accepts edition_id as atom key in job args", %{edition: edition} do
      subscribe("atom-key@example.com")

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :sent
    end

    test "returns :ok when edition does not exist" do
      assert :ok =
               perform_job(NewsletterSender, %{
                 edition_id: "01900000000000000000000000"
               })
    end

    test "sent_at is set to a recent UTC datetime", %{edition: edition} do
      before = DateTime.utc_now() |> DateTime.truncate(:second)

      :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      reloaded = Newsletter.get_edition!(edition.id)
      assert DateTime.compare(reloaded.sent_at, before) in [:eq, :gt]
    end

    test "delivers emails with [YSC] prefixed subject line", %{edition: edition} do
      subscribe("reader@example.com")

      :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      assert_email_sent(subject: "[YSC] This week")
    end

    test "handles nil intro_text in plain text fallback", %{edition: edition} do
      {:ok, _} = Newsletter.update_edition(edition, %{"intro_text" => nil})
      subscribe("nil-intro@example.com")

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :sent
    end

    test "accepts edition_id as string key (JSON-style args)", %{
      edition: edition
    } do
      subscribe("string-key-edition@example.com")

      assert :ok =
               perform_job(NewsletterSender, %{"edition_id" => edition.id})

      assert Newsletter.get_edition!(edition.id).status == :sent
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotency
  # ---------------------------------------------------------------------------

  describe "idempotency records" do
    setup :setup_edition

    test "creates one MessageIdempotency record per active subscriber after sending",
         %{edition: edition} do
      alice = subscribe("alice@example.com")
      bob = subscribe("bob@example.com")
      expected_count = active_subscriber_count()

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      records = idempotency_records_for(edition)
      assert length(records) == expected_count

      # Each record is keyed with the edition id and the subscriber's own id.
      subscriber_ids =
        Newsletter.list_subscribers(subscribed: true)
        |> Enum.map(& &1.id)
        |> MapSet.new()

      for record <- records do
        [_, edition_id_part, subscriber_id_part] =
          String.split(record.idempotency_key, "_", parts: 3)

        assert edition_id_part == edition.id
        assert MapSet.member?(subscriber_ids, subscriber_id_part)
      end

      # Spot-check known subscriber ids appear in the records.
      keys = Enum.map(records, & &1.idempotency_key) |> MapSet.new()
      assert MapSet.member?(keys, "newsletter_#{edition.id}_#{alice.id}")
      assert MapSet.member?(keys, "newsletter_#{edition.id}_#{bob.id}")
    end

    test "does not re-deliver email when idempotency record already exists for a subscriber",
         %{edition: edition} do
      alice = subscribe("alice@example.com")
      bob = subscribe("bob@example.com")

      # Simulate alice already received her copy in a prior (failed) job attempt.
      pre_insert_idempotency(edition, alice)

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      # Verify via DB: alice must have exactly ONE idempotency record — the
      # pre-inserted one. No new record means no second email was delivered.
      alice_records =
        Repo.all(
          from m in MessageIdempotency,
            where: m.email == "alice@example.com",
            where: m.message_template == "newsletter_edition"
        )

      assert length(alice_records) == 1,
             "alice should have exactly one idempotency record (the pre-inserted one)"

      # Bob should have received his email — verify via DB: a NEW idempotency
      # record was created by the sender, meaning delivery was attempted.
      bob_record =
        Repo.get_by(MessageIdempotency,
          email: "bob@example.com",
          message_template: "newsletter_edition"
        )

      assert bob_record != nil,
             "bob should have an idempotency record created by the sender"

      assert bob_record.idempotency_key == "newsletter_#{edition.id}_#{bob.id}"
    end

    test "sent_count equals total active subscribers even when some deliveries were already idempotent",
         %{edition: edition} do
      alice = subscribe("alice@example.com")
      subscribe("bob@example.com")

      # Pre-insert alice's record to simulate a partial first attempt.
      pre_insert_idempotency(edition, alice)

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      # Idempotent skips return {:ok, _}, so they still count toward sent_count.
      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.sent_count == active_subscriber_count()
    end

    test "running the job a second time (edition already :sent) creates no new idempotency records",
         %{edition: edition} do
      subscribe("alice@example.com")

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})
      first_run_records = idempotency_records_for(edition)

      # Second invocation: edition is :sent so the worker exits early.
      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})
      second_run_records = idempotency_records_for(edition)

      assert length(first_run_records) == length(second_run_records),
             "no new idempotency records should be created on a second run"
    end

    test "idempotency records store the correct email address and template",
         %{edition: edition} do
      subscriber = subscribe("member@example.com")

      assert :ok = perform_job(NewsletterSender, %{edition_id: edition.id})

      record =
        Repo.get_by(MessageIdempotency,
          idempotency_key: "newsletter_#{edition.id}_#{subscriber.id}"
        )

      assert record != nil
      assert record.message_type == :email
      assert record.message_template == "newsletter_edition"
      assert record.email == subscriber.email
    end
  end
end
