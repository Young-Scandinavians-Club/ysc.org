defmodule YscWeb.AdminMediaLibraryBrowserTest do
  use YscWeb.ConnCase, async: true
  use Phoenix.Component

  require Phoenix.LiveViewTest

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import YscWeb.AdminComponents

  describe "media_library_thumbnail_url/1" do
    test "prefers thumbnail, then optimized, then raw path" do
      assert media_library_thumbnail_url(%{thumbnail_path: "/t.jpg"}) == "/t.jpg"

      assert media_library_thumbnail_url(%{
               thumbnail_path: "",
               optimized_image_path: "/o.jpg"
             }) == "/o.jpg"

      assert media_library_thumbnail_url(%{
               thumbnail_path: nil,
               optimized_image_path: nil,
               raw_image_path: "/r.jpg"
             }) == "/r.jpg"

      assert media_library_thumbnail_url(%{}) == "/images/ysc_logo.webp"
    end
  end

  describe "admin_media_library_browser/1" do
    test "renders search, year pills, and grid shell" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_media_library_browser
          id="cover"
          grid_id="media-picker-grid-cover"
          target="picker-target"
          search=""
          selected_year={nil}
          available_years={[2025, 2024]}
          picker_images={[]}
          end_of_timeline?={false}
        />
        """)

      assert html =~ ~s(id="cover-search-form")
      assert html =~ ~s(phx-change="search-media")
      assert html =~ ~s(phx-target="picker-target")
      assert html =~ "Search by title or alt text"
      assert html =~ ~s(id="media-picker-grid-cover")
      assert html =~ ~s(phx-update="stream")
      assert html =~ ~s(phx-viewport-bottom="load-more-media")
      assert html =~ "All"
      assert html =~ "2025"
      assert html =~ "2024"
      assert html =~ "bg-zinc-800 text-white"
    end

    test "shows end-of-timeline message when enabled" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_media_library_browser
          id="cover"
          grid_id="media-picker-grid-cover"
          target="picker-target"
          search=""
          selected_year={nil}
          available_years={[]}
          picker_images={[]}
          end_of_timeline?={true}
        />
        """)

      assert html =~ "No more images"
    end
  end
end
