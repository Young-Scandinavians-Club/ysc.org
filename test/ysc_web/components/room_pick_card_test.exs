defmodule YscWeb.Components.RoomPickCardTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YscWeb.Components.RoomPickCard

  defp room(overrides \\ %{}) do
    Map.merge(
      %{
        id: "room-1",
        name: "Room 4",
        description: "Spacious family room.",
        capacity_max: 5,
        min_billable_occupancy: 1,
        single_beds: 3,
        queen_beds: 1,
        king_beds: 0,
        image: nil
      },
      overrides
    )
  end

  defp render_card(assigns) do
    render_component(
      &RoomPickCard.room_pick_card/1,
      Map.merge(
        %{room: room(), prices: %{adult: "$45.00", child: "$25.00"}},
        assigns
      )
    )
  end

  test "renders name, description, one metadata line and quiet prices" do
    html = render_card(%{})

    assert html =~ "Room 4"
    assert html =~ "Spacious family room."
    assert html =~ "Up to 5 guests"
    assert html =~ "3 twin"
    assert html =~ "1 queen"
    assert html =~ "$45.00/adult"
    assert html =~ "$25.00/child"
    refute html =~ "bg-blue-100"
    refute html =~ "bg-green-500"
  end

  test "is a radio by default and a checkbox when several rooms are allowed" do
    assert render_card(%{}) =~ ~s(type="radio")
    assert render_card(%{}) =~ ~s(name="room_id")

    html = render_card(%{multiple: true})
    assert html =~ ~s(type="checkbox")
    assert html =~ ~s(name="room_ids")
  end

  test "wires selection to room-changed with a stable id" do
    html = render_card(%{})

    assert html =~ ~s(id="room-room-1")
    assert html =~ ~s(phx-click="room-changed")
    assert html =~ ~s(phx-value-room-id="room-1")
    assert html =~ ~s(aria-label="Select Room 4")
  end

  test "marks the selected card" do
    html = render_card(%{selected: true})

    assert html =~ "border-blue-600"
    assert html =~ "checked"
    assert html =~ "hero-check-mini"
  end

  test "a disabled card cannot be picked and explains why" do
    html =
      render_card(%{
        disabled: true,
        reason: "Already booked for these dates"
      })

    assert html =~ "disabled"
    assert html =~ "Already booked for these dates"
    # The reason is exposed to assistive tech and sits under the photo.
    assert html =~ ~s(aria-describedby="room-room-1-reason")
    assert html =~ ~s(id="room-room-1-reason")
    refute html =~ "bg-zinc-900/80"
    refute html =~ ~s(id="room-room-1")
    refute html =~ "phx-click"
  end

  test "shows the minimum price and charge note for min-occupancy rooms" do
    html =
      render_card(%{
        room: room(%{min_billable_occupancy: 2}),
        prices: %{
          adult: "$45.00",
          child: "$25.00",
          minimum: "$90.00",
          minimum_caption: "(charged for 2 guests)"
        }
      })

    assert html =~ "$90.00 min"
    assert html =~ "(charged for 2 guests)"
    assert html =~ ~s(id="room-room-1-min-charge-badge")
    refute html =~ "/adult"
  end
end
