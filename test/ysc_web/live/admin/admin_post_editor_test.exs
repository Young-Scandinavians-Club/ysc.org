defmodule YscWeb.AdminPostEditorLiveTest do
  use YscWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Media.Image
  alias Ysc.Posts
  alias Ysc.Posts.Post
  alias Ysc.Repo
  alias YscWeb.Admin.EditingPresence

  setup :register_and_log_in_admin

  defp image_fixture(user_id) do
    {:ok, image} =
      %Image{user_id: user_id}
      |> Image.add_image_changeset(%{
        raw_image_path: "/test/raw/hero-#{System.unique_integer()}.jpg"
      })
      |> Repo.insert()

    image
  end

  defp post_count do
    Repo.aggregate(Post, :count, :id)
  end

  describe "new post" do
    test "opens editor without creating a database row", %{conn: conn} do
      count_before = post_count()

      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      assert has_element?(view, "#edit_post_form")
      assert has_element?(view, "trix-editor")
      assert has_element?(view, "span", "Draft")

      assert has_element?(
               view,
               "input[name='post[title]'][value='New Untitled Post']"
             )

      assert has_element?(
               view,
               "input[name='post[url_name]'][value='new-untitled-post']"
             )

      assert post_count() == count_before
    end

    test "updates url slug when title changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      view
      |> form("#edit_post_form", post: %{title: "My Great Post"})
      |> render_change()

      assert has_element?(
               view,
               "input[name='post[url_name]'][value='my-great-post']"
             )
    end

    test "restores default title when the title field is cleared", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      view
      |> form("#edit_post_form", post: %{title: ""})
      |> render_change()

      assert has_element?(
               view,
               "input[name='post[title]'][value='New Untitled Post']"
             )

      assert has_element?(
               view,
               "input[name='post[url_name]'][value='new-untitled-post']"
             )
    end

    test "persists new post when opening settings and patches editor URL", %{
      conn: conn
    } do
      count_before = post_count()

      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      view
      |> form("#edit_post_form", post: %{title: "Saved Later"})
      |> render_change()

      view
      |> element("#settings-post-new")
      |> render_click()

      assert post_count() == count_before + 1

      post = Repo.one!(from p in Post, where: p.title == "Saved Later")
      assert_patch(view, ~p"/admin/posts/#{post.id}/settings")
    end
  end

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

  describe "publish validation" do
    test "opens settings when publishing draft without featured image",
         %{
           conn: conn,
           user: user
         } do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "No Image Post",
            "url_name" => "no-image-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}")

      _html =
        view
        |> render_hook("publish-post", %{})

      assert_patch(view, ~p"/admin/posts/#{post.id}/settings")
      assert Posts.get_post!(post.id).state == :draft
    end

    test "publishes after featured image is selected from settings",
         %{conn: conn, user: user} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Publish After Image",
            "url_name" => "publish-after-image-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      image = image_fixture(user.id)

      {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}")

      view
      |> render_hook("publish-post", %{})

      assert_patch(view, ~p"/admin/posts/#{post.id}/settings")

      send(
        view.pid,
        {YscWeb.MediaPickerComponent, :post_featured_image, image.id}
      )

      _html = render(view)

      assert Posts.get_post!(post.id).state == :published
      assert Posts.get_post!(post.id).image_id == image.id
    end

    test "publishes immediately when featured image is already set",
         %{conn: conn, user: user} do
      image = image_fixture(user.id)

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Ready To Publish",
            "url_name" => "ready-publish-#{System.unique_integer()}",
            "state" => "draft",
            "image_id" => image.id,
            "body" => "Content"
          },
          user
        )

      {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}")

      view
      |> render_hook("publish-post", %{})

      assert_redirect(view, ~p"/admin/posts/#{post.id}")
      assert Posts.get_post!(post.id).state == :published
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

    test "phone preview button switches iframe layout on preview route", %{
      conn: conn,
      user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Preview devices",
            "url_name" => "preview-dev-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/preview")

      html =
        view
        |> element("button", "Phone preview")
        |> render_click()

      assert html =~ "phone_mockup" or html =~ "Phone preview"
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

      view
      |> element("#post-editor-preview-patch")
      |> render_click()

      assert_patch(view, ~p"/admin/posts/#{post.id}/preview")

      preview_html = render(view)

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
      assert html =~ "Choose from library"
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

  describe "editing presence" do
    defp presence_post_fixture(user) do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Presence Post",
            "url_name" => "presence-post-#{System.unique_integer()}",
            "state" => "draft",
            "body" => "Content"
          },
          user
        )

      post
    end

    test "shows an avatar for another admin currently editing the post", %{
      conn: conn,
      user: user
    } do
      post = presence_post_fixture(user)
      other_admin = user_fixture(%{role: :admin, first_name: "Jamie"})

      {:ok, _ref} =
        EditingPresence.track(
          %{id: "other-tab-#{System.unique_integer([:positive])}"},
          :post,
          post.id,
          other_admin
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Jamie"
      assert html =~ "is editing"
    end

    test "does not show the current admin's own presence", %{
      conn: conn,
      user: user
    } do
      post = presence_post_fixture(user)

      {:ok, _ref} =
        EditingPresence.track(
          %{id: "self-tab-#{System.unique_integer([:positive])}"},
          :post,
          post.id,
          user
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      refute html =~ "is editing"
    end

    test "shows no avatars when nobody else is editing", %{
      conn: conn,
      user: user
    } do
      post = presence_post_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      refute html =~ "is editing"
    end

    test "updates avatars live when another admin starts editing", %{
      conn: conn,
      user: user
    } do
      post = presence_post_fixture(user)

      {:ok, view, html} = live(conn, ~p"/admin/posts/#{post.id}")
      refute html =~ "is editing"

      other_admin = user_fixture(%{role: :admin, first_name: "Taylor"})

      {:ok, _ref} =
        EditingPresence.track(
          %{id: "live-tab-#{System.unique_integer([:positive])}"},
          :post,
          post.id,
          other_admin
        )

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: EditingPresence.topic(:post),
        event: "presence_diff",
        payload: %{}
      })

      html = render(view)
      assert html =~ "Taylor"
      assert html =~ "is editing"
    end
  end

  describe "last edited by" do
    test "shows who last edited the post", %{conn: conn, user: user} do
      editor = user_fixture(%{role: :admin, first_name: "Morgan"})
      post = presence_post_fixture(user)

      {:ok, _post} =
        Posts.update_post_editor(post, %{"title" => "Edited by Morgan"}, editor)

      {:ok, _view, html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert html =~ "Last edited by"
      assert html =~ "Morgan"
    end

    test "formats the timestamp in Pacific time, not UTC", %{
      conn: conn,
      user: user
    } do
      # 05:00 UTC on Mar 15 is still Mar 14 10:00pm PDT.
      edited_at = ~U[2024-03-15 05:00:00Z]
      post = presence_post_fixture(user)
      stamp_updated_at(Post, post.id, edited_at)

      {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}")

      assert has_element?(view, "p", pacific_last_edited_label(edited_at))
      refute has_element?(view, "p", utc_last_edited_label(edited_at))
    end
  end

  defp stamp_updated_at(schema, id, datetime) do
    {1, _} =
      Repo.update_all(from(r in schema, where: r.id == ^id),
        set: [updated_at: datetime]
      )

    :ok
  end

  defp pacific_last_edited_label(datetime) do
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Timex.format!("{Mshort} {D}, {YYYY} at {h12}:{m}{am}")
  end

  defp utc_last_edited_label(datetime) do
    Timex.format!(datetime, "{Mshort} {D}, {YYYY} at {h12}:{m}{am}")
  end

  defp register_and_log_in_admin(%{conn: conn}) do
    user = user_fixture(%{role: :admin})
    %{conn: log_in_user(conn, user), user: user}
  end
end
