defmodule YscWeb.AdminHelp.Ghost.PublicPreviewsTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YscWeb.AdminHelp.Ghost.PublicPreviews
  alias YscWeb.AdminHelp.Ghost.Registry

  defp render_slug(slug) do
    render_component(&PublicPreviews.preview/1, %{slug: slug})
  end

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
      assert html =~ "Club News"
      assert html =~ "ghost-new-post-card"
    end

    test "renders the public-news-pinned preview" do
      html = render_slug("public-news-pinned")
      assert html =~ "Pinned News"
      assert html =~ "ghost-pinned-hero"
    end

    test "renders the public-news-article preview" do
      html = render_slug("public-news-article")
      assert html =~ "ghost-article-hero"
    end

    test "renders the public-events-list preview" do
      html = render_slug("public-events-list")
      assert html =~ "Events"
      assert html =~ "ghost-new-event-card"
    end

    test "renders the public-event-page preview" do
      html = render_slug("public-event-page")
      assert html =~ "ghost-public-event-details"
      assert html =~ "Summer Cabin Weekend"
    end

    test "renders the public-event-agenda preview" do
      html = render_slug("public-event-agenda")
      assert html =~ "Members see timed items"
    end

    test "renders the public-event-tickets preview" do
      html = render_slug("public-event-tickets")
      assert html =~ "Sidebar pricing updates"
    end

    test "renders the public-event-ticket-tiers preview" do
      html = render_slug("public-event-ticket-tiers")
      assert html =~ "Get Tickets"
    end

    test "renders the public-event-tickets-tbd preview" do
      html = render_slug("public-event-tickets-tbd")
      assert html =~ "Tickets TBD"
    end

    test "renders the public-event-updates preview" do
      html = render_slug("public-event-updates")
      refute html =~ "ghost-public-event-details"
      assert html =~ "Summer Cabin Weekend"
    end

    test "renders the public-newsletter-archive preview" do
      html = render_slug("public-newsletter-archive")
      assert html =~ "ghost-new-newsletter-edition"
    end

    test "renders the public-newsletter-edition preview" do
      html = render_slug("public-newsletter-edition")
      assert html =~ "From the club"
    end

    test "renders a fallback message for an unknown slug" do
      html = render_slug("totally-unknown-slug")
      assert html =~ "Unknown public preview."
    end
  end

  describe "public_page_shell (via preview/1)" do
    test "renders header with label and subtitle when show_header? is true" do
      html = render_slug("public-events-list")
      assert html =~ "Events"
      assert html =~ "What&#39;s Next" or html =~ "What's Next"
    end

    test "omits the header block when show_header? is false" do
      html = render_slug("public-event-page")
      refute html =~ "<header"
    end
  end
end
