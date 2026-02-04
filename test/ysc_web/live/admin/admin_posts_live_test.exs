defmodule YscWeb.AdminPostsLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

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

  describe "Admin Posts" do
    setup [:create_admin]

    test "lists posts", %{conn: conn, admin: admin} do
      post_fixture(admin, %{title: "Viking News"})

      {:ok, _view, html} = live(conn, ~p"/admin/posts")
      assert html =~ "Posts"
      assert html =~ "Viking News"
    end

    test "navigates to new post modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts")

      view
      |> element("button", "New Post")
      |> render_click()

      assert_redirected(view, ~p"/admin/posts/new")
    end

    test "creates a new post", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      view
      |> form("#new-post-modal form", %{new_post: %{title: "Brand New Post"}})
      |> render_submit()

      # Should redirect to the post editor
      # Since we don't know the ID exactly, we can check for a redirect and then verify if it's the right path pattern
      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"/admin/posts/.*"
    end
  end
end
