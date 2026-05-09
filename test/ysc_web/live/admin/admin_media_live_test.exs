defmodule YscWeb.AdminMediaLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.TestDataFactory

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "Admin Media" do
    setup [:create_admin]

    test "renders media library", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/media")
      assert html =~ "Media Library"
    end

    test "navigates to upload page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/media")

      view
      |> element("button", "New Image")
      |> render_click()

      assert_patched(view, ~p"/admin/media/upload")
    end

    test "renders page-wide drag and drop upload target", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/media")

      assert has_element?(
               view,
               "#media-page-drop-target[phx-hook='MediaDropZone'][phx-drop-target]"
             )

      assert has_element?(
               view,
               "#media-drop-upload-form[phx-submit='save'][phx-change='validate'] input[type='file']"
             )
    end

    test "clearing search URL restores full gallery results", %{conn: conn} do
      _other =
        create_test_image(%{
          title: "AdminMediaOtherImage998877"
        })

      matching =
        create_test_image(%{
          title: "AdminMediaUniqueSearchTitle554433"
        })

      {:ok, view, html} =
        live(conn, ~p"/admin/media?search=#{matching.title}")

      assert html =~ matching.title
      refute html =~ "AdminMediaOtherImage998877"

      html_after_clear = render_patch(view, ~p"/admin/media")

      assert html_after_clear =~ matching.title
      assert html_after_clear =~ "AdminMediaOtherImage998877"
    end

    test "toggles the media gallery between square and masonry layouts", %{
      conn: conn
    } do
      image =
        create_test_image(%{
          width: 800,
          height: 1200,
          processing_state: "completed"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/media")

      assert has_element?(view, "[aria-label='Media layout']")

      assert has_element?(
               view,
               "button[phx-value-layout='square'][aria-pressed='false']"
             )

      assert has_element?(
               view,
               "button[phx-value-layout='masonry'][aria-pressed='true']"
             )

      assert has_element?(view, "#images-grid.media-masonry-grid")

      view
      |> element("button[phx-click='set-layout'][phx-value-layout='square']")
      |> render_click()

      assert has_element?(
               view,
               "button[phx-value-layout='square'][aria-pressed='true']"
             )

      assert has_element?(
               view,
               "button[phx-value-layout='masonry'][aria-pressed='false']"
             )

      assert has_element?(view, "#images-grid.grid")

      assert has_element?(
               view,
               "#images-grid.media-square-grid #image-#{image.id}"
             )
    end

    test "shows a round warning indicator when alt text is missing", %{
      conn: conn
    } do
      image =
        create_test_image(%{
          alt_text: "",
          processing_state: "completed"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/media")

      assert has_element?(
               view,
               "#image-#{image.id} [aria-label='Missing alt text'].h-7.w-7.rounded-full"
             )
    end
  end
end
