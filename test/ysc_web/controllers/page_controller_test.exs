defmodule YscWeb.PageControllerTest do
  use YscWeb.ConnCase
  import Mox
  import Ysc.AccountsFixtures

  # Set up mocks for this test module
  setup :verify_on_exit!

  describe "GET /" do
    test "renders home page", %{conn: conn} do
      conn = get(conn, ~p"/")
      # Check for content that actually exists on the home page
      html = html_response(conn, 200)
      assert html =~ "Young Scandinavians Club"
    end
  end

  describe "GET /choir" do
    test "renders choir leader by name when no matching user exists", %{
      conn: conn
    } do
      conn = get(conn, ~p"/choir")

      html = html_response(conn, 200)
      assert html =~ "The choir is led by our board member"
      assert html =~ "Christoffer Tevrén"
      assert conn.assigns.choir_leader == nil
    end

    test "renders choir leader user card when matching user exists", %{
      conn: conn
    } do
      user_fixture(%{
        email: "chrtev@gmail.com",
        first_name: "Christoffer",
        last_name: "Tevrén"
      })

      conn = get(conn, ~p"/choir")

      html = html_response(conn, 200)
      assert html =~ "Choir Leader"
      assert html =~ "Christoffer Tevrén"
      assert html =~ ~s(alt="User avatar")
      assert conn.assigns.choir_leader.email == "chrtev@gmail.com"
    end
  end

  describe "GET /pending-review" do
    setup %{conn: conn} do
      user = user_fixture(%{country: "SE", state: :pending_approval})
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "redirects active users with membership to the home page", %{
      conn: conn
    } do
      active_user = user_fixture(%{country: "SE", state: :active})

      {:ok, _sub} =
        Ysc.Subscriptions.create_subscription(%{
          name: "Test Membership",
          stripe_id: "sub_pending_review_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          user_id: active_user.id,
          current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
        })

      _ = Ysc.Accounts.MembershipCache.invalidate_user(active_user.id)

      conn = conn |> log_in_user(active_user) |> get(~p"/pending-review")

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects unpaid active users to account setup payment step", %{
      conn: conn
    } do
      active_user = user_fixture(%{country: "SE", state: :active})
      conn = conn |> log_in_user(active_user) |> get(~p"/pending-review")

      assert redirected_to(conn) ==
               ~p"/account/setup/#{active_user.id}?step=1"
    end

    test "redirects rejected users to login when session is invalid", %{
      conn: conn
    } do
      rejected_user = user_fixture(%{country: "SE", state: :rejected})
      conn = conn |> log_in_user(rejected_user) |> get(~p"/pending-review")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "redirects suspended users to login when session is invalid", %{
      conn: conn
    } do
      suspended_user = user_fixture(%{country: "SE", state: :suspended})
      conn = conn |> log_in_user(suspended_user) |> get(~p"/pending-review")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "redirects deleted users to login when session is invalid", %{
      conn: conn
    } do
      deleted_user = user_fixture(%{country: "SE", state: :deleted})
      conn = conn |> log_in_user(deleted_user) |> get(~p"/pending-review")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "renders pending review page with submission from Pacific timezone", %{
      conn: conn,
      user: _user
    } do
      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)
      timezone = "America/Los_Angeles"

      Mox.expect(
        Ysc.AccountsMock,
        :get_signup_application_submission_date,
        fn _user_id ->
          %{submit_date: submitted_date, timezone: timezone}
        end
      )

      conn = get(conn, ~p"/pending-review")

      assert html_response(conn, 200) =~ "Account Pending Review"
      assert conn.assigns.application_submitted_date != nil
      assert conn.assigns.time_delta =~ "ago"
    end

    test "renders pending review page with submission from different timezone",
         %{
           conn: conn,
           user: _user
         } do
      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)
      timezone = "Europe/Stockholm"

      Mox.expect(
        Ysc.AccountsMock,
        :get_signup_application_submission_date,
        fn _user_id ->
          %{submit_date: submitted_date, timezone: timezone}
        end
      )

      conn = get(conn, ~p"/pending-review")

      assert html_response(conn, 200)
      assert conn.assigns.application_submitted_date != nil
      assert conn.assigns.time_delta =~ "ago"
    end

    test "handles missing timezone by defaulting to America/Los_Angeles", %{
      conn: conn,
      user: _user
    } do
      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)

      Mox.expect(
        Ysc.AccountsMock,
        :get_signup_application_submission_date,
        fn _user_id ->
          %{submit_date: submitted_date, timezone: nil}
        end
      )

      conn = get(conn, ~p"/pending-review")

      assert html_response(conn, 200)
      assert conn.assigns.application_submitted_date != nil
      assert conn.assigns.time_delta =~ "ago"
    end
  end

  test "requires authentication", %{conn: conn} do
    conn = get(conn, ~p"/pending-review")
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
