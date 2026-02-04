defmodule YscWeb.AdminEventsLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

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
      |> element("button", "New Event")
      |> render_click()

      assert_redirected(view, ~p"/admin/events/new")
    end

    test "navigates to edit event page", %{conn: conn, admin: admin} do
      event = event_fixture(%{title: "Edit Me", organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events")

      view
      |> element("#admin_events_list button", "Edit")
      |> render_click()

      assert_redirected(view, ~p"/admin/events/#{event.id}/edit")
    end
  end
end
