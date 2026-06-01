defmodule YscWeb.AdminEventsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Events

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "Admin Events" do
    setup [:create_admin]

    test "lists events", %{conn: conn, admin: admin} do
      event_fixture(%{title: "Grand Viking Feast", organizer_id: admin.id})

      {:ok, _view, html} = live(conn, ~p"/admin/events")
      assert html =~ "Events"
      assert html =~ "Grand Viking Feast"
    end

    test "navigates to new event page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/events")

      view
      |> element(~s|a[href="/admin/events/new"]|)
      |> render_click()

      assert_redirected(view, ~p"/admin/events/new")
    end

    test "navigates to QR scanner", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/events")

      view
      |> element(~s|a[href="/admin/scanner"]|)
      |> render_click()

      assert_redirected(view, ~p"/admin/scanner")
    end

    test "navigates to edit event page", %{conn: conn, admin: admin} do
      event = event_fixture(%{title: "Edit Me", organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events")

      view
      |> element("#admin_events_list a[href*=\"#{event.id}/edit\"]")
      |> render_click()

      assert_redirected(view, ~p"/admin/events/#{event.id}/edit")
    end

    test "patch switches to drafts tab", %{conn: conn, admin: admin} do
      draft_title = "Draft Only #{System.unique_integer([:positive])}"

      {:ok, _} =
        %Events.Event{}
        |> Events.Event.changeset(%{
          title: draft_title,
          description: "Draft description",
          state: :draft,
          organizer_id: admin.id,
          published_at: nil,
          start_date:
            DateTime.add(DateTime.utc_now(), 5, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 6, :day)
            |> DateTime.truncate(:second),
          max_attendees: 50
        })
        |> Ysc.Repo.insert()

      {:ok, _view, html} = live(conn, ~p"/admin/events?tab=drafts")
      assert html =~ draft_title
    end

    test "patch switches to past tab", %{conn: conn, admin: admin} do
      past_title = "Past Tab Event #{System.unique_integer([:positive])}"

      event_fixture(%{
        title: past_title,
        organizer_id: admin.id,
        start_date: DateTime.add(DateTime.utc_now(), -3, :day),
        end_date: DateTime.add(DateTime.utc_now(), -2, :day),
        state: :published
      })

      {:ok, view, _html} = live(conn, ~p"/admin/events?tab=past")
      html = render(view)
      assert html =~ past_title
    end

    test "search patches URL with title filter", %{conn: conn, admin: admin} do
      event_fixture(%{title: "UniqueSearchXYZ", organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events")

      _html =
        view
        |> form("#events-search-form", %{q: "UniqueSearchXYZ"})
        |> render_submit()

      assert_patch(
        view,
        ~p"/admin/events?filters[0][field]=title&filters[0][op]=ilike&filters[0][value]=UniqueSearchXYZ&tab=upcoming"
      )
    end

    test "invalid flop params redirect to default events list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/events"}}} =
               live(conn, ~p"/admin/events?order_by=not_a_real_field")
    end

    test "check-in link joins open membership session for the event", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{title: "Check-in Join Test", organizer_id: admin.id})

      session = event_membership_session_fixture(event, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/events")

      assert html =~ ~p"/admin/membership-check-in/#{session.id}"
      refute html =~ ~s|href="/admin/events/#{event.id}/check-in"|
    end

    test "check-in link uses ticket desk when no open session exists", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{title: "Check-in Default Test", organizer_id: admin.id})

      {:ok, _view, html} = live(conn, ~p"/admin/events")

      assert html =~ ~p"/admin/events/#{event.id}/check-in"
    end

    test "copy event creates a draft and redirects to edit the new event", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{title: "To Copy", organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events")

      view
      |> element(
        "#admin_events_list button[phx-click='copy-event'][phx-value-id='#{event.id}']"
      )
      |> render_click()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r|/admin/events/[^/]+/edit|

      # Copied event should exist as draft with "Copy of" title
      [copied] =
        Events.list_events(%{}) |> Enum.filter(&(&1.title == "Copy of To Copy"))

      assert copied.state == :draft
    end
  end
end
