defmodule YscWeb.AdminHelp.HotspotTest do
  use ExUnit.Case, async: true

  alias YscWeb.AdminHelp.Hotspot

  test "admin ghost slugs use the sidebar layout" do
    assert Hotspot.admin_ghost?("posts-list")
    refute Hotspot.admin_ghost?("public-news-list")
    assert Hotspot.admin_ghost?("getting-started-dashboard")
    refute Hotspot.admin_ghost?("getting-started-login")
    assert Hotspot.admin_ghost?("getting-started-sidebar")
  end

  test "viewport-expanded coordinates convert to content-relative values" do
    [%{expanded: hotspot}] =
      Hotspot.normalize(
        [%{x: 70, y: 4, w: 12, h: 6, label: "Publish"}],
        "posts-publish"
      )

    assert hotspot.area == :content
    assert_in_delta hotspot.x, 61.29, 0.1
    assert_in_delta hotspot.w, 15.48, 0.1
  end

  test "expanded and collapsed layouts are normalized independently" do
    [%{expanded: expanded, collapsed: collapsed}] =
      Hotspot.normalize(
        [
          %{
            label: "Publish",
            expanded: %{x: 70, y: 4, w: 12, h: 6},
            collapsed: %{area: :content, x: 65, y: 4, w: 16, h: 6}
          }
        ],
        "posts-publish"
      )

    assert expanded.area == :content
    assert collapsed.area == :content
    assert_in_delta expanded.x, 61.29, 0.1
    assert collapsed.x == 65
    assert collapsed.w == 16
  end

  test "content hotspots use sidebar-aware CSS variables for both layouts" do
    style =
      Hotspot.css_vars(%{
        expanded: %{area: :content, x: 50, y: 10, w: 20, h: 8},
        collapsed: %{area: :content, x: 55, y: 10, w: 22, h: 8}
      })

    assert style =~ "--admin-help-hotspot-left-expanded"
    assert style =~ "--admin-help-hotspot-left-collapsed"
    assert style =~ "var(--admin-help-sidebar-pct)"
    assert style =~ "var(--admin-help-content-pct)"
  end

  test "ghost_src/2 encodes sidebar state" do
    assert Hotspot.ghost_src("posts-list", true) =~ "sidebar_collapsed=1"
    assert Hotspot.ghost_src("posts-list", false) =~ "sidebar_collapsed=0"
  end

  test "ghost_src/3 encodes scroll_to for section anchors" do
    url = Hotspot.ghost_src("events-edit", false, "ghost-event-agenda-section")

    assert url =~ "scroll_to=ghost-event-agenda-section"
    refute Hotspot.ghost_src("events-edit", false, "../evil") =~ "scroll_to="
  end

  test "hint style maps to hint CSS class" do
    hotspot = %{label: "Timeline", style: :hint, x: 0, y: 0, w: 50, h: 50}

    assert Hotspot.style_class(hotspot) == "admin-help-hotspot--hint"
    assert Hotspot.hint?(hotspot)
    refute Hotspot.hint?(%{label: "x", x: 0, y: 0, w: 1, h: 1})
  end
end
