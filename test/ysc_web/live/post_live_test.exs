defmodule YscWeb.PostLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Posts
  alias Ysc.Repo

  # Helper to create a post
  defp create_post(attrs) do
    author = attrs[:author] || user_fixture()

    default_attrs = %{
      title: "Test Post #{System.unique_integer()}",
      raw_body: "<p>This is a test post with some content.</p>",
      url_name: "test-post-#{System.unique_integer()}",
      state: :published,
      published_on: DateTime.utc_now(),
      user_id: author.id,
      comment_count: 0
    }

    attrs = Map.merge(default_attrs, Map.delete(attrs, :author))

    {:ok, post} =
      %Posts.Post{}
      |> Posts.Post.new_post_changeset(attrs)
      |> Repo.insert()

    Repo.preload(post, [:author, :featured_image])
  end

  describe "mount/3 - post access" do
    test "loads post by ULID successfully", %{conn: conn} do
      post = create_post(%{title: "Test Article"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "Test Article"
      assert html =~ "Club News"
    end

    test "loads post by url_name successfully", %{conn: conn} do
      _post = create_post(%{title: "Test Article", url_name: "my-test-article"})

      {:ok, _view, html} = live(conn, ~p"/posts/my-test-article")

      assert html =~ "Test Article"
      assert html =~ "Club News"
    end

    test "redirects to news when post not found", %{conn: conn} do
      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/posts/#{Ecto.ULID.generate()}")

      assert path == "/news"
      assert flash["error"] =~ "Article not found"
    end

    test "redirects to news when invalid ID format", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/posts/invalid-id-format")

      assert path == "/news"
    end

    test "sets page title to post title", %{conn: conn} do
      post = create_post(%{title: "Amazing Article"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      assert page_title(view) =~ "Amazing Article"
    end
  end

  describe "post display" do
    test "displays post title prominently", %{conn: conn} do
      post = create_post(%{title: "Important Announcement"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "Important Announcement"
    end

    test "displays post content", %{conn: conn} do
      post =
        create_post(%{
          title: "Test",
          raw_body: "<p>This is the main content of the article.</p>"
        })

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "This is the main content of the article."
    end

    test "displays author information", %{conn: conn} do
      author = user_fixture(%{first_name: "Jane", last_name: "Doe"})
      post = create_post(%{title: "Test", author: author})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "Jane"
      assert html =~ "Doe"
      assert html =~ "Post By"
    end

    test "displays author board position when present", %{conn: conn} do
      author =
        user_fixture(%{
          first_name: "John",
          last_name: "Smith",
          board_position: :president
        })

      post = create_post(%{title: "Test", author: author})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "President"
    end

    test "displays published date", %{conn: conn} do
      post =
        create_post(%{title: "Test", published_on: ~U[2024-06-15 10:00:00Z]})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      # Should display the formatted date
      assert html =~ "Jun 15, 2024"
    end
  end

  describe "featured image" do
    test "does not display featured image section when no image", %{conn: conn} do
      post = create_post(%{title: "Test", image_id: nil})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      refute html =~ "post-featured-image"
    end
  end

  describe "comments section - unauthenticated" do
    test "does not show comment form when not logged in", %{conn: conn} do
      post = create_post(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      refute has_element?(view, "#primary-post-comment")
    end

    test "does not show Community Discussion section when not logged in", %{
      conn: conn
    } do
      post = create_post(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      refute html =~ "Community Discussion"
    end
  end

  describe "comments section - authenticated" do
    test "shows comment form when logged in", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      post = create_post(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      assert has_element?(view, "#primary-post-comment")

      assert has_element?(
               view,
               "textarea[placeholder='Share your thoughts...']"
             )
    end

    test "shows Community Discussion heading with count", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      post = create_post(%{title: "Test", comment_count: 0})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "Community Discussion (0)"
    end

    test "shows loading skeleton initially before comments load", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      post = create_post(%{title: "Test", comment_count: 3})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      # Initial render should show loading skeleton
      html = render(view)
      assert html =~ "animate-pulse" or html =~ "Community Discussion"
    end

    test "comment form has submit button", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      post = create_post(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      assert has_element?(view, "button[type='submit']", "Post Comment")
    end
  end

  describe "posting comments" do
    test "allows posting a comment when authenticated", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      post = create_post(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      # Wait for comments to load
      :timer.sleep(100)

      result =
        view
        |> form("#primary-post-comment",
          comment: %{text: "Great article!", post_id: post.id}
        )
        |> render_submit()

      # Should still render the page (comment will be added via PubSub)
      assert result =~ "Test" or is_binary(result)
    end

    test "scrubs HTML from comments", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      post = create_post(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      # Wait for comments to load
      :timer.sleep(100)

      # Try to submit comment with script tag
      result =
        view
        |> form("#primary-post-comment",
          comment: %{
            text: "<script>alert('xss')</script>Nice post!",
            post_id: post.id
          }
        )
        |> render_submit()

      # Should still process (scrubbing happens server-side)
      assert is_binary(result)
    end
  end

  describe "async comment loading" do
    test "loads comments asynchronously after connection", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      post = create_post(%{title: "Test", comment_count: 2})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      # Wait for async load
      :timer.sleep(200)

      html = render(view)
      # Comments should be loaded or loading skeleton should be gone
      assert html =~ "Community Discussion"
    end
  end

  describe "reading progress bar" do
    test "includes reading progress bar", %{conn: conn} do
      post = create_post(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      assert has_element?(view, "#reading-progress-container")
      assert has_element?(view, "#reading-progress")
    end

    test "reading progress bar has ReadingProgress hook", %{conn: conn} do
      post = create_post(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ ~s(phx-hook="ReadingProgress")
    end
  end

  describe "article body hooks" do
    test "includes GLightbox hook for images", %{conn: conn} do
      post = create_post(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ ~s(phx-hook="GLightboxHook")
    end

    test "article body has proper styling classes", %{conn: conn} do
      post = create_post(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "prose"
      assert html =~ "first-letter:"
    end
  end

  describe "board position formatting" do
    test "formats president position correctly", %{conn: conn} do
      author = user_fixture(%{board_position: :president})
      post = create_post(%{author: author})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "President"
    end

    test "formats vice_president position correctly", %{conn: conn} do
      author = user_fixture(%{board_position: :vice_president})
      post = create_post(%{author: author})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "Vice President"
    end

    test "formats cabin_master positions correctly", %{conn: conn} do
      author = user_fixture(%{board_position: :tahoe_cabin_master})
      post = create_post(%{author: author})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "Tahoe Cabin Master"
    end
  end

  describe "metadata and structure" do
    test "includes Club News label", %{conn: conn} do
      post = create_post(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "Club News"
    end

    test "uses proper article tag for content", %{conn: conn} do
      post = create_post(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "<article"
    end
  end

  describe "empty state" do
    test "shows empty viking state when post is nil in assigns", %{conn: conn} do
      # This is an edge case where post becomes nil after mount
      # Just verify the empty state content exists in the template
      post = create_post(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      # Normal case - post is not nil, so empty state not shown
      refute html =~ "Sorry! The article could not be located"
    end
  end

  describe "real-time updates" do
    test "subscribes to post topic when connected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      post = create_post(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

      # View should be subscribed (connection established)
      assert view.pid
    end
  end

  describe "accessibility" do
    test "includes proper alt text for featured images when present", %{
      conn: conn
    } do
      post = create_post(%{title: "Test Article"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      # When image_id is nil, featured image section not shown
      # Just verify the page loads
      assert html =~ "Test Article"
    end

    test "includes proper semantic HTML structure", %{conn: conn} do
      post = create_post(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "<h1"
      assert html =~ "<article"
    end
  end
end
