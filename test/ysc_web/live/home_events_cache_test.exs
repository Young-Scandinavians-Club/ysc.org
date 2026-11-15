defmodule YscWeb.HomeEventsCacheTest do
  @moduledoc """
  The kiosk/app paginated list omits `:inserted_at` / `:published_at` and shares
  `EventPricingCache` with the public card/home list. A cache hit used to drop
  those keys; the guest home section dotted `event.inserted_at` and 500'd.
  """
  use YscWeb.ConnCase, async: false

  @moduletag process_caches: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.EventPricingCache
  alias Ysc.PublicContentCache

  setup do
    EventPricingCache.invalidate()
    PublicContentCache.invalidate()
    Cachex.clear(:ysc_cache)
    :ok
  end

  test "guest home keeps Just Added after a kiosk/API pricing-cache prime", %{
    conn: conn
  } do
    event =
      event_fixture(%{
        title: "Home Inserted At #{System.unique_integer()}",
        state: :published,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    _tier = ticket_tier_fixture(%{event_id: event.id})

    # Kiosk / mobile API select shape: no inserted_at / published_at.
    {api_rows, _meta} =
      Events.list_upcoming_events_paginated(%{"page_size" => "100"})

    api_row = Enum.find(api_rows, &(&1.id == event.id))
    assert api_row
    refute Map.has_key?(api_row, :inserted_at)
    refute Map.has_key?(api_row, :published_at)

    # Public list/card query selects both; enrich must restore them from the
    # caller on a cache hit so home can render without KeyError.
    public_row =
      Events.list_upcoming_events_from_db(50)
      |> Enum.find(&(&1.id == event.id))

    assert public_row
    assert %DateTime{} = public_row.inserted_at
    assert Map.has_key?(public_row, :published_at)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ event.title
    assert html =~ "Just Added"
  end
end
