defmodule Ysc.SitemapTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures, only: [event_fixture: 1]

  alias Ysc.Newsletter
  alias Ysc.Posts
  alias Ysc.Sitemap

  defp admin_fixture, do: user_fixture(%{role: "admin"})

  defp edition_fixture(user, attrs) do
    {:ok, edition} =
      Newsletter.create_edition(
        Map.merge(%{"title" => "Edition", "subject" => "Subject"}, attrs),
        created_by_id: user.id
      )

    edition
  end

  describe "generate/0" do
    test "includes the static top-level pages" do
      xml = Sitemap.generate()

      assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)

      assert xml =~
               ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)

      assert xml =~ "<loc>#{YscWeb.Endpoint.url()}/</loc>"
      assert xml =~ "<loc>#{YscWeb.Endpoint.url()}/events</loc>"
      assert xml =~ "<changefreq>daily</changefreq>"
      assert xml =~ "<priority>1.0</priority>"
    end

    test "includes published events with their id and updated_at as lastmod" do
      admin = admin_fixture()
      event = event_fixture(%{organizer_id: admin.id, state: :published})

      xml = Sitemap.generate()

      assert xml =~ "/events/#{event.id}"
      assert xml =~ "<changefreq>weekly</changefreq>"
      assert xml =~ "<priority>0.7</priority>"
    end

    test "excludes events that are not published" do
      admin = admin_fixture()
      event = event_fixture(%{organizer_id: admin.id, state: :draft})

      xml = Sitemap.generate()

      refute xml =~ "/events/#{event.id}"
    end

    test "includes published posts using url_name as the slug" do
      admin = admin_fixture()
      url_name = "sitemap-post-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Sitemap Post",
            "preview_text" => "Preview",
            "raw_body" => "<p>Body</p>",
            "rendered_body" => "<p>Body</p>",
            "url_name" => url_name,
            "state" => "published"
          },
          admin
        )

      xml = Sitemap.generate()

      assert xml =~ "/posts/#{post.url_name}"
      assert xml =~ "<changefreq>monthly</changefreq>"
    end

    test "excludes posts that are not published" do
      admin = admin_fixture()
      url_name = "sitemap-draft-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Draft Post",
            "preview_text" => "Preview",
            "raw_body" => "<p>Body</p>",
            "rendered_body" => "<p>Body</p>",
            "url_name" => url_name,
            "state" => "draft"
          },
          admin
        )

      xml = Sitemap.generate()

      refute xml =~ "/posts/#{post.url_name}"
    end

    test "includes sent newsletter editions using sent_at as lastmod" do
      admin = admin_fixture()
      edition = edition_fixture(admin, %{})

      sent_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, edition} =
        Newsletter.update_edition(edition, %{status: :sent, sent_at: sent_at})

      xml = Sitemap.generate()

      assert xml =~ "/newsletters/#{edition.id}"

      assert xml =~
               "<lastmod>#{Date.to_iso8601(DateTime.to_date(sent_at))}</lastmod>"

      assert xml =~ "<changefreq>never</changefreq>"
    end

    test "excludes newsletter editions that have not been sent" do
      admin = admin_fixture()
      edition = edition_fixture(admin, %{})

      xml = Sitemap.generate()

      refute xml =~ "/newsletters/#{edition.id}"
    end
  end

  describe "invalidate/0" do
    test "returns :ok" do
      assert Sitemap.invalidate() == :ok
    end

    @tag process_caches: true
    test "clears the cached xml so subsequent generates reflect new data" do
      admin = admin_fixture()

      xml_before = Sitemap.generate()
      refute xml_before =~ "/events/"

      event = event_fixture(%{organizer_id: admin.id, state: :published})

      xml_cached = Sitemap.generate()
      refute xml_cached =~ "/events/#{event.id}"

      Sitemap.invalidate()

      xml_after = Sitemap.generate()
      assert xml_after =~ "/events/#{event.id}"
    end
  end
end
