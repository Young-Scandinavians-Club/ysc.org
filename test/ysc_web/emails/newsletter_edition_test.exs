defmodule YscWeb.Emails.NewsletterEditionTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias Ysc.Repo
  alias YscWeb.Emails.NewsletterEdition

  # ---------------------------------------------------------------------------
  # email_safe_html/1
  # ---------------------------------------------------------------------------

  describe "email_safe_html/1" do
    test "returns empty string for nil" do
      assert NewsletterEdition.email_safe_html(nil) == ""
    end

    test "returns empty string for blank string" do
      assert NewsletterEdition.email_safe_html("") == ""
      assert NewsletterEdition.email_safe_html("   ") == ""
    end

    test "passes through standard inline tags unchanged" do
      html = "<p>Hello <strong>world</strong> and <em>friends</em></p>"
      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "Hello"
      assert result =~ "<strong>world</strong>"
      assert result =~ "<em>friends</em>"
    end

    test "strips class attributes" do
      html = "<p class=\"text-bold\">Text</p>"
      result = NewsletterEdition.email_safe_html(html)

      refute result =~ "class="
      assert result =~ "Text"
    end

    test "strips data-trix-* attributes" do
      html = ~s(<span data-trix-serialize="value">Content</span>)
      result = NewsletterEdition.email_safe_html(html)

      refute result =~ "data-trix"
      assert result =~ "Content"
    end

    test "converts Trix figure with image to inline img" do
      html = """
      <figure>
        <a href="/uploads/photo.jpg">
          <img src="/uploads/photo.jpg" alt="A photo" />
        </a>
      </figure>
      """

      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "<img"
      assert result =~ ~s(src="/uploads/photo.jpg")
      assert result =~ ~s(alt="A photo")
      assert result =~ "max-width:100%"
      refute result =~ "<figure"
    end

    test "includes figcaption text as a styled paragraph" do
      html = """
      <figure>
        <img src="/photo.jpg" alt="" />
        <figcaption>Caption here</figcaption>
      </figure>
      """

      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "Caption here"
      assert result =~ "text-align:center"
    end

    test "omits figcaption paragraph when caption is blank" do
      html = """
      <figure>
        <img src="/photo.jpg" alt="" />
        <figcaption>   </figcaption>
      </figure>
      """

      result = NewsletterEdition.email_safe_html(html)

      refute result =~ "<p"
    end

    test "handles nested tags recursively" do
      html = "<ul><li class=\"item\"><strong>Point</strong></li></ul>"
      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "<ul>"
      assert result =~ "<li>"
      assert result =~ "<strong>Point</strong>"
      refute result =~ "class="
    end

    test "strips script tags and event-handler attributes" do
      html =
        "<p>Hi</p><img src=x onerror=\"alert(1)\"><script>alert(2)</script>"

      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "Hi"
      refute result =~ "onerror"
      refute result =~ "<script"
    end

    test "strips javascript: URLs from href attributes" do
      href = "javascript" <> ":alert(1)"
      html = "<a href=\"" <> href <> "\">Click me</a>"
      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "Click me"
      refute result =~ href
    end

    test "strips style tags entirely" do
      css = "display" <> ":none"
      html = "<p>Safe</p><style>body{" <> css <> "}</style>"
      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "Safe"
      refute result =~ "<style"
      refute result =~ css
    end
  end

  # ---------------------------------------------------------------------------
  # present_unsubscribe_url?/1
  # ---------------------------------------------------------------------------

  describe "present_unsubscribe_url?/1" do
    test "returns false for nil" do
      refute NewsletterEdition.present_unsubscribe_url?(nil)
    end

    test "returns false for empty string" do
      refute NewsletterEdition.present_unsubscribe_url?("")
    end

    test "returns false for placeholder '#'" do
      refute NewsletterEdition.present_unsubscribe_url?("#")
    end

    test "returns true for a real URL" do
      assert NewsletterEdition.present_unsubscribe_url?(
               "https://example.com/unsub/abc123"
             )
    end
  end

  # ---------------------------------------------------------------------------
  # build_assigns/4
  # ---------------------------------------------------------------------------

  describe "build_assigns/4" do
    defp base_edition do
      %{
        title: "Spring Update",
        intro_text: "<p>Hello!</p>",
        cover_image: nil,
        post_ids: [],
        event_ids: []
      }
    end

    defp base_subscriber do
      %{
        first_name: "Alice",
        email: "alice@example.com",
        subscription_token: "token123"
      }
    end

    test "builds assigns with subscriber first name and unsubscribe url" do
      assigns =
        NewsletterEdition.build_assigns(
          base_edition(),
          base_subscriber(),
          [],
          []
        )

      assert assigns.first_name == "Alice"
      assert assigns.unsubscribe_url =~ "token123"
      assert assigns.edition_title == "Spring Update"
    end

    test "includes edition_date from sent_at when present" do
      sent_at = ~U[2026-07-09 12:00:00Z]
      edition = Map.put(base_edition(), :sent_at, sent_at)

      assigns =
        NewsletterEdition.build_assigns(
          edition,
          base_subscriber(),
          [],
          []
        )

      assert assigns.edition_date == "Newsletter, July 9, 2026"
    end

    test "uses today's date for edition_date when sent_at is nil" do
      assigns =
        NewsletterEdition.build_assigns(
          base_edition(),
          base_subscriber(),
          [],
          []
        )

      today = Calendar.strftime(Date.utc_today(), "%B %-d, %Y")
      assert assigns.edition_date == "Newsletter, #{today}"
    end

    test "falls back to 'there' when subscriber first_name is nil" do
      subscriber = %{base_subscriber() | first_name: nil}

      assigns =
        NewsletterEdition.build_assigns(base_edition(), subscriber, [], [])

      assert assigns.first_name == "there"
    end

    test "sets unsubscribe_url to '#' when token is nil" do
      subscriber = %{base_subscriber() | subscription_token: nil}

      assigns =
        NewsletterEdition.build_assigns(base_edition(), subscriber, [], [])

      assert assigns.unsubscribe_url == "#"
    end

    test "sets intro_text? to true when intro_text is present" do
      assigns =
        NewsletterEdition.build_assigns(
          base_edition(),
          base_subscriber(),
          [],
          []
        )

      assert assigns.intro_text? == true
    end

    test "sets intro_text? to false when intro_text is blank" do
      edition = %{base_edition() | intro_text: ""}

      assigns =
        NewsletterEdition.build_assigns(edition, base_subscriber(), [], [])

      assert assigns.intro_text? == false
    end

    test "maps posts into render maps" do
      post = %{
        title: "Post Title",
        preview_text: "Preview",
        raw_body: nil,
        url_name: "post-title",
        featured_image: nil
      }

      assigns =
        NewsletterEdition.build_assigns(
          base_edition(),
          base_subscriber(),
          [post],
          []
        )

      assert length(assigns.posts) == 1
      [mapped] = assigns.posts
      assert mapped.title == "Post Title"
      assert mapped.url =~ "post-title"
    end
  end

  # ---------------------------------------------------------------------------
  # build_preview_assigns/5
  # ---------------------------------------------------------------------------

  describe "build_preview_assigns/5" do
    test "uses 'there' as first name and a preview unsubscribe URL" do
      assigns =
        NewsletterEdition.build_preview_assigns("Title", nil, nil, [], [])

      assert assigns.first_name == "there"
      assert assigns.unsubscribe_url =~ "preview"
    end

    test "sets intro_text? to false when intro_text is nil" do
      assigns =
        NewsletterEdition.build_preview_assigns("Title", nil, nil, [], [])

      assert assigns.intro_text? == false
    end

    test "sets cover_image_url when provided" do
      assigns =
        NewsletterEdition.build_preview_assigns(
          "Title",
          nil,
          "https://cdn.example.com/image.jpg",
          [],
          []
        )

      assert assigns.cover_image_url == "https://cdn.example.com/image.jpg"
    end
  end

  describe "build_archive_assigns/3" do
    test "builds assigns without subscriber (archive)" do
      edition = %{
        title: "Archive Title",
        intro_text: "<p>Archived intro</p>",
        cover_image: nil
      }

      assigns = NewsletterEdition.build_archive_assigns(edition, [], [])

      assert assigns.edition_title == "Archive Title"
      assert assigns.first_name == "there"
      assert assigns.unsubscribe_url =~ "preview"
    end

    test "includes edition_date from sent_at" do
      edition = %{
        title: "Archive Title",
        intro_text: "<p>Archived intro</p>",
        cover_image: nil,
        sent_at: ~U[2026-07-09 12:00:00Z]
      }

      assigns = NewsletterEdition.build_archive_assigns(edition, [], [])

      assert assigns.edition_date == "Newsletter, July 9, 2026"
    end
  end

  describe "email_safe_html/1 — extra branches" do
    test "converts non-image file figure to download link" do
      html = """
      <figure>
        <a href="/files/notes.pdf">
          <span class="attachment__name">notes.pdf</span>
          <span class="attachment__size">12 KB</span>
        </a>
      </figure>
      """

      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "notes.pdf"
      assert result =~ "href=\"/files/notes.pdf\""
      refute result =~ "class="
    end

    test "converts Trix div with only br to br output" do
      html = "<div><br></div>"
      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "br"
    end

    test "figure with img but no src omits img and keeps non-empty caption" do
      html = """
      <figure>
        <img alt="x" />
        <figcaption>Caption only</figcaption>
      </figure>
      """

      result = NewsletterEdition.email_safe_html(html)
      assert result =~ "Caption only"
    end

    test "non-image figure without href falls back to filename-only label" do
      html = """
      <figure>
        <span class="attachment__name">doc.pdf</span>
      </figure>
      """

      result = NewsletterEdition.email_safe_html(html)
      assert result =~ "doc.pdf"
      refute result =~ "href="
    end

    test "non-image figure with no link metadata yields empty output" do
      html = "<figure><span>orphan</span></figure>"
      result = NewsletterEdition.email_safe_html(html)
      assert result == ""
    end

    test "non-image figure with href but no filename uses Download file label" do
      html = """
      <figure>
        <a href="/files/attachment.bin">x</a>
      </figure>
      """

      result = NewsletterEdition.email_safe_html(html)

      assert result =~ "Download file"
      assert result =~ ~s(href="/files/attachment.bin")
    end

    test "non-image attachment uses filename only when size span is absent" do
      html = """
      <figure>
        <a href="/files/report.pdf">
          <span class="attachment__name">report.pdf</span>
        </a>
      </figure>
      """

      result = NewsletterEdition.email_safe_html(html)
      assert result =~ "report.pdf"
      refute result =~ "KB"
    end
  end

  describe "get_template_name/0 and render/1" do
    test "exposes template name and renders built assigns" do
      assert NewsletterEdition.get_template_name() == "newsletter_edition"

      assigns =
        NewsletterEdition.build_preview_assigns(
          "Weekly",
          "<p>Hi</p>",
          nil,
          [],
          []
        )

      html = NewsletterEdition.render(assigns)
      assert html =~ "Weekly"
      assert html =~ "Hi"
      assert html =~ "Newsletter,"
    end
  end

  describe "build_assigns/4 with images and posts" do
    test "prefers optimized cover image URL when present" do
      edition = %{
        title: "E",
        intro_text: "",
        cover_image: %{
          optimized_image_path: "https://cdn.example.com/opt.jpg",
          raw_image_path: "https://cdn.example.com/raw.jpg"
        }
      }

      subscriber = %{
        first_name: "Sam",
        email: "s@example.com",
        subscription_token: "tok"
      }

      assigns = NewsletterEdition.build_assigns(edition, subscriber, [], [])
      assert assigns.cover_image_url == "https://cdn.example.com/opt.jpg"
    end

    test "uses raw image path when optimized is nil" do
      edition = %{
        title: "E",
        intro_text: "",
        cover_image: %{
          optimized_image_path: nil,
          raw_image_path: "https://x/r.jpg"
        }
      }

      assigns =
        NewsletterEdition.build_assigns(
          edition,
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [],
          []
        )

      assert assigns.cover_image_url == "https://x/r.jpg"
    end

    test "uses raw_body for preview when preview_text is nil" do
      long_raw = String.duplicate("word ", 80)

      post = %{
        title: "P",
        preview_text: nil,
        raw_body: "<p>" <> long_raw <> "</p>",
        url_name: "p",
        featured_image: nil
      }

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "E", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [post],
          []
        )

      [mapped] = assigns.posts
      assert String.length(mapped.preview_text) <= 200
    end
  end

  describe "build_assigns/4 with events from database" do
    test "maps event fields including long description truncation" do
      event =
        event_fixture(%{
          description: String.duplicate("D", 200),
          location_name: "Hall"
        })

      event = Repo.preload(event, :cover_image)

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "Ed", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [],
          [event]
        )

      [em] = assigns.events
      assert em.title == event.title
      assert em.location_name == "Hall"
      assert String.ends_with?(em.short_description, "...")
    end

    test "includes tickets on sale line when tier has start_date" do
      event = event_fixture()

      sale_start =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.truncate(:second)

      {:ok, _} =
        Ysc.Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 50,
          event_id: event.id,
          start_date: sale_start
        })

      event = Repo.preload(event, :cover_image)

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "Ed", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [],
          [event]
        )

      [em] = assigns.events
      assert em.tickets_on_sale_str =~ "Tickets on sale"
    end

    test "uses empty date string when event has no start_date" do
      event = event_fixture()

      {:ok, event} =
        event |> Ecto.Changeset.change(%{start_date: nil}) |> Repo.update()

      event = Repo.preload(event, :cover_image)

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "Ed", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [],
          [event]
        )

      [em] = assigns.events
      assert em.date_str == ""
    end

    test "formats date_str with clock time when start_time is set" do
      event = event_fixture()

      {:ok, event} =
        event
        |> Ecto.Changeset.change(%{start_time: ~T[15:30:00]})
        |> Repo.update()

      event = Repo.preload(event, :cover_image)

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "Ed", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [],
          [event]
        )

      [em] = assigns.events
      assert em.date_str =~ " at "
      assert em.date_str =~ "15:30"
    end

    test "short_description is nil when event description is nil" do
      event =
        event_fixture()
        |> Ecto.Changeset.change(%{description: nil})
        |> Repo.update!()

      event = Repo.preload(event, :cover_image)

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "Ed", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [],
          [event]
        )

      [em] = assigns.events
      assert em.short_description == nil
    end
  end

  describe "post image URL mapping" do
    test "uses raw_image_path when optimized is absent" do
      post = %{
        title: "P",
        preview_text: "Hi",
        raw_body: nil,
        url_name: "p",
        featured_image: %{
          optimized_image_path: nil,
          raw_image_path: "https://cdn.example.com/r.jpg"
        }
      }

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "E", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [post],
          []
        )

      [mapped] = assigns.posts
      assert mapped.image_url == "https://cdn.example.com/r.jpg"
    end
  end

  describe "build_assigns/4 event save_the_date and post image branches" do
    test "sets save_the_date when event has tickets_tbd" do
      event =
        event_fixture()
        |> Ecto.Changeset.change(%{tickets_tbd: true})
        |> Repo.update!()

      event = Repo.preload(event, :cover_image)

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "Ed", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [],
          [event]
        )

      assert hd(assigns.events).save_the_date == true
    end

    test "post featured_image uses optimized path when set" do
      post = %{
        title: "P",
        preview_text: "Hi",
        raw_body: nil,
        url_name: "p",
        featured_image: %{
          optimized_image_path: "https://cdn.example.com/o.jpg",
          raw_image_path: "https://cdn.example.com/r.jpg"
        }
      }

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "E", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [post],
          []
        )

      assert hd(assigns.posts).image_url == "https://cdn.example.com/o.jpg"
    end

    test "clean_preview_text returns empty for whitespace-only preview" do
      post = %{
        title: "P",
        preview_text: "   \n  ",
        raw_body: nil,
        url_name: "p",
        featured_image: nil
      }

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "E", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [post],
          []
        )

      assert hd(assigns.posts).preview_text == ""
    end

    test "event short_description is full string when description is short" do
      event =
        event_fixture(%{description: "Short blurb"})
        |> Repo.preload(:cover_image)

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "Ed", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [],
          [event]
        )

      assert hd(assigns.events).short_description == "Short blurb"
    end
  end

  describe "NewsletterEdition template and build_assigns — extended coverage" do
    test "render includes optimized post image URL (Open Graph–style CDN path)" do
      og_url = "https://images.example.com/og/vacation-photo-1200x630.jpg"

      post = %{
        title: "Lake Day",
        preview_text: "Short preview",
        raw_body: nil,
        url_name: "lake-day",
        featured_image: %{
          optimized_image_path: og_url,
          raw_image_path: "https://images.example.com/raw/vacation.jpg"
        }
      }

      assigns =
        NewsletterEdition.build_preview_assigns(
          "Summer news",
          "",
          nil,
          [post],
          []
        )

      html = NewsletterEdition.render(assigns)
      assert html =~ og_url
      assert html =~ "Lake Day"
    end

    test "post assigns prefer preview_text when both preview_text and raw_body differ" do
      post = %{
        title: "P",
        preview_text: "From preview field",
        raw_body: "<p>From raw body which is different</p>",
        url_name: "p",
        featured_image: nil,
        published_on: ~U[2023-03-15 10:00:00Z],
        inserted_at: ~U[2024-01-01 10:00:00Z]
      }

      assigns =
        NewsletterEdition.build_assigns(
          %{title: "E", intro_text: "", cover_image: nil},
          %{first_name: "A", email: "a@a.com", subscription_token: "t"},
          [post],
          []
        )

      assert hd(assigns.posts).preview_text =~ "From preview field"
    end

    test "render with nil edition title omits title block and empty intro uses spacer path" do
      assigns =
        NewsletterEdition.build_preview_assigns(
          nil,
          nil,
          nil,
          [],
          []
        )

      html = NewsletterEdition.render(assigns)
      assert is_binary(html)
      refute html =~ "undefined"
    end

    test "render with post lacking featured_image still produces Read more link" do
      post = %{
        title: "No image",
        preview_text: nil,
        raw_body: "Body only",
        url_name: "no-img",
        featured_image: nil
      }

      assigns =
        NewsletterEdition.build_preview_assigns("T", "", nil, [post], [])

      html = NewsletterEdition.render(assigns)
      assert html =~ "Read more"
      assert html =~ "No image"
    end

    test "render hits cover image, event overlay badges, and hides unsubscribe for #" do
      event = %{
        title: "Fest",
        description: "Hi",
        short_description: "Short",
        date_str: "Jan 1",
        save_the_date: false,
        selling_fast: true,
        pricing_str: "$10",
        tickets_on_sale_str: nil,
        location_name: "Hall",
        url: "https://example.com/e/1",
        image_url: "https://images.example.com/banner.jpg"
      }

      assigns = %{
        first_name: "there",
        edition_title: "Weekly",
        edition_date: "Newsletter, July 9, 2026",
        intro_text: Phoenix.HTML.raw("<p>x</p>"),
        intro_text?: true,
        cover_image_url: "https://cdn.example.com/cover.jpg",
        posts: [],
        events: [event],
        unsubscribe_url: "#"
      }

      html = NewsletterEdition.render(assigns)
      assert html =~ "https://cdn.example.com/cover.jpg"
      assert html =~ "GOING FAST!"
      refute html =~ "Unsubscribe from newsletters"
    end
  end
end
