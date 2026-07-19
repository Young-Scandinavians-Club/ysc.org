defmodule YscWeb.PostLiveQueryTest do
  @moduledoc """
  Query-count assertions for PostLive mount deduplication.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel LiveView tests.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  @moduletag process_caches: true

  alias Ysc.Posts
  alias Ysc.Repo

  defp post_fixture(author, attrs) do
    {:ok, post} =
      %Posts.Post{}
      |> Posts.Post.new_post_changeset(
        Map.merge(
          %{
            user_id: author.id,
            title: "Query Test Post #{System.unique_integer()}",
            url_name: "query-test-#{System.unique_integer()}",
            raw_body: "<p>Post body</p>",
            state: :published,
            published_on: DateTime.utc_now()
          },
          attrs
        )
      )
      |> Repo.insert()

    post
  end

  @post_query_pattern ~r/FROM "posts"/i

  describe "mount query deduplication" do
    test "dead render and connect avoid duplicate post fetches", %{conn: conn} do
      author = user_fixture()
      post = post_fixture(author, %{title: "Deduped Post Fetch XYZ"})

      {{:ok, view, _html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/posts/#{post.id}")
            render_async(view)
            {:ok, view, html}
          end,
          pattern: @post_query_pattern
        )

      assert query_count == 1
      assert render(view) =~ "Deduped Post Fetch XYZ"
    end

    test "dead render loads post once for SEO", %{conn: conn} do
      author = user_fixture()
      post = post_fixture(author, %{title: "Dead Render Post XYZ"})

      {_html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/posts/#{post.id}")
            |> html_response(200)
          end,
          pattern: @post_query_pattern
        )

      assert query_count == 1
    end
  end
end
