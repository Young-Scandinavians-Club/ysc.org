defmodule YscWeb.AdminPostsQueryTest do
  @moduledoc """
  Query-count assertions for admin posts author-filter caching.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel admin LiveView tests in the main suite module.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp post_fixture(author, attrs) do
    {:ok, post} =
      %Ysc.Posts.Post{}
      |> Ysc.Posts.Post.new_post_changeset(
        Enum.into(attrs, %{
          user_id: author.id,
          title: "Test Post",
          url_name: "test-post-#{System.unique_integer()}",
          state: :published
        })
      )
      |> Ysc.Repo.insert()

    post
  end

  describe "author filter query caching" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "does not re-query post authors on each search patch", %{
      conn: conn,
      admin: admin
    } do
      post_fixture(admin, %{title: "Author Cache Headline"})

      {:ok, view, _} = live(conn, ~p"/admin/posts")

      # Drain connected mount work before measuring search patch queries.
      render(view)

      author_filter_pattern = ~r/DISTINCT ON \(.*"user_id"\).*FROM "posts"/is

      {_patch, author_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> form("#posts-search-form", q: "Author Cache")
            |> render_change()
          end,
          pattern: author_filter_pattern,
          caller_pids: [view.pid]
        )

      assert author_queries == 0
    end
  end
end
