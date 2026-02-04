defmodule YscWeb.AdminMoneyLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "Admin Money" do
    setup [:create_admin]

    test "renders money management page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/money")
      assert html =~ "Money Management"
      assert html =~ "Account Balances"
      assert html =~ "Recent Payments"
    end

    test "toggles sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      assert render(view) =~ "Ledger Entries"

      # Initially collapsed sections might not show their content
      refute render(view) =~ "Debit/Credit"

      view
      |> element("button", "Ledger Entries")
      |> render_click()

      assert render(view) =~ "Debit/Credit"
    end

    test "updates date range", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      view
      |> form("form[phx-submit='update_date_range']", %{
        "start_date" => "2023-01-01",
        "end_date" => "2023-12-31"
      })
      |> render_submit()

      assert render(view) =~
               "Showing data from January 01, 2023 to December 31, 2023"
    end
  end
end
