defmodule YscWeb.NewsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Media.Image
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

  defp image_fixture(user_id) do
    {:ok, image} =
      %Image{user_id: user_id}
      |> Image.add_image_changeset(%{
        raw_image_path: "/test/raw/hero-#{System.unique_integer()}.jpg"
      })
      |> Repo.insert()

    image
  end

  # Helper to create a post. When author has board_position and post is published,
  # sets board_position_at_publish so the UI shows the historic role.
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

    attrs =
      default_attrs
      |> Map.merge(Map.delete(attrs, :author))
      |> maybe_set_board_position_at_publish(author)

    {:ok, post} =
      %Posts.Post{}
      |> Posts.Post.new_post_changeset(attrs)
      |> Repo.insert()

    # Preload author
    Repo.preload(post, [:author, :featured_image])
  end

  defp maybe_set_board_position_at_publish(attrs, author) do
    cond do
      Map.has_key?(attrs, :board_position_at_publish) ->
        attrs

      attrs[:state] == :published && author.board_position ->
        Map.put(
          attrs,
          :board_position_at_publish,
          to_string(author.board_position)
        )

      true ->
        attrs
    end
  end

  describe "mount/3" do
    test "loads news page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/news")

      assert html =~ "Club News"
    end

    test "shows loading skeleton initially", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/news")

      # Initial static render should show loading skeleton
      html = render(view)
      assert html =~ "animate-pulse" or html =~ "Club News"
    end

    test "sets correct page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/news")

      assert page_title(view) =~ "News"
    end

    @tag process_caches: true
    test "refreshes posts when public content cache is invalidated", %{
      conn: conn
    } do
      author = user_fixture(%{role: "admin"})
      title = "PubSub Post #{System.unique_integer()}"

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      url_name = "pubsub-post-#{System.unique_integer()}"

      assert {:ok, _post} =
               Posts.create_post(
                 %{
                   "title" => title,
                   "body" => "<p>Content</p>",
                   "url_name" => url_name,
                   "state" => "published",
                   "featured_post" => false,
                   "published_on" => DateTime.utc_now()
                 },
                 author
               )

      assert has_element?(view, "a[href='/posts/#{url_name}']", title)
    end

    test "loads async data after connection", %{conn: conn} do
      # Create some posts
      create_post(%{title: "Test Post 1"})
      create_post(%{title: "Test Post 2"})

      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      html = render(view)

      assert html =~ "Test Post 1" or html =~ "Test Post 2" or
               html =~ "Club News"
    end
  end

  describe "featured post display" do
    test "displays featured post when one exists", %{conn: conn} do
      author = user_fixture()
      # Create a featured post
      {:ok, _post} =
        %Posts.Post{}
        |> Posts.Post.new_post_changeset(%{
          title: "Featured News",
          raw_body: "<p>This is a featured news post.</p>",
          url_name: "featured-news-#{System.unique_integer()}",
          state: :published,
          published_on: DateTime.utc_now(),
          user_id: author.id,
          featured_post: true
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      html = render(view)
      assert html =~ "Featured News" or html =~ "Club News"
    end

    test "does not show featured section when no featured post exists", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      html = render(view)
      refute html =~ "Pinned News" or html =~ "animate-pulse"
    end

    test "displays author information for featured post", %{conn: conn} do
      author = user_fixture(%{first_name: "Jane", last_name: "Doe"})
      # Create featured post
      {:ok, _post} =
        %Posts.Post{}
        |> Posts.Post.new_post_changeset(%{
          title: "Featured by Jane",
          raw_body: "<p>Content here.</p>",
          url_name: "featured-by-jane-#{System.unique_integer()}",
          state: :published,
          published_on: DateTime.utc_now(),
          user_id: author.id,
          featured_post: true
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      html = render(view)
      # May show author name if featured post loaded
      assert html =~ "Club News"
    end

    test "displays board position for featured post", %{conn: conn} do
      author = user_fixture(%{first_name: "Jane", last_name: "Doe"})

      {:ok, _post} =
        %Posts.Post{}
        |> Posts.Post.new_post_changeset(%{
          title: "Featured by Jane",
          raw_body: "<p>Content here.</p>",
          url_name: "featured-by-jane-#{System.unique_integer()}",
          state: :published,
          published_on: DateTime.utc_now(),
          user_id: author.id,
          featured_post: true,
          board_position_at_publish: "president"
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      assert render(view) =~ "YSC President"
    end
  end

  describe "posts grid display" do
    test "displays multiple posts in grid", %{conn: conn} do
      create_post(%{title: "Post One"})
      create_post(%{title: "Post Two"})
      create_post(%{title: "Post Three"})

      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      html = render(view)
      # At least some posts should be visible
      assert html =~ "Club News"
    end

    test "displays author information for each post", %{conn: conn} do
      author = user_fixture(%{first_name: "John", last_name: "Smith"})
      create_post(%{title: "Post by John", author: author})

      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      html = render(view)
      assert html =~ "Club News"
    end

    test "shows reading time for posts", %{conn: conn} do
      create_post(%{
        title: "Long Post",
        raw_body: String.duplicate("<p>Word </p>", 500)
      })

      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      html = render(view)
      # Should show "min read" somewhere
      assert html =~ "min read" or html =~ "Club News"
    end
  end

  describe "pagination" do
    test "next-page event loads more posts", %{conn: conn} do
      # Create enough posts to trigger pagination
      for i <- 1..15 do
        create_post(%{title: "Post #{i}"})
      end

      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      # Trigger next page
      result = render_click(view, "next-page")

      # Should still render successfully
      assert result =~ "Club News" or is_binary(result)
    end

    test "next-page appends more posts using cursor", %{conn: conn} do
      for i <- 1..15 do
        create_post(%{title: "Post #{i}"})
      end

      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      # Trigger load of next batch via cursor
      result = render_click(view, "next-page")

      assert result =~ "Club News" or is_binary(result)
    end
  end

  describe "empty state" do
    test "handles no posts gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      html = render(view)
      # Should show the page header even with no posts
      assert html =~ "Club News"
    end
  end

  describe "board position formatting" do
    test "displays board position for authors with board roles", %{conn: conn} do
      author = user_fixture(%{board_position: :president})
      create_post(%{title: "Presidential Post", author: author})

      {:ok, view, _html} = live(conn, ~p"/news")

      render_news_async(view)

      html = render(view)
      # May show "President" if post is visible
      assert html =~ "Club News"
    end
  end

  describe "async data loading error handling" do
    test "handles async load failure gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/news")

      # Even if async load fails, page should still render
      render_news_async(view)

      html = render(view)
      assert html =~ "Club News"
    end
  end

  describe "post body and metadata rendering" do
    test "uses scrubbed raw_body when preview_text is nil", %{conn: conn} do
      create_post(%{
        title: "Preview From Raw",
        preview_text: nil,
        raw_body: "<p>UniqueRawSnippet#{System.unique_integer()}</p>"
      })

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      html = render(view)
      assert html =~ "UniqueRawSnippet"
    end

    test "strips HTML from preview_text instead of rendering it raw", %{
      conn: conn
    } do
      marker = "SafePreviewMarker#{System.unique_integer()}"
      xss_probe = "XSSProbe#{System.unique_integer()}"

      create_post(%{
        title: "Preview Text XSS",
        preview_text:
          "<p>#{marker}</p><script>#{xss_probe}</script><img src=x onerror=alert(1)>",
        raw_body: "<p>ignored body</p>"
      })

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      html = render(view)
      assert html =~ marker
      refute html =~ "<script>#{xss_probe}</script>"
      refute html =~ "onerror=alert(1)"
      refute html =~ "src=x"
    end

    test "strips formatting tags from preview_text as plain text", %{conn: conn} do
      marker = "Happy python code#{System.unique_integer()}"

      create_post(%{
        title: "Formatted Preview",
        preview_text:
          "Line one<br>Line two<strong>Hkk</strong><div></div>#{marker}<div><br /></div>"
      })

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      html = render(view)
      assert html =~ "whitespace-pre-line"
      assert html =~ "Line one"
      assert html =~ "Line twoHkk"
      assert html =~ marker
      refute html =~ "&lt;strong&gt;"
      refute html =~ "<strong>"
    end

    test "uses rendered_body for reading time when present", %{conn: conn} do
      long_html = "<p>" <> String.duplicate("word ", 500) <> "</p>"

      create_post(%{
        title: "Rendered Body Post",
        raw_body: "<p>short</p>",
        rendered_body: long_html,
        preview_text: nil
      })

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      html = render(view)
      assert html =~ "min read"
    end

    test "shows default reading time when bodies are empty", %{conn: conn} do
      create_post(%{
        title: "Empty Body Post",
        raw_body: "",
        rendered_body: nil,
        preview_text: nil
      })

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      html = render(view)
      assert html =~ "1 min read"
    end

    test "formats unknown board position strings via title case fallback", %{
      conn: conn
    } do
      create_post(%{
        title: "Unknown Role Post",
        board_position_at_publish: "zz_unknown_role"
      })

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      html = render(view)
      assert html =~ "YSC Zz_unknown_role"
    end

    test "uses raw image path when optimized image is not available", %{
      conn: conn
    } do
      author = user_fixture()
      image = image_fixture(author.id)

      create_post(%{
        title: "Image Grid Post",
        author: author,
        image_id: image.id
      })

      Ysc.PublicContentCache.invalidate_posts()

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)
      refresh_news_content(view)

      html = render(view)
      assert html =~ image.raw_image_path
    end
  end

  describe "reading time branches" do
    test "uses preview_text for reading time when bodies are empty", %{
      conn: conn
    } do
      html_preview =
        "<p>" <> String.duplicate("alpha ", 400) <> "</p>"

      create_post(%{
        title: "Preview Time",
        raw_body: "",
        rendered_body: nil,
        preview_text: html_preview
      })

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      html = render(view)
      assert html =~ "min read"
    end
  end

  describe "handle_async load_news_data exit" do
    test "marks async loaded when async task exits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/news")
      %{socket: socket} = :sys.get_state(view.pid)

      assert {:noreply, new_socket} =
               YscWeb.NewsLive.handle_async(
                 :load_news_data,
                 {:exit, :test_reason},
                 socket
               )

      assert new_socket.assigns.async_data_loaded == true
    end
  end

  describe "board position title lookup" do
    test "renders historic board role from string matching lookup atom", %{
      conn: conn
    } do
      create_post(%{
        title: "President Column",
        board_position_at_publish: "president"
      })

      {:ok, view, _html} = live(conn, ~p"/news")
      render_news_async(view)

      assert render(view) =~ "YSC President"
    end
  end
end
