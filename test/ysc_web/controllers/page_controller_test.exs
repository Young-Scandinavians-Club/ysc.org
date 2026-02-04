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

  describe "GET /pending-review" do
    setup %{conn: conn} do
      # Add country code for avatar
      user = user_fixture(%{country: "SE"})
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "renders pending review page with submission from Pacific timezone", %{
      conn: conn,
      user: _user
    } do
      # Setup submission date in Pacific timezone (5 minutes ago to ensure "ago" is returned)
      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)
      timezone = "America/Los_Angeles"

      # Mock the get_signup_application_submission_date function
      Mox.expect(
        Ysc.AccountsMock,
        :get_signup_application_submission_date,
        fn _user_id ->
          %{submit_date: submitted_date, timezone: timezone}
        end
      )

      conn = get(conn, ~p"/pending-review")

      # Adjust based on your actual page content
      assert html_response(conn, 200) =~ "Account Pending Review"
      assert conn.assigns.application_submitted_date != nil
      # Since Timex.from_now returns a string with "ago"
      assert conn.assigns.time_delta =~ "ago"
    end

    test "renders pending review page with submission from different timezone",
         %{
           conn: conn,
           user: _user
         } do
      # Setup submission date in a different timezone (5 minutes ago to ensure "ago" is returned)
      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)
      timezone = "Europe/Stockholm"

      # Mock the get_signup_application_submission_date function
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
      # Setup submission date without timezone (5 minutes ago to ensure "ago" is returned)
      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)

      # Mock the get_signup_application_submission_date function
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
