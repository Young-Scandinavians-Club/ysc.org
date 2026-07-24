defmodule YscWeb.LegacyRedirectControllerTest do
  use YscWeb.ConnCase, async: true

  describe "GET /lake-tahoe-cabin" do
    test "redirects to /bookings/tahoe with 301", %{conn: conn} do
      conn = get(conn, ~p"/lake-tahoe-cabin")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/bookings/tahoe"
    end

    test "preserves query string on redirect", %{conn: conn} do
      conn = get(conn, ~p"/lake-tahoe-cabin?season=summer")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/bookings/tahoe?season=summer"
    end
  end

  describe "GET /lake-tahoe-cabin/tahoe-cabin-booking" do
    test "redirects to /bookings/tahoe with 301", %{conn: conn} do
      conn = get(conn, ~p"/lake-tahoe-cabin/tahoe-cabin-booking")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/bookings/tahoe"
    end
  end

  describe "GET /clear-lake-cabin" do
    test "redirects to /bookings/clear-lake with 301", %{conn: conn} do
      conn = get(conn, ~p"/clear-lake-cabin")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/bookings/clear-lake"
    end

    test "preserves query string on redirect", %{conn: conn} do
      conn = get(conn, ~p"/clear-lake-cabin?season=summer")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/bookings/clear-lake?season=summer"
    end
  end

  describe "GET /clear-lake-cabin/clear-lake-booking-calendar" do
    test "redirects to /bookings/clear-lake with 301", %{conn: conn} do
      conn = get(conn, ~p"/clear-lake-cabin/clear-lake-booking-calendar")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/bookings/clear-lake"
    end
  end

  describe "GET /login-2" do
    test "redirects to /users/log-in with 301", %{conn: conn} do
      conn = get(conn, ~p"/login-2")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/users/log-in"
    end

    test "preserves query string on redirect", %{conn: conn} do
      conn = get(conn, ~p"/login-2?return_to=/bookings/tahoe")

      assert conn.status == 301

      assert redirected_to(conn, 301) ==
               ~p"/users/log-in?return_to=/bookings/tahoe"
    end
  end

  describe "GET /register" do
    test "redirects to /users/register with 301", %{conn: conn} do
      conn = get(conn, ~p"/register")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/users/register"
    end

    test "preserves query string on redirect", %{conn: conn} do
      conn = get(conn, ~p"/register?invite=abc123")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/users/register?invite=abc123"
    end
  end
end
