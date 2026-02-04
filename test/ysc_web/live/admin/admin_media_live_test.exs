defmodule YscWeb.AdminMediaLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

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

      assert_redirected(view, ~p"/admin/media/upload")
    end
  end
end
