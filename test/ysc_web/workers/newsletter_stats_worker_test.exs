defmodule YscWeb.Workers.NewsletterStatsWorkerTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Newsletter
  alias YscWeb.Workers.EmailNotifier
  alias YscWeb.Workers.NewsletterStatsWorker

  describe "perform/1" do
    test "schedules the stats snapshot through the regular email notifier" do
      user = user_fixture()
      sent_at = ~U[2026-05-06 18:30:00Z]

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Weekly", "subject" => "This week"},
          created_by_id: user.id
        )

      {:ok, edition} =
        Newsletter.update_edition(edition, %{
          "status" => :sent,
          "sent_at" => sent_at,
          "sent_count" => 10
        })

      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "open",
          email: "reader@example.com",
          environment: "test",
          edition_id: edition.id
        })

      {:ok, _} =
        Newsletter.record_email_event(%{
          event_type: "click",
          email: "reader@example.com",
          environment: "test",
          edition_id: edition.id,
          link_url: YscWeb.Endpoint.url() <> "/posts/club-news"
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        idempotency_key = "newsletter_stats_snapshot_#{edition.id}"

        assert :ok =
                 perform_job(NewsletterStatsWorker, %{edition_id: edition.id})

        assert [
                 %Oban.Job{
                   args: %{
                     "idempotency_key" => ^idempotency_key,
                     "template" => "newsletter_stats_snapshot",
                     "subject" => "[YSC Newsletter Stats] Weekly",
                     "params" => params
                   }
                 }
               ] = all_enqueued(worker: EmailNotifier)

        assert params["edition_title"] == "Weekly"
        assert params["edition_subject"] == "This week"

        assert params["top_links"] == [
                 %{
                   "clicks" => 1,
                   "title" => nil,
                   "url" => YscWeb.Endpoint.url() <> "/posts/club-news"
                 }
               ]
      end)
    end

    test "does not schedule stats for an edition that has not been sent" do
      user = user_fixture()

      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Draft", "subject" => "Not yet"},
          created_by_id: user.id
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok =
                 perform_job(NewsletterStatsWorker, %{edition_id: edition.id})

        assert all_enqueued(worker: EmailNotifier) == []
      end)
    end

    test "returns :ok when edition_id is missing" do
      assert :ok = perform_job(NewsletterStatsWorker, %{})
    end
  end
end
