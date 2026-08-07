defmodule YscWeb.AdminHelp.Ghost.PreviewsTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YscWeb.AdminHelp.Ghost.Previews
  alias YscWeb.AdminHelp.Ghost.Registry

  defp render_slug(slug) do
    render_component(&Previews.preview/1, %{slug: slug})
  end

  defp doc(html), do: LazyHTML.from_fragment(html)

  defp has_id?(html, id),
    do: html |> doc() |> LazyHTML.query_by_id(id) |> Enum.any?()

  defp has_sel?(html, selector),
    do: html |> doc() |> LazyHTML.query(selector) |> Enum.any?()

  defp page_text(html), do: html |> doc() |> LazyHTML.text()

  describe "preview/1 admin slugs" do
    test "renders every registered admin (non-public) slug without raising" do
      admin_slugs =
        Registry.all() |> Enum.reject(&String.starts_with?(&1, "public-"))

      assert admin_slugs != []

      for slug <- admin_slugs do
        html = render_slug(slug)
        assert is_binary(html)
        assert html != ""
      end
    end

    test "renders the getting-started-login preview content" do
      html = render_slug("getting-started-login")
      assert page_text(html) =~ "Admin"
      assert has_id?(html, "ghost-admin-fab")
    end

    test "renders the getting-started-dashboard preview inside the shell" do
      html = render_slug("getting-started-dashboard")
      assert has_sel?(html, ".admin-help-ghost-content")
    end

    test "renders the posts-list preview with search and table" do
      html = render_slug("posts-list")
      assert page_text(html) =~ "Posts"
      assert has_sel?(html, ~s(input[placeholder="Search by post title..."]))
      assert has_id?(html, "ghost-new-post")
    end

    test "renders the newsletter-compose preview" do
      html = render_slug("newsletter-compose")
      assert has_id?(html, "ghost-newsletter-editor-panel")
      assert has_id?(html, "ghost-newsletter-preview-panel")
    end

    test "renders the events-edit preview sections" do
      html = render_slug("events-edit")
      assert has_id?(html, "ghost-event-cover-section")
      assert has_id?(html, "ghost-event-agenda-section")
    end

    test "renders the events-updates preview timeline" do
      html = render_slug("events-updates")
      assert has_id?(html, "ghost-event-communication-timeline")
    end

    test "renders the media-gallery preview" do
      html = render_slug("media-gallery")
      assert page_text(html) =~ "Media"
      assert page_text(html) =~ "Upload new images"
    end

    test "renders the check-in-desk preview" do
      html = render_slug("check-in-desk")
      assert has_id?(html, "ghost-event-check-in-desk")
    end

    test "renders the scanner preview" do
      html = render_slug("scanner")
      assert has_id?(html, "ghost-scanner")
    end

    test "renders a fallback message for an unknown admin slug" do
      html = render_slug("totally-unknown-slug")
      assert page_text(html) =~ "Unknown preview."
    end
  end

  describe "preview/1 public delegation" do
    test "delegates slugs prefixed with public- to the public previews module" do
      html = render_slug("public-news-list")
      assert page_text(html) =~ "Club News"
    end

    test "delegates an unknown public- slug to the public fallback" do
      html = render_slug("public-does-not-exist")
      assert page_text(html) =~ "Unknown public preview."
    end
  end
end
