defmodule YscWeb.Workers.NewsletterScheduleCheckerTest do
  # async: false: Tasks spawned by NewsletterSender need the shared sandbox.
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Newsletter
  alias Ysc.Newsletter.Edition
  alias Ysc.Repo
  alias YscWeb.Workers.NewsletterScheduleChecker

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp edition_fixture(attrs \\ %{}) do
    user = user_fixture(%{role: "admin"})

    {:ok, edition} =
      Newsletter.create_edition(
        Map.merge(%{"title" => "Edition", "subject" => "Weekly"}, attrs),
        created_by_id: user.id
      )

    edition
  end

  # Set an edition's status to :scheduled with a past scheduled_at directly in
  # the DB, bypassing schedule_edition (which in inline Oban mode would
  # immediately fire NewsletterSender and mark the edition as :sent).
  defp make_overdue_scheduled(edition) do
    past =
      DateTime.utc_now()
      |> DateTime.add(-300, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(
      Ecto.Query.from(e in Edition, where: e.id == ^edition.id),
      set: [status: :scheduled, scheduled_at: past]
    )

    Repo.get!(Edition, edition.id)
  end

  defp make_future_scheduled(edition) do
    future =
      DateTime.utc_now()
      |> DateTime.add(3600, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(
      Ecto.Query.from(e in Edition, where: e.id == ^edition.id),
      set: [status: :scheduled, scheduled_at: future]
    )

    Repo.get!(Edition, edition.id)
  end

  # ---------------------------------------------------------------------------
  # perform/1
  # ---------------------------------------------------------------------------

  describe "perform/1" do
    test "triggers NewsletterSender for overdue scheduled editions" do
      edition = edition_fixture() |> make_overdue_scheduled()
      assert edition.status == :scheduled

      # In inline Oban mode the checker's Oban.insert calls immediately run
      # NewsletterSender, which marks the edition as :sent.
      assert :ok = perform_job(NewsletterScheduleChecker, %{})

      reloaded = Repo.get!(Edition, edition.id)
      assert reloaded.status == :sent
    end

    test "does not trigger NewsletterSender for editions scheduled in the future" do
      edition = edition_fixture() |> make_future_scheduled()

      assert :ok = perform_job(NewsletterScheduleChecker, %{})

      reloaded = Repo.get!(Edition, edition.id)
      # Future edition stays :scheduled — checker correctly ignored it
      assert reloaded.status == :scheduled
    end

    test "does not affect :draft editions" do
      edition = edition_fixture()
      assert edition.status == :draft

      assert :ok = perform_job(NewsletterScheduleChecker, %{})

      reloaded = Repo.get!(Edition, edition.id)
      assert reloaded.status == :draft
    end

    test "does not double-send already :sent editions" do
      edition = edition_fixture()

      Repo.update_all(
        Ecto.Query.from(e in Edition, where: e.id == ^edition.id),
        set: [status: :sent, sent_count: 5]
      )

      assert :ok = perform_job(NewsletterScheduleChecker, %{})

      reloaded = Repo.get!(Edition, edition.id)
      # sent_count unchanged — sender skipped it because status was :sent
      assert reloaded.sent_count == 5
    end

    test "handles an empty database gracefully" do
      assert :ok = perform_job(NewsletterScheduleChecker, %{})
    end

    test "handles multiple overdue editions in one pass" do
      e1 = edition_fixture(%{"title" => "E1"}) |> make_overdue_scheduled()
      e2 = edition_fixture(%{"title" => "E2"}) |> make_overdue_scheduled()

      assert :ok = perform_job(NewsletterScheduleChecker, %{})

      assert Repo.get!(Edition, e1.id).status == :sent
      assert Repo.get!(Edition, e2.id).status == :sent
    end
  end
end
