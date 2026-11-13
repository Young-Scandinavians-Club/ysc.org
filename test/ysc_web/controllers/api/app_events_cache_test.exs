defmodule YscWeb.Api.AppEventsCacheTest do
  @moduledoc """
  The public event-card query omits `:age_restriction` and shares
  `EventPricingCache` with the mobile app list. A cache hit used to drop the
  key and `GET /api/v1/app/events` 500'd in `EventsJSON` (#1842).
  """
  use YscWeb.ConnCase, async: false

  @moduletag process_caches: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Accounts
  alias Ysc.Events
  alias Ysc.Events.EventPricingCache

  setup do
    EventPricingCache.invalidate()
    Cachex.clear(:ysc_cache)
    :ok
  end

  test "GET /api/v1/app/events keeps age_restriction after a public-list cache prime",
       %{conn: conn} do
    event =
      event_fixture(%{
        title: "App Age Restriction #{System.unique_integer()}",
        state: :published,
        age_restriction: 21
      })

    ticket_tier_fixture(%{
      event_id: event.id,
      type: :paid,
      price: Money.new(50, :USD)
    })

    public_row =
      Events.list_upcoming_events_from_db(50)
      |> Enum.find(&(&1.id == event.id))

    assert public_row
    refute Map.has_key?(public_row, :age_restriction)

    response =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header(
        "authorization",
        "Bearer #{Accounts.generate_user_mobile_token(user_fixture(%{role: :admin}))}"
      )
      |> get(~p"/api/v1/app/events")

    assert %{"data" => data} = json_response(response, 200)

    row = Enum.find(data, &(&1["id"] == event.id))
    assert row, "expected the payable event in the app list"
    assert row["age_restriction"] == 21
  end
end
