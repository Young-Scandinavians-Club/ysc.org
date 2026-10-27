defmodule YscWeb.Feeds.AtomFeedTest do
  use ExUnit.Case, async: true

  alias Ysc.Posts.Post
  alias YscWeb.Feeds.AtomFeed

  describe "posts_feed/1" do
    test "summary strips HTML from preview_text" do
      marker = "plain summary#{System.unique_integer()}"

      post = %Post{
        id: Ecto.ULID.generate(),
        url_name: "html-preview",
        title: "HTML Preview Post",
        preview_text: "<p>#{marker}</p><strong>bold</strong>",
        raw_body: "<p>ignored body</p>",
        rendered_body: "<p>Rendered</p>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_on: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      xml = AtomFeed.posts_feed([post])

      assert xml =~ marker
      assert xml =~ "bold"
      refute xml =~ "<strong>"
      refute xml =~ "<p>#{marker}</p>"
    end

    test "summary preserves line breaks from br and block elements" do
      post = %Post{
        id: Ecto.ULID.generate(),
        url_name: "multiline-preview",
        title: "Multiline Preview Post",
        preview_text: "Line one<br>Line two<p>Line three</p>",
        raw_body: nil,
        rendered_body: "<p>Rendered</p>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_on: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      xml = AtomFeed.posts_feed([post])

      assert xml =~ "Line one"
      assert xml =~ "Line two"
      assert xml =~ "Line three"
      refute xml =~ "<br>"
    end

    test "summary falls back to raw_body when preview_text is absent" do
      marker = "from raw body#{System.unique_integer()}"

      post = %Post{
        id: Ecto.ULID.generate(),
        url_name: "raw-body-preview",
        title: "Raw Body Post",
        preview_text: nil,
        raw_body: "<p>#{marker}</p>",
        rendered_body: "<p>#{marker}</p>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_on: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      xml = AtomFeed.posts_feed([post])

      assert xml =~ marker
      refute xml =~ "<p>#{marker}</p>"
    end

    test "escapes entity-like sequences in titles so they stay inert after XML parse" do
      post = %Post{
        id: Ecto.ULID.generate(),
        url_name: "entity-title",
        title: "&lt;script&gt;alert(1)&lt;/script&gt;",
        preview_text: "ok",
        raw_body: nil,
        rendered_body: "<p>Rendered</p>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_on: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      xml = AtomFeed.posts_feed([post])

      assert xml =~ "&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;"
      refute xml =~ "<title>&lt;script&gt;"
    end

    test "escapes HTML content so nested entity sequences cannot become markup" do
      marker = "feed-html#{System.unique_integer()}"

      post = %Post{
        id: Ecto.ULID.generate(),
        url_name: "html-content",
        title: "HTML Content Post",
        preview_text: "preview",
        raw_body: nil,
        rendered_body: "<p>#{marker} &lt;img src=x onerror=alert(1)&gt;</p>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_on: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      xml = AtomFeed.posts_feed([post])

      assert xml =~ marker
      assert xml =~ "&amp;lt;img"
      refute xml =~ ~s|<content type="html"><p>|
    end

    test "omits summary when post has no preview or body text" do
      post = %Post{
        id: Ecto.ULID.generate(),
        url_name: "empty-preview",
        title: "Empty Preview Post",
        preview_text: "   ",
        raw_body: nil,
        rendered_body: "<p>Rendered only</p>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_on: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      xml = AtomFeed.posts_feed([post])

      assert xml =~ "Empty Preview Post"
      refute xml =~ "<summary"
    end

    test "scrubs script tags from rendered_body before emitting HTML content" do
      marker = "post-atom-safe-#{System.unique_integer()}"

      post = %Post{
        id: Ecto.ULID.generate(),
        url_name: "post-xss-body",
        title: "Feed XSS Post",
        preview_text: "preview",
        raw_body: nil,
        rendered_body:
          "<p>#{marker}</p><script>document.cookie</script><img src=x onerror=alert(1)>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_on: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      xml = AtomFeed.posts_feed([post])

      assert xml =~ marker
      # Atomex entity-encodes HTML content; feed readers decode then render.
      refute xml =~ "&lt;script"
      refute xml =~ "onerror="
    end

    test "omits HTML content when leftover markup scrubs to empty" do
      post = %Post{
        id: Ecto.ULID.generate(),
        url_name: "post-scrub-empty",
        title: "Feed Empty Scrub Post",
        preview_text: "preview",
        raw_body: nil,
        # Empty disallowed tags scrub to "" (script inner text would remain).
        rendered_body: "<script></script><iframe></iframe><svg></svg>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_on: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      xml = AtomFeed.posts_feed([post])

      assert xml =~ "Feed Empty Scrub Post"
      refute xml =~ "<content"
    end
  end

  describe "events_feed/1" do
    test "includes plain-text event description in summary" do
      marker = "event blurb#{System.unique_integer()}"

      event = %{
        id: Ecto.ULID.generate(),
        title: "Feed Event",
        description: "#{marker} with <em>formatting</em>",
        rendered_details: "<p>Details HTML</p>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_at: DateTime.utc_now() |> DateTime.truncate(:second),
        start_date: DateTime.add(DateTime.utc_now(), 7, :day)
      }

      xml = AtomFeed.events_feed([event])

      assert xml =~ marker
      assert xml =~ "formatting"
      refute xml =~ "<em>"
    end

    test "scrubs script tags from rendered_details before emitting HTML content" do
      marker = "atom-safe-#{System.unique_integer()}"

      event = %{
        id: Ecto.ULID.generate(),
        title: "Feed XSS Event",
        description: "Blurb",
        rendered_details:
          "<p>#{marker}</p><script>document.cookie</script><img src=x onerror=alert(1)>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_at: DateTime.utc_now() |> DateTime.truncate(:second),
        start_date: DateTime.add(DateTime.utc_now(), 7, :day)
      }

      xml = AtomFeed.events_feed([event])

      assert xml =~ marker
      # Atomex entity-encodes HTML content; feed readers decode then render.
      refute xml =~ "&lt;script"
      refute xml =~ "onerror="
    end

    test "omits HTML content when leftover markup scrubs to empty" do
      event = %{
        id: Ecto.ULID.generate(),
        title: "Feed Empty Scrub Event",
        description: "Blurb",
        # Empty disallowed tags scrub to "" (script inner text would remain).
        rendered_details: "<script></script><iframe></iframe><svg></svg>",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
        published_at: DateTime.utc_now() |> DateTime.truncate(:second),
        start_date: DateTime.add(DateTime.utc_now(), 7, :day)
      }

      xml = AtomFeed.events_feed([event])

      assert xml =~ "Feed Empty Scrub Event"
      refute xml =~ "<content"
    end
  end
end
