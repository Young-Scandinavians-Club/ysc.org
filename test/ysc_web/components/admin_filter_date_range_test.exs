defmodule YscWeb.AdminFilterDateRangeTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_filter_date_range/1" do
    test "renders labeled From/To date inputs with prefixed ids" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_filter_date_range
          id="filter-newsletters"
          label="Date Created"
          date_from="2026-01-01"
          date_to="2026-03-31"
        />
        """)

      assert html =~ "Date Created"
      assert html =~ ~s(id="filter-newsletters-date-from")
      assert html =~ ~s(id="filter-newsletters-date-to")
      assert html =~ ~s(name="date_from")
      assert html =~ ~s(name="date_to")
      assert html =~ ~s(type="date")
      assert html =~ "From"
      assert html =~ "To"
      assert html =~ "2026-01-01"
      assert html =~ "2026-03-31"
      assert html =~ "phx-debounce"
    end

    test "allows overriding submitted field names" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_filter_date_range
          id="filter-custom"
          label="Custom Range"
          from_name="starts_on"
          to_name="ends_on"
        />
        """)

      assert html =~ ~s(name="starts_on")
      assert html =~ ~s(name="ends_on")
      refute html =~ ~s(name="date_from")
      refute html =~ ~s(name="date_to")
    end
  end
end
