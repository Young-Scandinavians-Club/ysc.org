defmodule YscWeb.MediaPickerComponentTest do
  @moduledoc """
  Tests for the MediaPickerComponent used in newsletter editor and events forms.
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  alias Ysc.Media
  alias Ysc.Media.Image
  alias Ysc.Repo

  defp create_admin(%{conn: conn}) do
    user = user_fixture_fast(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp create_image(user, attrs \\ %{}) do
    {:ok, image} =
      %Image{
        user_id: user.id,
        raw_image_path: "https://example.com/test.jpg",
        thumbnail_path: "https://example.com/test_thumb.jpg",
        processing_state: :completed
      }
      |> Map.merge(attrs)
      |> Repo.insert()

    image
  end

  # Valid 1×1 PNG so LiveView accepts the upload entry.
  defp tiny_png do
    <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
      0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84,
      8, 215, 99, 248, 207, 192, 0, 0, 3, 1, 1, 0, 24, 221, 141, 176, 0, 0, 0,
      0, 73, 69, 78, 68, 174, 66, 96, 130>>
  end

  describe "MediaPickerComponent in newsletter editor" do
    setup [:create_admin]

    test "shows upload zone and 'Choose from library' button for new edition",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      assert has_element?(view, "#media-picker-newsletter_cover")
      assert has_element?(view, "button", "Choose from library")
    end

    test "opens media picker modal when clicking 'Choose from library'", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      view
      |> element("#media-picker-newsletter_cover button", "Choose from library")
      |> render_click()

      assert has_element?(view, "#media-picker-modal-newsletter_cover")
      assert has_element?(view, "h2", "Media library")
    end

    test "media picker modal shows year filter buttons", %{
      conn: conn,
      admin: admin
    } do
      _image = create_image(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      view
      |> element("#media-picker-newsletter_cover button", "Choose from library")
      |> render_click()

      assert has_element?(
               view,
               "#media-picker-modal-newsletter_cover button",
               "All"
             )
    end

    test "media picker modal shows search input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      view
      |> element("#media-picker-newsletter_cover button", "Choose from library")
      |> render_click()

      assert has_element?(view, "input[name='search']")
    end

    test "in-progress upload shows a cancel overlay without a filename caption",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      upload =
        file_input(view, "#newsletter_cover-upload-form", :media_picker_file, [
          %{name: "cover.png", content: tiny_png(), type: "image/png"}
        ])

      html = render_upload(upload, "cover.png", 50)

      assert html =~ "upload-entry__cancel"
      assert html =~ ~s(aria-label="cancel")
      assert html =~ "hero-x-circle"
      assert html =~ "Phoenix.LiveImgPreview"
      refute html =~ "<figcaption"

      assert has_element?(
               view,
               "#newsletter_cover-upload-form button[aria-label='cancel']"
             )

      view
      |> element("#newsletter_cover-upload-form button[aria-label='cancel']")
      |> render_click()

      refute has_element?(
               view,
               "#newsletter_cover-upload-form button[aria-label='cancel']"
             )
    end

    test "selecting an image from the modal sends it to the parent", %{
      conn: conn,
      admin: admin
    } do
      image = create_image(admin, %{title: "Test Cover"})

      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      view
      |> element("#media-picker-newsletter_cover button", "Choose from library")
      |> render_click()

      view
      |> element(
        "#media-picker-grid-newsletter_cover button[phx-value-image-id='#{image.id}']"
      )
      |> render_click()

      refute has_element?(view, "#media-picker-modal-newsletter_cover")
    end

    test "load-more-media appends the next page of images", %{
      conn: conn,
      admin: admin
    } do
      # Page size is 30; create enough rows for a second page.
      for i <- 1..35 do
        create_image(admin, %{
          title: "Pager #{i}",
          raw_image_path: "https://example.com/pager-#{i}.jpg",
          thumbnail_path: "https://example.com/pager-#{i}_thumb.jpg"
        })
      end

      first_page = Media.list_images_cursor(limit: 30)
      last_on_first = List.last(first_page)

      second_page =
        Media.list_images_cursor(
          limit: 30,
          before_date: last_on_first.inserted_at,
          before_id: last_on_first.id
        )

      second_page_image = hd(second_page)

      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      view
      |> element("#media-picker-newsletter_cover button", "Choose from library")
      |> render_click()

      assert has_element?(view, "#newsletter_cover-scroll")
      assert has_element?(view, "#newsletter_cover-load-more-footer")

      assert has_element?(
               view,
               "#media-picker-grid-newsletter_cover button[phx-value-image-id='#{hd(first_page).id}']"
             )

      refute has_element?(
               view,
               "#media-picker-grid-newsletter_cover button[phx-value-image-id='#{second_page_image.id}']"
             )

      view
      |> element("#newsletter_cover-scroll")
      |> render_hook("load-more-media", %{})

      assert has_element?(
               view,
               "#media-picker-grid-newsletter_cover button[phx-value-image-id='#{second_page_image.id}']"
             )
    end
  end
end
