defmodule YscWeb.VolunteerRoleTest do
  @moduledoc """
  Comprehensive tests for the volunteer admin role.

  Covers:
  - Access control: volunteers can reach allowed pages
  - Access control: volunteers are blocked from restricted pages
  - Dashboard differences between admin and volunteer
  - Sidebar navigation visibility per role
  - Floating admin button visibility
  - Role management (assigning volunteer role via admin UI)
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp create_volunteer(%{conn: conn}) do
    user = user_fixture(%{role: "volunteer"})
    %{conn: log_in_user(conn, user), volunteer: user}
  end

  # ---------------------------------------------------------------------------
  # Volunteer access: allowed pages
  # ---------------------------------------------------------------------------

  describe "volunteer access - allowed pages" do
    setup [:create_volunteer]

    test "can access admin dashboard", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Welcome back"
    end

    test "can access events list", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/events")
      assert html =~ "Events"
    end

    test "new event page creates an event and redirects to its edit page", %{
      conn: conn
    } do
      # Connected mount creates a draft and live-redirects to the edit page.
      # The HTTP dead render is a loading shell and does not insert.
      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/admin/events/new")

      assert path =~ "/admin/events/"
      assert path =~ "/edit"
    end

    test "can access posts list", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/posts")
      assert html =~ "Posts"
    end

    test "can access newsletters list", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/newsletters")
      assert html =~ "Newsletters"
    end

    test "can access new newsletter form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/newsletters/new")
      assert html =~ "Newsletter"
    end

    test "can access media gallery", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/media")
      assert html =~ "Media"
    end
  end

  # ---------------------------------------------------------------------------
  # Volunteer access: restricted pages redirect to /admin
  # ---------------------------------------------------------------------------

  describe "volunteer access - restricted pages" do
    setup [:create_volunteer]

    test "cannot access users list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin"}}} =
               live(conn, ~p"/admin/users")
    end

    test "cannot access memberships", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin"}}} =
               live(conn, ~p"/admin/memberships")
    end

    test "cannot access money management", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin"}}} =
               live(conn, ~p"/admin/money")
    end

    test "cannot access bookings", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin"}}} =
               live(conn, ~p"/admin/bookings")
    end

    test "cannot access settings", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin"}}} =
               live(conn, ~p"/admin/settings")
    end

    test "cannot impersonate users", %{conn: conn} do
      other_user = user_fixture()

      conn =
        conn
        |> get(~p"/admin")

      {conn, token} = fetch_conn_csrf_from_html(conn)

      conn =
        post(conn, ~p"/admin/impersonate/#{other_user.id}", %{
          "_csrf_token" => token
        })

      assert redirected_to(conn) == "/admin"
    end
  end

  # ---------------------------------------------------------------------------
  # Members are blocked from all admin pages
  # ---------------------------------------------------------------------------

  describe "member access - blocked from all admin pages" do
    test "cannot access admin dashboard", %{conn: conn} do
      member = user_fixture(%{role: "member", state: "active"})
      conn = log_in_user(conn, member)

      conn = get(conn, ~p"/admin")
      assert redirected_to(conn) == "/"
    end

    test "unauthenticated user cannot access admin", %{conn: conn} do
      conn = get(conn, ~p"/admin")
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end

  # ---------------------------------------------------------------------------
  # Dashboard: admin sees full stats
  # ---------------------------------------------------------------------------

  describe "admin dashboard - full admin view" do
    setup [:create_admin]

    test "shows admin stats row", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#admin-stats-row")
    end

    test "does not show volunteer stats row", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      refute has_element?(view, "#volunteer-stats-row")
    end

    test "shows review applications section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#review-applications-section")
    end

    test "shows events timeline section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#dashboard-events-timeline")
    end

    test "shows recent discussions section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#dashboard-recent-discussions")
    end
  end

  # ---------------------------------------------------------------------------
  # Dashboard: volunteer sees simplified view
  # ---------------------------------------------------------------------------

  describe "admin dashboard - volunteer view" do
    setup [:create_volunteer]

    test "does not show admin stats row", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      refute has_element?(view, "#admin-stats-row")
    end

    test "shows volunteer stats row", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#volunteer-stats-row")
    end

    test "does not show review applications section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      refute has_element?(view, "#review-applications-section")
    end

    test "shows events timeline section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#dashboard-events-timeline")
    end

    test "shows recent discussions section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#dashboard-recent-discussions")
    end

    test "volunteer stats row contains events, posts, and newsletters links", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#volunteer-stats-row a[href='/admin/events']")
      assert has_element?(view, "#volunteer-stats-row a[href='/admin/posts']")

      assert has_element?(
               view,
               "#volunteer-stats-row a[href='/admin/newsletters']"
             )
    end
  end

  # ---------------------------------------------------------------------------
  # Sidebar navigation visibility
  # ---------------------------------------------------------------------------

  describe "sidebar navigation - admin" do
    setup [:create_admin]

    test "shows standard admin nav items", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/users']")

      refute has_element?(
               view,
               "#admin-sidebar-menu-scroll a[href='/admin/memberships']"
             )

      assert has_element?(view, "a[href='/admin/bookings']")
      assert has_element?(view, "a[href='/admin/posts']")
      assert has_element?(view, "a[href='/admin/events']")
      assert has_element?(view, "a[href='/admin/newsletters']")
      assert has_element?(view, "a[href='/admin/media']")
    end

    test "shows memberships nav only for membership director board role", %{
      conn: conn
    } do
      admin =
        user_fixture(%{
          role: "admin",
          board_position: :membership_director
        })

      conn = log_in_user(conn, admin)

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(
               view,
               "#admin-sidebar-menu-scroll a[href='/admin/memberships']"
             )
    end
  end

  describe "sidebar navigation - volunteer" do
    setup [:create_volunteer]

    test "shows content nav items", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "a[href='/admin/posts']")
      assert has_element?(view, "a[href='/admin/events']")
      assert has_element?(view, "a[href='/admin/newsletters']")
      assert has_element?(view, "a[href='/admin/media']")
    end

    test "does not show restricted nav items", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      refute has_element?(view, "a[href='/admin/users']")

      refute has_element?(
               view,
               "#admin-sidebar-menu-scroll a[href='/admin/memberships']"
             )

      refute has_element?(view, "a[href='/admin/bookings']")
    end
  end

  # ---------------------------------------------------------------------------
  # Floating admin button (root layout)
  # ---------------------------------------------------------------------------

  describe "floating admin button" do
    test "visible to admin users", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "admin-floating-button-wrap"
    end

    test "visible to volunteer users", %{conn: conn} do
      volunteer = user_fixture(%{role: "volunteer"})
      conn = log_in_user(conn, volunteer)

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "admin-floating-button-wrap"
    end

    test "not visible to regular members", %{conn: conn} do
      member = user_fixture(%{role: "member", state: "active"})
      conn = log_in_user(conn, member)

      {:ok, _view, html} = live(conn, ~p"/")
      refute html =~ "admin-floating-button-wrap"
    end

    test "not visible when logged out", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      refute html =~ "admin-floating-button-wrap"
    end
  end

  # ---------------------------------------------------------------------------
  # Role management: admin can assign volunteer role
  # ---------------------------------------------------------------------------

  describe "role management in admin users list" do
    setup [:create_admin]

    test "volunteer option available in role filter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "Volunteer"
    end

    test "filtering by volunteer role shows only volunteers", %{conn: conn} do
      volunteer =
        user_fixture(%{
          role: "volunteer",
          first_name: "Vol",
          last_name: "Unteer"
        })

      _member =
        user_fixture(%{
          role: "member",
          first_name: "Regular",
          last_name: "Member"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      html =
        view
        |> element("#user-filter-form")
        |> render_change(%{
          filters: %{
            "0" => %{
              "_persistent_id" => "0",
              "field" => "role",
              "op" => "in",
              "value" => ["volunteer"]
            }
          }
        })

      assert html =~ "Vol Unteer"
      refute html =~ "Regular Member"

      assert Ysc.Accounts.get_user!(volunteer.id).role == :volunteer
    end
  end

  # ---------------------------------------------------------------------------
  # Role management: admin user detail page
  # ---------------------------------------------------------------------------

  describe "role management in admin user detail page" do
    setup [:create_admin]

    test "volunteer option visible in role dropdown", %{conn: conn} do
      target_user = user_fixture(%{role: "member"})

      {:ok, _view, html} =
        live(conn, ~p"/admin/users/#{target_user.id}/details")

      assert html =~ "volunteer"
    end

    test "board position field hidden when role is volunteer", %{conn: conn} do
      target_user = user_fixture(%{role: "volunteer"})

      {:ok, _view, html} =
        live(conn, ~p"/admin/users/#{target_user.id}/details")

      refute html =~ "Board Position"
    end

    test "board position field shown when role is admin", %{conn: conn} do
      target_user = user_fixture(%{role: "admin"})

      {:ok, _view, html} =
        live(conn, ~p"/admin/users/#{target_user.id}/details")

      assert html =~ "Board Position"
    end

    test "board bio field shown when admin user holds a board seat", %{
      conn: conn
    } do
      target_user = user_fixture(%{role: "admin"})

      {:ok, target_user} =
        Ysc.Accounts.assign_board_position(target_user, :secretary)

      {:ok, view, _html} =
        live(conn, ~p"/admin/users/#{target_user.id}/details")

      assert has_element?(view, "#board_bio")
      assert has_element?(view, ~s(label[for="board_bio"]))
    end

    test "board bio field hidden when admin user has no board seat", %{
      conn: conn
    } do
      target_user = user_fixture(%{role: "admin"})

      {:ok, view, _html} =
        live(conn, ~p"/admin/users/#{target_user.id}/details")

      refute has_element?(view, "#board_bio")
    end
  end

  # ---------------------------------------------------------------------------
  # Volunteer cannot access user detail pages
  # ---------------------------------------------------------------------------

  describe "volunteer access - user detail pages" do
    setup [:create_volunteer]

    test "redirected from user detail page", %{conn: conn} do
      other_user = user_fixture()

      assert {:error, {:redirect, %{to: "/admin"}}} =
               live(conn, ~p"/admin/users/#{other_user.id}/details")
    end
  end
end
