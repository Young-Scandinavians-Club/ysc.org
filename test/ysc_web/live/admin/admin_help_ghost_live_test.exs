defmodule YscWeb.AdminHelpGhostLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{role: "volunteer"})
    %{conn: log_in_user(conn, user)}
  end

  test "renders a ghost preview with real admin chrome", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/ghost/posts-list?embed=1")

    assert has_element?(view, ".admin-help-ghost-embed")
    assert has_element?(view, "h1", "Posts")
    assert has_element?(view, "#ghost-new-post", "New Post")
    assert has_element?(view, ".admin-ghost-bar")
    assert has_element?(view, "#admin-navigation")
  end

  test "public site ghost preview has no admin sidebar", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/getting-started-login?embed=1")

    refute has_element?(view, "#admin-navigation")
    assert has_element?(view, "#ghost-admin-fab")
  end

  test "dashboard ghost matches volunteer admin dashboard layout", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/getting-started-dashboard?embed=1")

    assert has_element?(view, "#admin-navigation")
    assert has_element?(view, "#ghost-admin-dashboard")
    assert has_element?(view, "h1", "Welcome back, Alex")
    assert has_element?(view, "#ghost-admin-search")
    assert has_element?(view, "#volunteer-help-banner", "Volunteer guides")
    assert has_element?(view, "#volunteer-stats-row", "Upcoming Events")
    assert has_element?(view, "#volunteer-stats-row", "News & Posts")
    assert has_element?(view, "#dashboard-events-timeline", "Upcoming events")

    assert has_element?(
             view,
             "#ghost-dashboard-event-primary",
             "Summer Cabin Weekend"
           )

    assert has_element?(
             view,
             "#dashboard-recent-discussions",
             "Recent discussions"
           )
  end

  test "collapsed sidebar query param renders narrow sidebar", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie("admin_sb_collapsed", "0")
      |> get(~p"/admin/help/ghost/posts-list?embed=1&sidebar_collapsed=1")

    assert html_response(conn, 200) =~ "sidebar-collapsed"
  end

  test "posts list ghost shows table with actions menu", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/posts-list?embed=1")

    assert has_element?(view, "#ghost-new-post", "New Post")
    assert has_element?(view, "#ghost-posts-table", "Title")
    assert has_element?(view, "#ghost-posts-actions")
    assert has_element?(view, "#ghost-posts-actions-menu", "Pin post")
  end

  test "posts editor ghost matches post editor layout", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/posts-editor?embed=1")

    assert has_element?(view, "#ghost-post-editor-title", "Midsummer 2026")

    assert has_element?(
             view,
             "#ghost-post-editor-url",
             "midsummer-2026-photos-and-thanks"
           )

    assert has_element?(
             view,
             "#ghost-post-editor-body-toolbar .trix-button--icon-library"
           )

    assert has_element?(view, "button", "Publish")
    assert has_element?(view, "#ghost-post-editor-menu")
  end

  test "events list ghost shows table of events", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/events-list?embed=1")

    assert has_element?(view, "#ghost-new-event", "New Event")
    assert has_element?(view, "#ghost-events-table", "Title")
    assert has_element?(view, "#ghost-events-table", "Registrations")
    assert has_element?(view, "#ghost-events-table", "Published")
    assert has_element?(view, "#ghost-events-table", "Draft")
    assert has_element?(view, "#ghost-events-actions")
    assert has_element?(view, "#ghost-events-actions-menu", "Copy")
    assert has_element?(view, "#ghost-events-actions-menu", "Delete")
  end

  test "events edit ghost shows editor header, sections, and agenda", %{
    conn: conn
  } do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/events-edit?embed=1")

    assert has_element?(view, "#ghost-event-header-bar")
    assert has_element?(view, "#ghost-event-detail-tabs")
    assert has_element?(view, "button", "Publish")
    assert has_element?(view, "#ghost-event-detail-tabs", "Event Details")
    assert has_element?(view, "#ghost-event-overview-section", "Overview")

    assert has_element?(
             view,
             "#ghost-event-overview-editor-toolbar .trix-button--icon-library"
           )

    assert has_element?(
             view,
             "#ghost-event-overview-editor-body",
             "What to expect"
           )

    assert has_element?(view, "#ghost-event-agenda-section")
    assert has_element?(view, "#ghost-add-agenda-button", "Add Agenda")
  end

  test "events tickets ghost shows header and tier cards", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/events-tickets?embed=1")

    assert has_element?(view, "#ghost-event-header-bar")
    assert has_element?(view, "#ghost-event-detail-tabs", "Tickets")
    assert has_element?(view, "h2", "Event Capacity")
    assert has_element?(view, "#ghost-add-ticket-tier")
    assert has_element?(view, "h4", "Member")
  end

  test "public event tickets ghost shows sidebar pricing", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/public-event-tickets?embed=1")

    assert has_element?(view, "#ghost-public-ticket-sidebar")
    assert has_element?(view, "#ghost-public-ticket-sidebar", "From $20")

    assert has_element?(
             view,
             "#ghost-public-ticket-sidebar",
             "48 Spots Available"
           )

    assert has_element?(view, "#ghost-public-get-tickets")
  end

  test "public event ticket tiers ghost shows modal with tiers", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/public-event-ticket-tiers?embed=1")

    assert has_element?(view, "#ghost-public-ticket-modal")
    assert has_element?(view, "#ghost-public-ticket-modal", "Member")
    assert has_element?(view, "#ghost-public-ticket-modal", "Guest")
    assert has_element?(view, "#ghost-public-ticket-modal", "Order Summary")

    assert has_element?(
             view,
             "#ghost-public-ticket-modal",
             "Continue to checkout"
           )
  end

  test "public event tickets tbd ghost shows coming soon state", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/public-event-tickets-tbd?embed=1")

    assert has_element?(
             view,
             "#ghost-public-ticket-sidebar",
             "Tickets Coming Soon"
           )

    assert has_element?(
             view,
             "#ghost-public-ticket-sidebar",
             "Notify me when tickets open"
           )
  end

  test "public event page ghost lists hosts in attendees section", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/public-event-page?embed=1")

    assert has_element?(view, "#ghost-public-event-details", "Details")
    assert has_element?(view, "#ghost-public-event-attendees", "Attendees")
    assert has_element?(view, "#ghost-public-event-hosts", "Host")
    refute render(view) =~ "Hosted by"
    refute has_element?(view, "h1", "Event")
  end

  test "public event updates ghost shows update cards on the event page", %{
    conn: conn
  } do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/public-event-updates?embed=1")

    assert has_element?(view, "#ghost-event-updates-section", "Updates")

    assert has_element?(
             view,
             "#ghost-event-updates-section",
             "Parking entrance has changed"
           )

    assert has_element?(view, "#ghost-event-updates-section", "What to bring")

    assert has_element?(
             view,
             "#ghost-event-updates-section",
             "Posted by Alex Volunteer"
           )

    assert has_element?(view, "#ghost-public-ticket-sidebar")
  end

  test "public event agenda ghost shows timeline", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/public-event-agenda?embed=1")

    assert has_element?(view, "#ghost-public-event-agenda")
    assert has_element?(view, "#ghost-public-event-agenda", "Doors open")
    assert has_element?(view, "#ghost-public-event-agenda", "Dinner")
  end

  test "scanner ghost shows setup panel and phone scan UI", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/scanner?embed=1")

    refute has_element?(view, "#admin-navigation")
    assert has_element?(view, "#ghost-scanner", "Check-in & Scan")

    assert has_element?(
             view,
             "#ghost-scanner-resume",
             "Resume an Active Session"
           )

    assert has_element?(
             view,
             "#ghost-scanner-setup",
             "Start a Check-in Session"
           )

    assert has_element?(view, "#ghost-scanner-setup", "Start Session")
    assert has_element?(view, "#ghost-scanner-phone")

    assert has_element?(
             view,
             "#ghost-scanner-viewfinder",
             "Point camera at a QR code"
           )

    assert has_element?(view, "#ghost-scanner-result", "Checked In")
    assert has_element?(view, "#ghost-scanner-result", "Jamie Member")
  end

  test "event check-in desk ghost matches full-width check-in layout", %{
    conn: conn
  } do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/check-in-desk?embed=1")

    refute has_element?(view, "#admin-navigation")
    assert has_element?(view, "#ghost-event-check-in-desk")
    assert has_element?(view, "h1", "Summer Cabin Weekend")
    assert has_element?(view, "#ghost-check-in-counter", "12 / 48")
    assert has_element?(view, "#ghost-check-in-search-input")
    assert has_element?(view, "#ghost-check-in-pending", "Pending")
    assert has_element?(view, "#ghost-check-in-order-all", "Check in all")
    assert has_element?(view, "#ghost-check-in-pending", "ORD-2026-AB12")
    assert has_element?(view, "#ghost-check-in-checked-in", "Checked In")
    assert has_element?(view, "button", "QR Scanner")
  end

  test "newsletter subscribers ghost shows toolbar and table", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/newsletter-subscribers?embed=1")

    assert has_element?(view, "#ghost-subscribers-search")
    assert has_element?(view, "#ghost-subscribers-filters", "Active")
    assert has_element?(view, "#ghost-add-subscriber", "Add subscriber")
    assert has_element?(view, "#ghost-subscribers-table", "Email")
    assert has_element?(view, "#ghost-subscribers-table", "jamie@example.com")
  end

  test "newsletter compose ghost shows editor and email preview columns", %{
    conn: conn
  } do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/newsletter-compose?embed=1")

    assert has_element?(view, "h3", "Email Preview")

    assert has_element?(
             view,
             "#ghost-newsletter-email-preview",
             "Shown as: Subscriber"
           )

    assert has_element?(view, "#ghost-newsletter-email-preview", "Club Updates")

    assert has_element?(
             view,
             "#ghost-newsletter-post-picker",
             "Latest news (posts)"
           )

    assert has_element?(view, "#ghost-newsletter-preview-panel")
    assert has_element?(view, "#ghost-newsletter-send-test", "Send test")
  end

  test "member-facing ghost previews render public page chrome", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/ghost/public-news-list?embed=1")

    refute has_element?(view, "#admin-navigation")
    assert has_element?(view, "h1", "Club News")
    assert has_element?(view, "#ghost-new-post-card")
  end

  test "unknown preview redirects to help index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/help"}}} =
             live(conn, ~p"/admin/help/ghost/not-real")
  end
end
