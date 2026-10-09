defmodule YscWeb.Components.RoomBrowserTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YscWeb.Components.RoomBrowser

  defp room(overrides) do
    Map.merge(
      %{
        id: "room-1",
        name: "Family Room",
        description: "Sleeps the whole family.",
        capacity_max: 5,
        min_billable_occupancy: 1,
        single_beds: 0,
        queen_beds: 0,
        king_beds: 0,
        room_category: nil,
        image: nil
      },
      overrides
    )
  end

  defp render_browser(rooms, extra \\ %{}) do
    render_component(
      &RoomBrowser.room_browser/1,
      Map.merge(%{rooms: rooms, property_name: "Test Cabin"}, extra)
    )
  end

  describe "room_browser/1" do
    test "renders name, description, capacity and category" do
      html =
        render_browser([
          room(%{room_category: %{name: "Family"}})
        ])

      assert html =~ "Rooms at the Test Cabin"
      assert html =~ "Family Room"
      assert html =~ "Sleeps the whole family."
      assert html =~ "Max 5 guests"
      assert html =~ "Family"
    end

    test "uses singular wording for single-guest rooms" do
      assert render_browser([room(%{capacity_max: 1})]) =~ "Max 1 guest"
    end

    test "shows a bed summary for each bed type" do
      html =
        render_browser([
          room(%{single_beds: 2, queen_beds: 1, king_beds: 1})
        ])

      assert html =~ "2 twin"
      assert html =~ "1 queen"
      assert html =~ "1 king"
    end

    test "omits the bed list when the room has no beds" do
      refute render_browser([room(%{})]) =~ ~s(aria-label="Beds")
    end

    test "shows the minimum-charge badge only for min-occupancy rooms" do
      assert render_browser([room(%{min_billable_occupancy: 2})]) =~
               "Priced for 2+ guests"

      refute render_browser([room(%{})]) =~ "Priced for"
    end

    test "renders the pick button only when a pick event is given" do
      with_pick = render_browser([room(%{})], %{pick_event: "browse-room-pick"})
      without_pick = render_browser([room(%{})])

      assert with_pick =~ ~s(id="browse-room-pick-room-1")
      assert with_pick =~ ~s(phx-click="browse-room-pick")
      refute without_pick =~ "browse-room-pick-room-1"
    end

    test "supports the teal accent" do
      html =
        render_browser([room(%{})], %{
          accent: :teal,
          pick_event: "browse-room-pick"
        })

      assert html =~ "bg-teal-600"
    end
  end
end
