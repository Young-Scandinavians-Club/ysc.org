defmodule YscWeb.AdminHelpGhostLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{role: "volunteer"})
    %{conn: log_in_user(conn, user)}
  end

  test "renders a ghost preview with real admin chrome", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/help/ghost/posts-list?embed=1")

    assert html =~ "admin-help-ghost-embed"
    assert html =~ "Posts"
    assert html =~ "New Post"
    assert html =~ "admin-ghost-bar"
    assert has_element?(view, "#admin-navigation")
  end

  test "public site ghost preview has no admin sidebar", %{conn: conn} do
    {:ok, _view, html} =
      live(conn, ~p"/admin/help/ghost/getting-started-dashboard?embed=1")

    refute html =~ "admin-navigation"
    assert html =~ "ghost-admin-fab"
  end

  test "collapsed sidebar query param renders narrow sidebar", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie("admin_sb_collapsed", "0")
      |> get(~p"/admin/help/ghost/posts-list?embed=1&sidebar_collapsed=1")

    assert html_response(conn, 200) =~ "sidebar-collapsed"
  end

  test "events edit ghost shows editor header, sections, and agenda", %{
    conn: conn
  } do
    {:ok, _view, html} =
      live(conn, ~p"/admin/help/ghost/events-edit?embed=1")

    assert html =~ "ghost-event-header-bar"
    assert html =~ "ghost-event-detail-tabs"
    assert html =~ "Publish"
    assert html =~ "Event Details"
    assert html =~ "ghost-event-agenda-section"
    assert html =~ "ghost-add-agenda-button"
    assert html =~ "Add Agenda"
  end

  test "events tickets ghost shows header and tier cards", %{conn: conn} do
    {:ok, _view, html} =
      live(conn, ~p"/admin/help/ghost/events-tickets?embed=1")

    assert html =~ "ghost-event-header-bar"
    assert html =~ "Tickets"
    assert html =~ "Event Capacity"
    assert html =~ "ghost-add-ticket-tier"
    assert html =~ "Member"
  end

  test "public event tickets ghost shows sidebar pricing", %{conn: conn} do
    {:ok, _view, html} =
      live(conn, ~p"/admin/help/ghost/public-event-tickets?embed=1")

    assert html =~ "ghost-public-ticket-sidebar"
    assert html =~ "From $20"
    assert html =~ "48 Spots Available"
    assert html =~ "ghost-public-get-tickets"
  end

  test "public event ticket tiers ghost shows modal with tiers", %{conn: conn} do
    {:ok, _view, html} =
      live(conn, ~p"/admin/help/ghost/public-event-ticket-tiers?embed=1")

    assert html =~ "ghost-public-ticket-modal"
    assert html =~ "Member"
    assert html =~ "Guest"
    assert html =~ "Order Summary"
    assert html =~ "Continue to checkout"
  end

  test "public event tickets tbd ghost shows coming soon state", %{conn: conn} do
    {:ok, _view, html} =
      live(conn, ~p"/admin/help/ghost/public-event-tickets-tbd?embed=1")

    assert html =~ "Tickets Coming Soon"
    assert html =~ "Notify me when tickets open"
  end

  test "public event agenda ghost shows timeline", %{conn: conn} do
    {:ok, _view, html} =
      live(conn, ~p"/admin/help/ghost/public-event-agenda?embed=1")

    assert html =~ "ghost-public-event-agenda"
    assert html =~ "Doors open"
    assert html =~ "Dinner"
  end

  test "newsletter compose ghost shows editor and email preview columns", %{
    conn: conn
  } do
    {:ok, _view, html} =
      live(conn, ~p"/admin/help/ghost/newsletter-compose?embed=1")

    assert html =~ "Email Preview"
    assert html =~ "Shown as: Subscriber"
    assert html =~ "Club Updates"
    assert html =~ "Latest news (posts)"
    assert html =~ "ghost-newsletter-preview-panel"
  end

  test "member-facing ghost previews render public page chrome", %{conn: conn} do
    {:ok, _view, html} =
      live(conn, ~p"/admin/help/ghost/public-news-list?embed=1")

    refute html =~ "admin-navigation"
    assert html =~ "Club News"
    assert html =~ "ghost-new-post-card"
  end

  test "unknown preview redirects to help index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/help"}}} =
             live(conn, ~p"/admin/help/ghost/not-real")
  end
end
