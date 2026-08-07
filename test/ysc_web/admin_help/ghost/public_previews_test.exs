defmodule YscWeb.AdminHelp.Ghost.PublicPreviewsTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YscWeb.AdminHelp.Ghost.PublicPreviews
  alias YscWeb.AdminHelp.Ghost.Registry

  defp render_slug(slug) do
    render_component(&PublicPreviews.preview/1, %{slug: slug})
  end

  defp doc(html), do: LazyHTML.from_fragment(html)

  defp has_id?(html, id),
    do: html |> doc() |> LazyHTML.query_by_id(id) |> Enum.any?()

  defp has_sel?(html, selector),
    do: html |> doc() |> LazyHTML.query(selector) |> Enum.any?()

  defp page_text(html), do: html |> doc() |> LazyHTML.text()

  describe "preview/1" do
    test "renders every registered public- slug without raising" do
      public_slugs =
        Registry.all() |> Enum.filter(&String.starts_with?(&1, "public-"))

      assert public_slugs != []

      for slug <- public_slugs do
        html = render_slug(slug)
        assert is_binary(html)
        assert html != ""
      end
    end

    test "renders the public-news-list preview" do
      html = render_slug("public-news-list")
      assert page_text(html) =~ "Club News"
      assert has_id?(html, "ghost-new-post-card")
    end

    test "renders the public-news-pinned preview" do
      html = render_slug("public-news-pinned")
      assert page_text(html) =~ "Pinned News"
      assert has_id?(html, "ghost-pinned-hero")
    end

    test "renders the public-news-article preview" do
      html = render_slug("public-news-article")
      assert has_id?(html, "ghost-article-hero")
    end

    test "renders the public-events-list preview" do
      html = render_slug("public-events-list")
      assert page_text(html) =~ "Events"
      assert has_id?(html, "ghost-new-event-card")
    end

    test "renders the public-event-page preview" do
      html = render_slug("public-event-page")
      assert has_id?(html, "ghost-public-event-details")
      assert page_text(html) =~ "Summer Cabin Weekend"
    end

    test "renders the public-event-agenda preview" do
      html = render_slug("public-event-agenda")
      assert page_text(html) =~ "Members see timed items"
    end

    test "renders the public-event-tickets preview" do
      html = render_slug("public-event-tickets")
      assert page_text(html) =~ "Sidebar pricing updates"
    end

    test "renders the public-event-ticket-tiers preview" do
      html = render_slug("public-event-ticket-tiers")
      assert page_text(html) =~ "Get Tickets"
    end

    test "renders the public-event-tickets-tbd preview" do
      html = render_slug("public-event-tickets-tbd")
      assert page_text(html) =~ "Tickets TBD"
    end

    test "renders the public-event-updates preview" do
      html = render_slug("public-event-updates")
      refute has_id?(html, "ghost-public-event-details")
      assert page_text(html) =~ "Summer Cabin Weekend"
    end

    test "renders the public-newsletter-archive preview" do
      html = render_slug("public-newsletter-archive")
      assert has_id?(html, "ghost-new-newsletter-edition")
    end

    test "renders the public-newsletter-edition preview" do
      html = render_slug("public-newsletter-edition")
      assert page_text(html) =~ "From the club"
    end

    test "renders a fallback message for an unknown slug" do
      html = render_slug("totally-unknown-slug")
      assert page_text(html) =~ "Unknown public preview."
    end
  end

  describe "public_page_shell (via preview/1)" do
    test "renders header with label and subtitle when show_header? is true" do
      html = render_slug("public-events-list")
      assert has_sel?(html, "header")
      assert page_text(html) =~ "Events"
      assert page_text(html) =~ "What's Next"
    end

    test "omits the header block when show_header? is false" do
      html = render_slug("public-event-page")
      refute has_sel?(html, "header")
    end
  end
end
