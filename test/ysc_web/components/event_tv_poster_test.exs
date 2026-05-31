defmodule YscWeb.Components.EventTvPosterTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.Components.Events.EventTvPoster

  test "renders poster layout with title and QR section" do
    assigns = %{
      event: %{
        title: "Summer Dance",
        image: nil,
        state: :published,
        start_date: ~U[2026-07-01 18:00:00Z],
        location: "Tahoe"
      },
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
      event: %{
        title: "Sold Out Show",
        image: nil,
        state: :published,
        start_date: ~U[2026-07-01 18:00:00Z],
        location: "Tahoe"
      },
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
end
