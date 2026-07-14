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
        Enum.into(attrs, %{
          user_id: author.id,
          title: "Deferred Load Post",
          url_name: "deferred-load-#{System.unique_integer()}",
          state: :draft
        })
      )
      |> Repo.insert()

    post
  end

  test "dead render skips post queries and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    post = post_fixture(admin, %{})

    posts_pattern = ~r/FROM "posts"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get(~p"/admin/posts/#{post.id}")
          |> html_response(200)
        end,
        pattern: posts_pattern
      )

    assert query_count == 0
    assert html =~ "Loading post"
    refute html =~ "Deferred Load Post"
  end

  test "connected mount loads post editor", %{conn: conn, admin: admin} do
    post = post_fixture(admin, %{})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}")

    assert render(view) =~ "Deferred Load Post"
    assert has_element?(view, "#edit_post_form")
  end
end
