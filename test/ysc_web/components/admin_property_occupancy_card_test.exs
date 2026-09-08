defmodule YscWeb.AdminPropertyOccupancyCardTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  defp sample_stats(overrides) do
    Map.merge(
      %{
        staying: 0,
        checkins_today: 0,
        checkouts_today: 0,
        upcoming_bookings: 0,
        upcoming_guests: 0
      },
      overrides
    )
  end

  describe "admin_property_occupancy_card/1" do
    test "renders empty cabin with default view label and sky accent" do
      assigns = %{stats: sample_stats(%{})}

      html =
        rendered_to_string(~H"""
        <.admin_property_occupancy_card
          id="dashboard-property-tahoe"
          navigate="/admin/bookings?property=tahoe"
          label="Tahoe"
          accent={:sky}
          stats={@stats}
        />
        """)

      assert html =~ ~s(id="dashboard-property-tahoe")
      assert html =~ ~s(href="/admin/bookings?property=tahoe")
      assert html =~ "Tahoe"
      assert html =~ "text-sky-600"
      assert html =~ "group-hover:text-sky-600"
      assert html =~ "Empty"
      assert html =~ "bg-zinc-300"
      refute html =~ "Active"
      assert html =~ "staying now"
      assert html =~ "Checking in"
      assert html =~ "Checking out"
      assert html =~ "0 bookings"
      refute html =~ "1 booking"
      assert html =~ "Expected guests"
      assert html =~ "View Tahoe bookings →"
      assert html =~ "hero-map-pin"
      assert html =~ "hero-arrow-right-circle"
      assert html =~ "hero-arrow-left-circle"
    end

    test "renders occupied cabin, singular booking, teal accent, and custom CTA" do
      assigns = %{
        stats:
          sample_stats(%{
            staying: 4,
            checkins_today: 2,
            checkouts_today: 1,
            upcoming_bookings: 1,
            upcoming_guests: 6
          })
      }

      html =
        rendered_to_string(~H"""
        <.admin_property_occupancy_card
          id="dashboard-property-clear-lake"
          navigate="/admin/bookings?property=clear_lake"
          label="Clear Lake"
          accent={:teal}
          stats={@stats}
          view_label="Open Clear Lake bookings →"
        />
        """)

      assert html =~ ~s(id="dashboard-property-clear-lake")
      assert html =~ "Clear Lake"
      assert html =~ "text-teal-600"
      assert html =~ "group-hover:text-teal-600"
      assert html =~ "Active"
      assert html =~ "bg-emerald-500"
      refute html =~ "Empty"
      assert html =~ "4"
      assert html =~ "2"
      assert html =~ "1 booking"
      refute html =~ "1 bookings"
      assert html =~ "6"
      assert html =~ "Open Clear Lake bookings →"
      refute html =~ "View Clear Lake bookings →"
    end
  end
end
