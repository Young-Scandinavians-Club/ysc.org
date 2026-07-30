defmodule YscWeb.AdminMembershipCheckInLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Repo
  alias Ysc.Scanning

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp make_active_member do
    user = user_fixture()

    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
    |> Repo.reload!()
  end

  defp make_inactive_member do
    user_fixture()
  end

  defp setup_session(admin) do
    event = event_fixture(%{organizer_id: admin.id})
    session = event_membership_session_fixture(event, admin)
    %{event: event, session: session}
  end

  # ---------------------------------------------------------------------------
  # Access control
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated users", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/membership-check-in/#{session.id}")

      assert path =~ "/users/log"
    end

    test "redirects regular members to home", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)

      member = user_fixture()
      conn = log_in_user(conn, member)

      assert {:error, {:redirect, _}} =
               live(conn, ~p"/admin/membership-check-in/#{session.id}")
    end
  end

  # ---------------------------------------------------------------------------
  # Page renders
  # ---------------------------------------------------------------------------

  describe "page renders" do
    setup [:create_admin]

    test "shows session name and checked-in count", %{conn: conn, admin: admin} do
      %{session: session} = setup_session(admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      assert has_element?(view, "#member-search-form")
      assert has_element?(view, "#checked-in-members")
    end

    test "shows the QR Scanner button", %{conn: conn, admin: admin} do
      %{session: session} = setup_session(admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      assert has_element?(view, "#launch-scanner-btn")
    end

    test "shows the Share/copy button", %{conn: conn, admin: admin} do
      %{session: session} = setup_session(admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      assert has_element?(view, "#copy-url-btn")
    end

    test "hides keyboard shortcut hints until the user searches", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      html = render(view)
      refute html =~ "quick check in"
      refute html =~ ~s(data-key="alt")
    end

    test "hides keyboard hints and search results when q param is empty", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}?q=")

      html = render(view)
      refute html =~ "Search Results"
      refute html =~ "quick check in"
      refute html =~ ~s(data-key="alt")
    end
  end

  describe "deferred check-in loading" do
    setup [:create_admin]

    test "initial connect issues at most one membership check-in list query", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)
      member = make_active_member()
      {:ok, _} = Scanning.check_in_member(session, member, admin)

      check_ins_pattern = ~r/FROM "session_check_ins"/i

      {{:ok, view, _html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} =
              live(conn, ~p"/admin/membership-check-in/#{session.id}")

            Ysc.QueryCounter.track_caller_pid(view.pid)
            render(view)
            {:ok, view, html}
          end,
          pattern: check_ins_pattern,
          caller_pids: [self()]
        )

      assert query_count <= 1
      assert has_element?(view, "#checked-in-members")
    end
  end

  # ---------------------------------------------------------------------------
  # Search
  # ---------------------------------------------------------------------------

  describe "search" do
    setup [:create_admin]

    test "shows search results when query is present", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)
      member = make_active_member()

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      view
      |> element("#member-search-form")
      |> render_change(%{"q" => member.email})

      patched_path = assert_patch(view)
      assert patched_path =~ "q="
    end

    test "shows active membership badge for member with active membership", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)
      member = make_active_member()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/membership-check-in/#{session.id}?q=#{URI.encode(member.email)}"
        )

      assert has_element?(view, "#search-results-list")

      assert has_element?(
               view,
               "#search-result-#{member.id}",
               member.first_name
             )

      html = render(view)
      assert html =~ ~s(data-key="alt")
      assert html =~ "quick check in"
    end

    test "shows inactive membership for user without membership", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)
      inactive = make_inactive_member()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/membership-check-in/#{session.id}?q=#{URI.encode(inactive.email)}"
        )

      assert has_element?(view, "#search-results-list")

      assert has_element?(
               view,
               "#search-result-#{inactive.id}",
               "NO MEMBERSHIP"
             )
    end
  end

  # ---------------------------------------------------------------------------
  # Check-in actions
  # ---------------------------------------------------------------------------

  describe "check-in actions" do
    setup [:create_admin]

    test "checking in an active member adds them to the checked-in stream", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)
      member = make_active_member()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/membership-check-in/#{session.id}?q=#{URI.encode(member.email)}"
        )

      view
      |> element(
        "#search-result-#{member.id} button[phx-click='check-in-member']"
      )
      |> render_click()

      assert has_element?(view, "#checked-in-members")
      assert has_element?(view, "#checked-in-members", member.first_name)

      assert Scanning.member_checked_in?(session.id, member.id)
    end

    test "checking in an inactive user shows an error flash", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)
      inactive = make_inactive_member()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/membership-check-in/#{session.id}?q=#{URI.encode(inactive.email)}"
        )

      refute has_element?(
               view,
               "#search-result-#{inactive.id} [phx-click='check-in-member']"
             )
    end

    test "undoing a check-in removes the member from the list", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)
      member = make_active_member()

      {:ok, _check_in} = Scanning.check_in_member(session, member, admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      assert has_element?(
               view,
               "button[phx-click='undo-check-in'][phx-value-user-id='#{member.id}']"
             )

      view
      |> element(
        "button[phx-click='undo-check-in'][phx-value-user-id='#{member.id}']"
      )
      |> render_click()

      refute Scanning.member_checked_in?(session.id, member.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Real-time collaboration via PubSub
  # ---------------------------------------------------------------------------

  describe "real-time collaboration" do
    setup [:create_admin]

    test "second admin joining the session sees real-time check-ins", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)
      member = make_active_member()

      admin2 = user_fixture(%{role: "admin"})
      conn2 = log_in_user(build_conn(), admin2)

      {:ok, view1, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      {:ok, view2, _html} =
        live(conn2, ~p"/admin/membership-check-in/#{session.id}")

      {:ok, _} = Scanning.check_in_member(session, member, admin)

      assert has_element?(view1, "#checked-in-members", member.first_name)
      assert has_element?(view2, "#checked-in-members", member.first_name)
    end
  end

  # ---------------------------------------------------------------------------
  # Closed session authorization
  # ---------------------------------------------------------------------------

  describe "closed session authorization" do
    test "another admin cannot open a closed membership check-in desk", %{
      conn: conn
    } do
      owner = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: owner.id})
      session = event_membership_session_fixture(event, owner)
      member = make_active_member()
      {:ok, _} = Scanning.check_in_member(session, member, owner)
      {:ok, _} = Scanning.close_session(session.id)

      other_admin = user_fixture(%{role: "admin"})
      conn = log_in_user(conn, other_admin)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/admin/membership-check-in/#{session.id}")

      assert to == ~p"/admin/scanner/sessions"
    end

    test "session creator can still open a closed membership check-in desk", %{
      conn: conn
    } do
      owner = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: owner.id})
      session = event_membership_session_fixture(event, owner)
      {:ok, _} = Scanning.close_session(session.id)

      conn = log_in_user(conn, owner)

      assert {:ok, view, _html} =
               live(conn, ~p"/admin/membership-check-in/#{session.id}")

      assert has_element?(view, "#export-csv-btn")
    end

    test "another admin cannot export CSV from a closed membership check-in desk",
         %{
           conn: conn
         } do
      owner = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: owner.id})
      session = event_membership_session_fixture(event, owner)
      member = make_active_member()
      {:ok, _} = Scanning.check_in_member(session, member, owner)
      {:ok, _} = Scanning.close_session(session.id)

      other_admin = user_fixture(%{role: "admin"})
      conn = log_in_user(conn, other_admin)

      assert {:error, {:live_redirect, _}} =
               live(conn, ~p"/admin/membership-check-in/#{session.id}")
    end

    test "redirects when session does not exist", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      conn = log_in_user(conn, admin)
      missing_id = Ecto.ULID.generate()

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/admin/membership-check-in/#{missing_id}")

      assert to == ~p"/admin/scanner/sessions"
    end

    test "creator can export CSV from a closed membership check-in desk", %{
      conn: conn
    } do
      owner = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: owner.id})
      session = event_membership_session_fixture(event, owner)
      member = make_active_member()
      {:ok, _} = Scanning.check_in_member(session, member, owner)
      {:ok, _} = Scanning.close_session(session.id)
      conn = log_in_user(conn, owner)

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      view
      |> element("#export-csv-btn")
      |> render_click()

      assert_push_event(view, "download-csv", %{content: _b64, filename: fname})
      assert fname =~ "membership_checkin_#{session.id}"
    end

    test "non-owner gets error flash when exporting CSV after session closes",
         %{
           conn: conn
         } do
      owner = user_fixture(%{role: "admin"})
      other_admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: owner.id})
      session = event_membership_session_fixture(event, owner)
      conn = log_in_user(conn, other_admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      {:ok, _} = Scanning.close_session(session.id)

      html =
        view
        |> element("#export-csv-btn")
        |> render_click()

      assert html =~
               "You can only export membership check-in sessions you created after they are closed."
    end
  end

  # ---------------------------------------------------------------------------
  # Launch QR scanner
  # ---------------------------------------------------------------------------

  describe "launch scanner" do
    setup [:create_admin]

    test "clicking QR Scanner button navigates to scanner with resume param", %{
      conn: conn,
      admin: admin
    } do
      %{session: session} = setup_session(admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/membership-check-in/#{session.id}")

      {:error, {:live_redirect, %{to: to}}} =
        view
        |> element("#launch-scanner-btn")
        |> render_click()

      assert to =~ "/admin/scanner"
      assert to =~ session.id
    end
  end
end
