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
  end
end
