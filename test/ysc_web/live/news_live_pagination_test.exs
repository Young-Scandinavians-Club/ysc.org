defmodule YscWeb.NewsLivePaginationTest do
  @moduledoc """
  Pagination edge cases for NewsLive.

  Runs with `async: false` so shared Cachex state and PubSub cache reloads from
  parallel suites cannot reset timeline pagination mid-assertion.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Posts
  alias Ysc.Repo

  @async_timeout_ms 2_000

  setup do
    Ysc.DataCase.invalidate_shared_caches()
    :ok
  end

  defp render_news_async(view) do
    render_async(view, @async_timeout_ms)
  end

  defp refresh_news_content(view) do
    Ysc.PublicContentCache.invalidate_posts()
    render(view)
  end

  defp create_post(attrs) do
    author = attrs[:author] || user_fixture()

    default_attrs = %{
      title: "Test Post #{System.unique_integer()}",
      raw_body:
        "<p>This is a test post with some content that should be long enough to calculate reading time properly.</p>",
      url_name: "test-post-#{System.unique_integer()}",
      state: :published,
      published_on: DateTime.utc_now(),
      user_id: author.id
    }

    attrs = Map.merge(default_attrs, Map.delete(attrs, :author))

    {:ok, post} =
      %Posts.Post{}
      |> Posts.Post.new_post_changeset(attrs)
      |> Repo.insert()

    Repo.preload(post, [:author, :featured_image])
  end

  describe "pagination edge cases" do
    test "next-page when no older posts marks end of timeline", %{conn: conn} do
      base = DateTime.add(DateTime.utc_now(), -3600, :second)

      for i <- 0..9 do
        create_post(%{
          title: "Pag Post #{i}",
          url_name: "pag-post-#{i}-#{System.unique_integer()}",
          published_on: DateTime.add(base, i, :second)
        })
      end

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      render_click(view, "next-page")

      html = render(view)
      assert html =~ "Club News"
    end

    @tag process_caches: true
    test "next-page when cursor is exhausted returns empty batch", %{conn: conn} do
      # Publish in a far-future window with hour spacing so no other test posts can
      # land between our pages when using published_on cursor pagination.
      base =
        DateTime.utc_now()
        |> DateTime.add(10_000, :day)
        |> DateTime.truncate(:second)

      unique = System.unique_integer()
      url_prefix = "tl-end-#{unique}"

      for i <- 1..11 do
        create_post(%{
          title: "Timeline End #{i}",
          url_name: "#{url_prefix}-#{i}",
          published_on: DateTime.add(base, -i, :hour)
        })
      end

      # Sandbox-isolated DB check (Cachex is shared across async tests).
      assert Enum.count(
               Posts.list_posts(100),
               &String.starts_with?(&1.url_name, url_prefix)
             ) ==
               11

      page1 =
        Posts.list_posts(10)
        |> Enum.filter(&String.starts_with?(&1.url_name, url_prefix))

      assert length(page1) == 10

      cursor = List.last(page1).published_on

      page2 =
        Posts.list_posts(cursor, 10)
        |> Enum.filter(&String.starts_with?(&1.url_name, url_prefix))

      assert length(page2) == 1
      assert hd(page2).url_name == "#{url_prefix}-11"

      # create_post uses Repo.insert and does not invalidate the public posts cache.
      # Clear shared Cachex state and invalidate immediately before mount so parallel
      # suites cannot serve stale post lists to this LiveView.
      Cachex.clear(:ysc_cache)
      Ysc.PublicContentCache.invalidate_posts()

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)
      refresh_news_content(view)

      html = render(view)
      assert html =~ "#{url_prefix}-1"
      assert html =~ "#{url_prefix}-10"
      refute html =~ "#{url_prefix}-11"

      assert has_element?(view, "#news-grid[phx-viewport-bottom=\"next-page\"]")

      html = render_click(view, "next-page")
      assert html =~ "#{url_prefix}-11"
      refute html =~ ~s(phx-viewport-bottom="next-page")

      html = render_click(view, "next-page")
      assert html =~ "Club News"
      assert html =~ "#{url_prefix}-11"
      refute html =~ ~s(phx-viewport-bottom="next-page")
    end
  end
end
