defmodule YscWeb.AdminDashboardLinkCardTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_dashboard_link_card/1" do
    test "renders a navigable card with default accent, id, href, and footer CTA" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_dashboard_link_card
          id="volunteer-events-card"
          navigate="/admin/events"
          action="Manage events →"
        >
          <p>Upcoming Events</p>
        </.admin_dashboard_link_card>
        """)

      assert html =~ ~s(id="volunteer-events-card")
      assert html =~ ~s(href="/admin/events")
      assert html =~ "Upcoming Events"
      assert html =~ "Manage events →"
      assert html =~ "hover:ring-2"
      assert html =~ "hover:ring-zinc-300"
      assert html =~ "group-hover:underline"
      refute html =~ "border-amber-300"
    end

    test "applies warning accent for pending-application treatment" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_dashboard_link_card
          id="dashboard-applications-card"
          navigate="/admin/users"
          action="Review applications →"
          accent={:warning}
        >
          <p>Applications</p>
        </.admin_dashboard_link_card>
        """)

      assert html =~ ~s(id="dashboard-applications-card")
      assert html =~ "Applications"
      assert html =~ "Review applications →"
      assert html =~ "border-amber-300"
      assert html =~ "hover:ring-amber-200"
      refute html =~ "hover:ring-zinc-300"
    end

    test "renders a static card when navigate is omitted" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_dashboard_link_card action="Manage posts →">
          <p>News posts</p>
        </.admin_dashboard_link_card>
        """)

      assert html =~ "News posts"
      assert html =~ "Manage posts →"
      refute html =~ "href="
      refute html =~ "hover:ring-2"
      refute html =~ "group-hover:underline"
    end
  end
end
