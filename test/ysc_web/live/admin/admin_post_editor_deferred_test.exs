defmodule YscWeb.AdminPostEditorDeferredTest do
  @moduledoc """
  Query-count assertions for admin post editor deferred loading.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Posts.Post
  alias Ysc.Repo

  setup %{conn: conn} do
    admin = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp post_fixture(author, attrs) do
    {:ok, post} =
      %Post{}
      |> Post.new_post_changeset(
        Map.merge(
          %{
            user_id: author.id,
            title: "Deferred Load Post",
            url_name: "deferred-load-#{System.unique_integer()}",
            state: :draft
          },
          attrs
        )
      )
      |> Repo.insert()

    post
  end

  test "dead render skips post queries and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    post = post_fixture(admin, %{raw_body: "<div>Reload body content</div>"})

    posts_pattern = ~r/FROM "posts"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get(~p"/admin/posts/#{post.id}")
          |> html_response(200)
        end,
        pattern: posts_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ "Loading post"
    refute html =~ "Deferred Load Post"
    refute html =~ "trix-editor-form"
    refute html =~ "Reload body content"
  end

  test "connected mount loads post editor with body content", %{
    conn: conn,
    admin: admin
  } do
    post = post_fixture(admin, %{raw_body: "<div>Reload body content</div>"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}")

    assert render(view) =~ "Deferred Load Post"
    assert has_element?(view, "#edit_post_form")
    assert has_element?(view, "#trix-editor-form")

    assert has_element?(
             view,
             "#post\\[raw_body\\][value='<div>Reload body content</div>']"
           )
  end
end
