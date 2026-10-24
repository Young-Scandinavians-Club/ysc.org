defmodule YscWeb.Components.Events.EventDatePillTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import YscWeb.Components.Events.EventDatePill

  @event %{start_date: ~D[2026-11-07], end_date: nil, start_time: ~T[10:00:00]}

  defp render_pill(assigns) do
    rendered_to_string(~H"""
    <.event_date_pill {@pill} />
    """)
  end

  defp pill_text(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.trim()
  end

  test "renders date and time in a single pill" do
    html = render_pill(%{pill: %{event: @event, id: "pill"}})

    assert pill_text(html) == "Nov 7 · 10:00 AM"

    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#pill")
           |> Enum.count() == 1
  end

  test "includes the year when requested" do
    html = render_pill(%{pill: %{event: @event, with_year: true}})

    assert pill_text(html) == "Nov 7, 2026 · 10:00 AM"
  end

  test "renders only the date when there is no start time" do
    html = render_pill(%{pill: %{event: %{@event | start_time: nil}}})

    assert pill_text(html) == "Nov 7"
  end

  test "applies variant classes" do
    assert render_pill(%{pill: %{event: @event, variant: "dark"}}) =~
             "bg-zinc-800"

    assert render_pill(%{pill: %{event: @event, variant: "overlay"}}) =~
             "bg-white/15"
  end
end
