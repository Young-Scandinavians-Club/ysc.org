defmodule YscWeb.AdminDashboardLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "Admin Dashboard" do
    setup [:create_admin]

    test "renders dashboard overview", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Overview"
      assert html =~ "Applications"
      assert html =~ "Total Revenue"
    end

    test "navigates to user review from pending applications", %{conn: conn} do
      # Create a pending user
      pending_user =
        user_fixture(%{
          state: "pending_approval",
          first_name: "Pending",
          last_name: "User"
        })

      # We need to ensure the user has a registration form if the dashboard expects it for some UI elements,
      # but let's see if it renders without it first.

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert render(view) =~ "Pending User"

      view
      |> element("button", "Review")
      |> render_click()

      params = %{
        "filters" => %{
          "0" => %{
            "field" => "state",
            "op" => "in",
            "value" => ["pending_approval"]
          }
        },
        "search" => ""
      }

      assert_redirected(
        view,
        ~p"/admin/users/#{pending_user.id}/review?#{params}"
      )
    end
  end
end
