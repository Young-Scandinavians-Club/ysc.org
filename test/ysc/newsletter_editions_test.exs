defmodule Ysc.NewsletterEditionsTest do
  use Ysc.DataCase, async: false

  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures

  alias Ysc.Newsletter
  alias Ysc.Newsletter.Edition

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp admin_fixture, do: user_fixture(%{role: "admin"})

  defp edition_fixture(user, attrs \\ %{}) do
    {:ok, edition} =
      Newsletter.create_edition(
        Map.merge(
          %{"title" => "My Edition", "subject" => "Weekly news"},
          attrs
        ),
        created_by_id: user.id
      )

    edition
  end

  # ---------------------------------------------------------------------------
  # create_edition/2
  # ---------------------------------------------------------------------------

  describe "create_edition/2" do
    test "creates a draft edition with required fields" do
      user = admin_fixture()

      assert {:ok, %Edition{} = edition} =
               Newsletter.create_edition(
                 %{"title" => "Test Newsletter", "subject" => "Hello"},
                 created_by_id: user.id
               )

      assert edition.title == "Test Newsletter"
      assert edition.subject == "Hello"
      assert edition.status == :draft
      assert edition.sent_count == 0
      assert edition.creator_id == user.id
    end

    test "works without a creator_id" do
      assert {:ok, edition} =
               Newsletter.create_edition(%{
                 "title" => "No Creator",
                 "subject" => "Subj"
               })

      assert edition.creator_id == nil
      assert edition.status == :draft
    end

    test "returns error changeset when title is missing" do
      assert {:error, changeset} =
               Newsletter.create_edition(%{"subject" => "Oops"})

      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error changeset when subject is missing" do
      assert {:error, changeset} =
               Newsletter.create_edition(%{"title" => "Oops"})

      assert %{subject: ["can't be blank"]} = errors_on(changeset)
    end

    test "stores optional fields" do
      user = admin_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{
            "title" => "Rich Edition",
            "subject" => "Subj",
            "intro_text" => "<p>Hello</p>",
            "post_ids" => ["abc", "def"],
            "event_ids" => ["xyz"]
          },
          created_by_id: user.id
        )

      assert edition.intro_text == "<p>Hello</p>"
      assert edition.post_ids == ["abc", "def"]
      assert edition.event_ids == ["xyz"]
    end
  end

  # ---------------------------------------------------------------------------
  # get_edition!/1
  # ---------------------------------------------------------------------------

  describe "get_edition!/1" do
    test "returns the edition with preloaded associations" do
      edition = edition_fixture(admin_fixture())
      fetched = Newsletter.get_edition!(edition.id)

      assert fetched.id == edition.id
      assert fetched.cover_image == nil
      assert fetched.creator != nil
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Newsletter.get_edition!("01900000000000000000000000")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # list_editions/0
  # ---------------------------------------------------------------------------

  describe "list_editions/0" do
    test "returns editions including all created ones" do
      user = admin_fixture()
      e1 = edition_fixture(user, %{"title" => "First"})
      e2 = edition_fixture(user, %{"title" => "Second"})

      editions = Newsletter.list_editions()
      ids = Enum.map(editions, & &1.id)

      assert e1.id in ids
      assert e2.id in ids
    end

    test "returns editions sorted by descending inserted_at" do
      user = admin_fixture()
      e1 = edition_fixture(user, %{"title" => "Older"})
      e2 = edition_fixture(user, %{"title" => "Newer"})

      # Backdate e1 so it has a clearly earlier inserted_at
      past =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      Ysc.Repo.update_all(
        Ecto.Query.from(e in Edition, where: e.id == ^e1.id),
        set: [inserted_at: past]
      )

      editions = Newsletter.list_editions()
      ids = Enum.map(editions, & &1.id)

      newer_idx = Enum.find_index(ids, &(&1 == e2.id))
      older_idx = Enum.find_index(ids, &(&1 == e1.id))
      assert newer_idx < older_idx
    end
  end

  # ---------------------------------------------------------------------------
  # update_edition/2
  # ---------------------------------------------------------------------------

  describe "update_edition/2" do
    test "updates allowed fields" do
      edition = edition_fixture(admin_fixture())

      assert {:ok, updated} =
               Newsletter.update_edition(edition, %{
                 "title" => "Updated Title",
                 "subject" => "New Subject",
                 "intro_text" => "Updated intro"
               })

      assert updated.title == "Updated Title"
      assert updated.subject == "New Subject"
      assert updated.intro_text == "Updated intro"
    end

    test "returns error changeset for invalid data" do
      edition = edition_fixture(admin_fixture())

      assert {:error, changeset} =
               Newsletter.update_edition(edition, %{"title" => ""})

      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # delete_edition/1
  # ---------------------------------------------------------------------------

  describe "delete_edition/1" do
    test "deletes the edition" do
      edition = edition_fixture(admin_fixture())
      assert {:ok, _} = Newsletter.delete_edition(edition)

      assert_raise Ecto.NoResultsError, fn ->
        Newsletter.get_edition!(edition.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # send_edition/1
  # ---------------------------------------------------------------------------

  describe "send_edition/1" do
    test "returns {:ok, edition} with :sending status for a draft edition" do
      # In test mode (Oban inline), the job executes immediately; we verify the
      # return value and that the edition ends up marked as sent.
      edition = edition_fixture(admin_fixture())

      assert {:ok, sending_edition} = Newsletter.send_edition(edition)
      assert sending_edition.status == :sending

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :sent
    end

    test "returns {:ok, edition} with :sending status for a :scheduled edition (send now overrides the schedule)" do
      edition = edition_fixture(admin_fixture())

      {:ok, scheduled} =
        Newsletter.update_edition(edition, %{"status" => :scheduled})

      assert {:ok, sending_edition} = Newsletter.send_edition(scheduled)
      assert sending_edition.status == :sending
    end

    test "returns error when edition is already sent" do
      edition = edition_fixture(admin_fixture())
      {:ok, sent} = Newsletter.update_edition(edition, %{"status" => :sent})

      assert {:error, :already_sent} = Newsletter.send_edition(sent)
    end
  end

  # ---------------------------------------------------------------------------
  # schedule_edition/2
  # ---------------------------------------------------------------------------

  describe "schedule_edition/2" do
    test "persists scheduled_at and returns ok tuple" do
      edition = edition_fixture(admin_fixture())

      send_at =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      assert {:ok, updated} = Newsletter.schedule_edition(edition, send_at)

      # scheduled_at is persisted on the returned struct
      assert updated.scheduled_at == send_at
    end

    test "edition eventually transitions away from :draft" do
      # In Oban inline mode the NewsletterSender fires synchronously inside
      # schedule_edition, so by the time schedule_edition returns the edition
      # will already be :sent (0 subscribers in this test).  We verify the
      # scheduled_at is stored and the edition is no longer :draft.
      edition = edition_fixture(admin_fixture())

      send_at =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      {:ok, _} = Newsletter.schedule_edition(edition, send_at)

      reloaded = Newsletter.get_edition!(edition.id)
      refute reloaded.status == :draft
    end
  end

  # ---------------------------------------------------------------------------
  # send_test_email/2
  # ---------------------------------------------------------------------------

  describe "send_test_email/2" do
    test "delivers an email with [TEST] subject prefix to the user" do
      user = admin_fixture()

      edition =
        edition_fixture(user, %{
          "title" => "Spring Edition",
          "subject" => "Spring news"
        })

      recipient = user_fixture(%{email: "alice@example.com"})

      assert :ok = Newsletter.send_test_email(edition, recipient)

      assert_email_sent(fn email ->
        assert email.subject == "[YSC] [TEST] Spring news"

        assert Enum.any?(email.to, fn {_name, addr} ->
                 addr == "alice@example.com"
               end)
      end)
    end

    test "uses subject line in the email subject header" do
      user = admin_fixture()

      edition =
        edition_fixture(user, %{
          "title" => "My Title",
          "subject" => "My Subject Line"
        })

      recipient = user_fixture()

      Newsletter.send_test_email(edition, recipient)

      assert_email_sent(subject: "[YSC] [TEST] My Subject Line")
    end

    test "does not change edition status or sent_count" do
      user = admin_fixture()
      edition = edition_fixture(user)
      recipient = user_fixture()

      Newsletter.send_test_email(edition, recipient)

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :draft
      assert reloaded.sent_count == 0
    end
  end

  # ---------------------------------------------------------------------------
  # get_all_creators/0
  # ---------------------------------------------------------------------------

  describe "get_all_creators/0" do
    test "returns list of {display_name, creator_id} tuples for creators" do
      user =
        user_fixture(%{role: "admin", first_name: "Zara", last_name: "Smith"})

      edition_fixture(user, %{"title" => "Ed 1"})

      creators = Newsletter.get_all_creators()
      assert is_list(creators)

      found = Enum.find(creators, fn {_, id} -> id == user.id end)
      assert found != nil
      assert elem(found, 0) =~ "Zara"
    end
  end

  # ---------------------------------------------------------------------------
  # duplicate_edition/2
  # ---------------------------------------------------------------------------

  describe "duplicate_edition/2" do
    test "creates a draft copy of editorial fields" do
      user = admin_fixture()
      other = admin_fixture()

      {:ok, source} =
        Newsletter.create_edition(
          %{
            "title" => "Spring Update",
            "subject" => "Hello spring",
            "intro_text" => "<p>Welcome back</p>",
            "post_ids" => ["post-1"],
            "event_ids" => ["event-1"]
          },
          created_by_id: user.id
        )

      {:ok, source} =
        Newsletter.update_edition(source, %{
          status: :sent,
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
          sent_count: 42,
          archived_html: "<html>archived</html>"
        })

      assert {:ok, copy} =
               Newsletter.duplicate_edition(source, created_by_id: other.id)

      assert copy.id != source.id
      assert copy.title == "Spring Update (copy)"
      assert copy.subject == "Hello spring"
      assert copy.intro_text == "<p>Welcome back</p>"
      assert copy.post_ids == ["post-1"]
      assert copy.event_ids == ["event-1"]
      assert copy.status == :draft
      assert copy.sent_count == 0
      assert copy.sent_at == nil
      assert copy.scheduled_at == nil
      assert copy.archived_html == nil
      assert copy.creator_id == other.id
    end

    test "truncates long titles when appending (copy)" do
      user = admin_fixture()
      long_title = String.duplicate("A", 250)
      edition = edition_fixture(user, %{"title" => long_title})

      assert {:ok, copy} =
               Newsletter.duplicate_edition(edition, created_by_id: user.id)

      assert String.ends_with?(copy.title, " (copy)")
      assert String.length(copy.title) <= 255
    end
  end
end
