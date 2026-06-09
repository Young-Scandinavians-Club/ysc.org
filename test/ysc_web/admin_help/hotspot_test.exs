defmodule YscWeb.AdminHelp.HotspotTest do
  use ExUnit.Case, async: true

  alias YscWeb.AdminHelp.Hotspot

  test "admin ghost slugs use the sidebar layout" do
    assert Hotspot.admin_ghost?("posts-list")
    refute Hotspot.admin_ghost?("public-news-list")
    refute Hotspot.admin_ghost?("getting-started-dashboard")
    assert Hotspot.admin_ghost?("getting-started-sidebar")
  end

  test "viewport-expanded coordinates convert to content-relative values" do
    [hotspot] =
      Hotspot.normalize(
        [%{x: 70, y: 4, w: 12, h: 6, label: "Publish"}],
        "posts-publish"
      )

    assert hotspot.area == :content
    assert_in_delta hotspot.x, 61.29, 0.1
    assert_in_delta hotspot.w, 15.48, 0.1
  end

  test "content hotspots use sidebar-aware CSS variables" do
    style = Hotspot.style(%{area: :content, x: 50, y: 10, w: 20, h: 8})

    assert style =~ "var(--admin-help-sidebar-pct)"
    assert style =~ "var(--admin-help-content-pct)"
  end

  test "ghost_src/2 encodes sidebar state" do
    assert Hotspot.ghost_src("posts-list", true) =~ "sidebar_collapsed=1"
    assert Hotspot.ghost_src("posts-list", false) =~ "sidebar_collapsed=0"
  end
end
