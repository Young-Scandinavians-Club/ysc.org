defmodule YscWeb.Api.EventsJSONTest do
  use ExUnit.Case, async: true

  alias YscWeb.Api.EventsJSON

  @base_event %{
    id: "01ABCDEFGHIJKLMNOPQRSTUVWX",
    reference_id: "EVT-1",
    state: :published,
    title: "Gala",
    description: "Fun",
    start_date: ~U[2025-06-01 18:00:00Z],
    start_time: ~T[18:00:00],
    end_date: ~U[2025-06-01 22:00:00Z],
    end_time: ~T[22:00:00],
    location_name: "Hall",
    address: "1 St",
    latitude: "1.0",
    longitude: "2.0",
    age_restriction: "21+",
    max_attendees: 50,
    tickets_tbd: false,
    partiful_link: nil,
    selling_fast: false,
    recent_tickets_count: 0,
    ticket_count: 10,
    pricing_info: nil,
    ticket_tiers: [],
    image: nil
  }

  test "index/1 builds data and meta payload" do
    result = EventsJSON.index(%{events: [@base_event], meta: %{page: 1}})

    assert %{data: [row], meta: %{page: 1}} = result
    assert row[:id] == to_string(@base_event.id)
    assert row[:title] == "Gala"
    assert row[:start_date] == DateTime.to_iso8601(@base_event.start_date)
    assert row[:pricing_info] == nil
    assert row[:ticket_tiers] == []
    assert row[:cover_image] == nil
  end

  test "index/1 includes pricing_info and ticket tier fields when present" do
    event = %{
      @base_event
      | pricing_info: %{
          display_text: "From $10",
          has_free_tiers: false,
          lowest_price: %{price: Money.new(10, :USD)}
        },
        ticket_tiers: [
          %{
            id: "01JKLMNOPQRSTUVWXYZABCD123",
            name: "GA",
            description: nil,
            type: :paid,
            price: Money.new(10, :USD),
            quantity: 100,
            sold_tickets_count: 5,
            requires_registration: false,
            start_date: nil,
            end_date: nil
          }
        ],
        image: %{
          id: "01IMGIMGIMGIMGIMGIMGIMGIMG1",
          optimized_image_path: "/o.jpg",
          thumbnail_path: "/t.jpg",
          blur_hash: "x",
          width: 800,
          height: 600,
          alt_text: "Poster"
        }
    }

    result = EventsJSON.index(%{events: [event], meta: %{}})

    assert %{data: [row]} = result
    assert row[:pricing_info][:display_text] == "From $10"
    assert row[:pricing_info][:lowest_price] == "$10.00"
    [tier] = row[:ticket_tiers]
    assert tier[:name] == "GA"
    assert tier[:price] == "$10.00"
    assert tier[:available] == 95
    assert row[:cover_image][:optimized_path] == "/o.jpg"
  end
end
