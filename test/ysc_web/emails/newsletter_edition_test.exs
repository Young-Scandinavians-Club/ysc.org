defmodule YscWeb.Emails.NewsletterEditionTest do
  use ExUnit.Case, async: true

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
end
