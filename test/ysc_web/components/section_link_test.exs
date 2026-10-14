defmodule YscWeb.Components.SectionLinkTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias YscWeb.CoreComponents

  describe "section_link/1" do
    test "renders a link with a 44px tap area when given navigate" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.section_link id="sl-link" navigate="/events">
          View All Events
        </CoreComponents.section_link>
        """)

      assert html =~ ~s(href="/events")
      assert html =~ "View All Events"
      assert html =~ "min-h-11"
      refute html =~ "<button"
    end

    test "renders a button when no destination is given" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.section_link id="sl-btn" phx-click="toggle">
          Turn off
        </CoreComponents.section_link>
        """)

      assert html =~ "<button"
      assert html =~ ~s(type="button")
      assert html =~ ~s(phx-click="toggle")
      assert html =~ "min-h-11"
    end
  end
end
