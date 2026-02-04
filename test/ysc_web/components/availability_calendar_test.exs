defmodule YscWeb.Components.AvailabilityCalendarTest do
  use YscWeb.ConnCase
  import Phoenix.LiveViewTest

  alias YscWeb.Components.AvailabilityCalendar

  describe "render" do
    test "renders calendar with current month" do
      today = Date.utc_today()
      current_month = Calendar.strftime(today, "%B %Y")

      html =
        render_component(AvailabilityCalendar,
          id: "calendar",
          today: today
        )

      assert html =~ current_month
      assert html =~ "Today"
    end
  end
end
