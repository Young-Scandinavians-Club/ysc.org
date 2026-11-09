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
    {rendered_body, attrs} = Map.pop(attrs, :rendered_body)

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

    if is_binary(rendered_body) do
      post
      |> Ecto.Changeset.change(%{rendered_body: rendered_body})
      |> Repo.update!()
    else
      post
    end
  end

  @post_query_pattern ~r/FROM "posts"/i
  @raw_body_pattern ~r/raw_body/i
  @secret_pattern ~r/hashed_password|board_bio|upload_data/i

  describe "mount query deduplication" do
    test "dead render and connect avoid duplicate post fetches", %{conn: conn} do
      author = user_fixture()
      post = post_fixture(author, %{title: "Deduped Post Fetch XYZ"})

      {{:ok, view, _html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/posts/#{post.id}")
            Ysc.QueryCounter.track_caller_pid(view.pid)
            render_async(view)
            {:ok, view, html}
          end,
          pattern: @post_query_pattern,
          caller_pids: [self()]
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
          pattern: @post_query_pattern,
          caller_pids: [self()]
        )

      assert query_count == 1
    end
  end

  describe "public page TOAST and preloads" do
    test "dead render does not SELECT raw_body and still shows rendered body",
         %{
           conn: conn
         } do
      marker = "toast-#{System.unique_integer([:positive])}"
      author = user_fixture()

      post =
        post_fixture(author, %{
          title: "Public Body Toast Post",
          raw_body: "<p>raw #{marker}</p>",
          rendered_body: "<p>rendered #{marker}</p>"
        })

      {html, raw_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/posts/#{post.id}")
            |> html_response(200)
          end,
          pattern: @raw_body_pattern,
          caller_pids: [self()]
        )

      # Before: get_public_post selected posts.* including Trix source.
      # After: public page fields omit raw_body; the article uses
      # rendered_body.
      assert raw_cols == 0
      assert html =~ "rendered #{marker}"
      refute html =~ "raw #{marker}"
    end

    test "dead render author preload skips hashed_password", %{conn: conn} do
      author = user_fixture()
      post = post_fixture(author, %{title: "Slim Author Post"})

      {_html, fat_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/posts/#{post.id}")
            |> html_response(200)
          end,
          pattern: @secret_pattern,
          caller_pids: [self()]
        )

      assert fat_cols == 0
    end
  end

  describe "comment loading" do
    test "guest connect does not query comments", %{conn: conn} do
      author = user_fixture()
      post = post_fixture(author, %{title: "Guest Comment Skip"})

      Posts.add_comment_to_post(
        %{"post_id" => post.id, "text" => "Hidden from guests"},
        author
      )

      {_result, comment_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")
            render_async(view)
          end,
          pattern: ~r/FROM "comments"/i
        )

      assert comment_cols == 0
    end

    test "signed-in connect still shows comment author and body", %{
      conn: conn
    } do
      author = user_fixture(%{first_name: "Commenter", last_name: "Member"})
      post = post_fixture(author, %{title: "Member Comments"})
      marker = "visible-#{System.unique_integer([:positive])}"

      Posts.add_comment_to_post(
        %{"post_id" => post.id, "text" => "Hello #{marker}"},
        author
      )

      conn = log_in_user(conn, author)

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")
      render_async(view)
      html = render(view)

      assert html =~ "Hello #{marker}"
      assert html =~ "Commenter"
      assert has_element?(view, "#primary-post-comment")
    end
  end
end
