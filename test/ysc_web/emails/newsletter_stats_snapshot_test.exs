defmodule YscWeb.Emails.NewsletterStatsSnapshotTest do
  use Ysc.DataCase, async: true

  alias YscWeb.Emails.NewsletterStatsSnapshot

  describe "render/1" do
    test "renders newsletter stats in the shared MJML layout" do
      edition = %{
        title: "Weekly Update",
        subject: "This week at YSC",
        sent_at: ~U[2026-05-06 18:30:00Z]
      }

      stats = %{
        sent_count: 100,
        opens: 55,
        clicks: 12,
        bounces: 1,
        complaints: 0,
        top_links: [
          %{
            url: "https://ysc.org/events/01ABC",
            clicks: 7,
            title: "Spring Dinner"
          }
        ]
      }

      html =
        edition
        |> NewsletterStatsSnapshot.build_assigns(stats)
        |> NewsletterStatsSnapshot.render()

      assert html =~ "Newsletter Stats Snapshot"
      assert html =~ "Weekly Update"
      assert html =~ "55.0% open rate"
      assert html =~ "Spring Dinner"
      assert html =~ "Young Scandinavians Club"
    end
  end

  describe "build_text_body/2" do
    test "includes the key metrics and plain top links" do
      edition = %{
        title: "Weekly Update",
        subject: "This week at YSC",
        sent_at: ~U[2026-05-06 18:30:00Z]
      }

      stats = %{
        sent_count: 10,
        opens: 5,
        clicks: 2,
        bounces: 1,
        complaints: 1,
        top_links: [
          %{url: "https://ysc.org/posts/news", clicks: 2, title: "Club News"}
        ]
      }

      text = NewsletterStatsSnapshot.build_text_body(edition, stats)

      assert text =~ "Newsletter: Weekly Update"
      assert text =~ "Unique opens: 5 (50.0%)"
      assert text =~ "Complaints: 1"
      assert text =~ "Club News"
    end
  end
end
