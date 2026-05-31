defmodule YscWeb.Components.EventTvPosterTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.Components.Events.EventTvPoster

  defp poster_event(overrides \\ %{}) do
    Map.merge(
      %{
        title: "Summer Dance",
        image: nil,
        description: nil,
        state: :published,
        start_date: ~U[2026-07-01 18:00:00Z],
        location: "Tahoe",
        location_name: "Tahoe"
      },
      overrides
    )
  end

  test "renders poster layout with title and QR section" do
    assigns = %{
      event: poster_event(%{title: "Summer Dance"}),
      event_url: "https://ysc.org/events/abc",
      sold_out: false,
      selling_fast: true
    }

    html =
      rendered_to_string(~H"""
      <.event_tv_poster
        event={@event}
        event_url={@event_url}
        sold_out={@sold_out}
        selling_fast={@selling_fast}
      />
      """)

    assert html =~ "event-tv-poster"
    assert html =~ "Summer Dance"
    assert html =~ "event-tv-poster-qr"
    assert html =~ "Scan for details"
  end

  test "shows sold out badge when sold_out is true" do
    assigns = %{
      event: poster_event(%{title: "Sold Out Show"}),
      event_url: "https://ysc.org/events/abc",
      sold_out: true,
      selling_fast: false
    }

    html =
      rendered_to_string(~H"""
      <.event_tv_poster
        event={@event}
        event_url={@event_url}
        sold_out={@sold_out}
        selling_fast={@selling_fast}
      />
      """)

    assert html =~ "Sold Out"
  end

  test "formats event date and time with Calendar" do
    assigns = %{
      event:
        poster_event(%{
          start_date: ~D[2026-07-28],
          start_time: ~T[19:00:00]
        }),
      event_url: "https://ysc.org/events/abc",
      sold_out: false,
      selling_fast: false
    }

    html =
      rendered_to_string(~H"""
      <.event_tv_poster
        event={@event}
        event_url={@event_url}
        sold_out={@sold_out}
        selling_fast={@selling_fast}
      />
      """)

    assert html =~ "Jul 28, 2026"
    assert html =~ "7:00 PM"
  end
end
