defmodule YscWeb.AdminPostEditorLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Posts
  alias Ysc.Repo

  setup :register_and_log_in_admin

  describe "mount" do
    test "loads post for editing", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test Post",
            "url_name" => "test-post-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Test content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Test Post"
      assert html =~ "Draft"
    end

    test "displays post title in form", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "My Article",
            "url_name" => "my-article-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "My Article"
    end

    test "initializes with draft state", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Draft Post",
            "url_name" => "draft-post-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Draft"
      assert html =~ "Publish"
    end
  end

  describe "post states" do
    test "displays publish button for draft posts", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Publish"
    end

    test "displays restore button for deleted posts", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Deleted Post",
            "url_name" => "deleted-#{System.unique_integer()}",
            "state" => "deleted",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Restore"
    end

    test "shows correct badge style for draft", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Draft"
    end

    test "shows correct badge style for published", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "published",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Published"
    end
  end

  describe "editor interface" do
    test "displays trix editor", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "trix-editor"
      assert html =~ "phx-hook=\"TrixHook\""
    end

    test "displays URL name field", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "my-custom-url",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "my-custom-url"
    end

    test "displays post link", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-article",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "/posts/test-article"
    end
  end

  describe "preview functionality" do
    test "displays preview button", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Preview"
    end

    test "can navigate to preview mode", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}")

      {:ok, _view, preview_html} =
        view
        |> element("a", "Preview")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/posts/#{post.id}/preview")

      # Preview modal should be shown
      assert preview_html =~ "hero-device-phone-mobile"
      assert preview_html =~ "hero-computer-desktop"
    end
  end

  describe "settings modal" do
    test "can navigate to settings", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}")

      {:ok, _view, settings_html} =
        view
        |> element("a", "Post Settings")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/posts/#{post.id}/settings")

      assert settings_html =~ "Post Settings"
      assert settings_html =~ "Featured Image"
    end

    test "displays featured image section in settings", %{
      conn: conn,
      user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}/settings")

      assert html =~ "Featured Image"
      assert html =~ "No featured image set"
    end
  end

  describe "post actions" do
    test "can delete post", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "To Delete",
            "url_name" => "to-delete-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}")

      view
      |> element("button", "Delete Post")
      |> render_click()

      assert_redirected(view, ~p"/admin/posts")

      # Verify post is deleted
      deleted_post = Repo.get(Posts.Post, post.id)
      assert deleted_post.state == :deleted
    end

    test "shows saving indicator", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Saving"
      assert html =~ "hero-arrow-path"
    end
  end

  describe "dropdown menu" do
    test "displays settings option", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Post Settings"
    end

    test "displays delete option", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Delete Post"
    end

    test "has ellipsis icon for dropdown", %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "url_name" => "test-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "hero-ellipsis-vertical"
    end
  end

  defp register_and_log_in_admin(%{conn: conn}) do
    user = user_fixture(%{role: :admin})
    %{conn: log_in_user(conn, user), user: user}
  end
end
