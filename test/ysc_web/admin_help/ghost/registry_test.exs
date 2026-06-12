defmodule YscWeb.AdminHelp.Ghost.RegistryTest do
  use ExUnit.Case, async: true

  alias YscWeb.AdminHelp.Ghost.Registry

  test "all preview slugs are fetchable" do
    for slug <- Registry.all() do
      assert {:ok, %{slug: ^slug}} = Registry.fetch(slug)
    end
  end

  test "print_image_path/1 resolves ghost slugs to static fallbacks" do
    assert Registry.print_image_path("ghost:posts-list") =~
             "/images/admin-help/posts-list"

    assert Registry.print_image_path("/images/foo.png") == "/images/foo.png"
  end

  test "print_image_path/2 resolves scroll-variant paths" do
    path =
      Registry.print_image_path("ghost:newsletter-compose",
        scroll_to: "ghost-newsletter-preview-panel"
      )

    assert path =~ "/images/admin-help/newsletter-compose"
    assert path =~ "ghost-newsletter-preview-panel" or path =~ ".png"
  end

  test "print_asset_basename/2 encodes scroll targets in filenames" do
    assert Registry.print_asset_basename("newsletter-compose") ==
             "newsletter-compose"

    assert Registry.print_asset_basename(
             "newsletter-compose",
             "ghost-newsletter-preview-panel"
           ) == "newsletter-compose--ghost-newsletter-preview-panel"
  end

  test "capture_targets/0 includes base slugs and scroll variants from guides" do
    targets = Registry.capture_targets()

    assert %{slug: "posts-list", scroll_to: nil} in targets

    assert Enum.any?(targets, fn t ->
             t.slug == "newsletter-compose" and
               t.scroll_to == "ghost-newsletter-preview-panel"
           end)

    assert Enum.any?(targets, fn t ->
             t.slug == "public-event-page" and
               t.scroll_to == "ghost-public-event-details"
           end)
  end
end
