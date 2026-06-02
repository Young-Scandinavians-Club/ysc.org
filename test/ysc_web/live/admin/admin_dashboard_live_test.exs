defmodule YscWeb.AdminDashboardLiveTest do
  # LiveView + connected?/async can race; keep this module sync for stable WS.
  use YscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Accounts.User
  alias Ysc.Repo

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp create_volunteer(%{conn: conn}) do
    user = user_fixture(%{role: "volunteer"})
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "Admin Dashboard" do
    setup [:create_admin]

    test "renders dashboard overview", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Overview"
      assert html =~ "Applications"
      assert html =~ "Financials"
    end

    test "shows admin stats row for admin users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#admin-stats-row")
      refute has_element?(view, "#volunteer-stats-row")
    end

    test "shows admin dashboard sections and event timeline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#dashboard-events-timeline")
      assert has_element?(view, "#dashboard-financials")
      assert has_element?(view, "#dashboard-newsletters")
      assert has_element?(view, "#dashboard-recent-discussions")
    end

    test "event check-in link joins open membership session", %{
      conn: conn,
      user: admin
    } do
      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Dashboard Check-in Join",
          start_date:
            DateTime.add(DateTime.utc_now(), 2, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 3, :day)
            |> DateTime.truncate(:second)
        })

      session = event_membership_session_fixture(event, admin)

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert render(view) =~ "Dashboard Check-in Join"

      assert has_element?(
               view,
               "#dashboard-event-#{event.id}-check-in[href='/admin/membership-check-in/#{session.id}']"
             )

      refute has_element?(
               view,
               "#dashboard-event-#{event.id}-check-in[href='/admin/events/#{event.id}/check-in']"
             )
    end

    test "navigates to user review from pending applications", %{conn: conn} do
      pending_user =
        user_fixture(%{
          state: "pending_approval",
          first_name: "Pending",
          last_name: "User"
        })

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert render(view) =~ "Pending User"

      view
      |> element(
        "#review-applications-section button[phx-value-user-id=\"#{pending_user.id}\"]",
        "Review"
      )
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

    test "shows empty pending applications state when queue is empty", %{
      conn: conn
    } do
      # Other tests in this module (or the suite) may leave users in pending_approval;
      # ExUnit order is random, so normalize before asserting the empty UI.
      Repo.update_all(from(u in User, where: u.state == :pending_approval),
        set: [state: :active]
      )

      {:ok, view, _html} = live(conn, ~p"/admin")
      html = render(view)

      assert html =~ "Review applications"
      assert html =~ "No pending applications"
    end

    test "shows overdue application styling when signup was completed long ago",
         %{
           conn: conn
         } do
      pending =
        oauth_user_fixture(%{
          state: :pending_approval,
          first_name: "Slow",
          last_name: "Applicant"
        })

      app = signup_application_fixture(pending)

      hours_ago =
        DateTime.utc_now()
        |> DateTime.add(-80, :hour)
        |> DateTime.truncate(:second)

      app
      |> Ecto.Changeset.change(%{completed: hours_ago})
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/admin")
      _ = render(view)
      html = render(view)

      assert html =~ "Slow Applicant"
      assert html =~ "Review Now"
      assert html =~ "Overdue"
    end
  end

  describe "volunteer dashboard" do
    setup [:create_volunteer]

    test "shows volunteer stats row instead of admin metrics", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#volunteer-stats-row")
      refute has_element?(view, "#admin-stats-row")
      assert has_element?(view, "#dashboard-events-timeline")
      refute has_element?(view, "#dashboard-financials")
    end

    test "shows volunteer shortcuts to events, posts, and newsletters", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/admin")
      html = render(view)

      assert html =~ "Upcoming Events"
      assert html =~ "News &amp; Posts"
      assert html =~ "Newsletters"
      assert html =~ "Manage events"
      assert html =~ "Manage posts"
      assert html =~ "Manage newsletters"
    end
  end
end
