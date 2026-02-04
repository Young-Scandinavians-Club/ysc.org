defmodule YscWeb.UserTicketsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  describe "mount/3" do
    test "loads tickets page successfully", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/users/tickets")

      assert html =~ "Your Tickets"
      assert html =~ "Find More Events"
    end

    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/users/tickets")
      assert path == "/users/log-in"
    end

    test "displays empty state when user has no tickets", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      assert has_element?(view, "#ticket-orders-empty")
    end

    test "displays page structure with navigation elements", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/users/tickets")

      # Check for main page structure
      assert html =~ "Member Portal"
      assert html =~ "Browse Events"
    end

    test "displays title as page_title", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      assert page_title(view) =~ "My Tickets"
    end
  end

  describe "event handlers" do
    test "cancel-order event shows error when order not found", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      result =
        render_click(view, "cancel-order", %{"order-id" => Ecto.ULID.generate()})

      assert result =~ "Order not found"
    end

    test "resume-order event shows error when order not found", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      result =
        render_click(view, "resume-order", %{"order-id" => Ecto.ULID.generate()})

      assert result =~ "Order not found"
    end

    test "view-tickets event redirects to confirmation page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      fake_order_id = Ecto.ULID.generate()

      assert {:error, {:redirect, %{to: path}}} =
               render_click(view, "view-tickets", %{"order-id" => fake_order_id})

      assert path == "/orders/#{fake_order_id}/confirmation"
    end
  end
end
