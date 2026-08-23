defmodule YscWeb.Api.AppEventsControllerTest do
  @moduledoc """
  Tests that `GET /api/v1/app/events` (the admin/volunteer mobile app's
  events list) is gated by a per-user mobile bearer token rather than the
  kiosk shared secret, and only returns events with a payable ticket tier.
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Accounts

  defp authed_conn(conn, role \\ :admin) do
    user = user_fixture(%{role: role})
    token = Accounts.generate_user_mobile_token(user)

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
  end

  describe "GET /api/v1/app/events" do
    test "includes an event with a paid ticket tier", %{conn: conn} do
      event = event_fixture(%{state: :published})

      ticket_tier_fixture(%{
        event_id: event.id,
        type: :paid,
        price: Money.new(50, :USD)
      })

      response = conn |> authed_conn() |> get(~p"/api/v1/app/events")

      assert %{"data" => data} = json_response(response, 200)
      assert Enum.any?(data, &(&1["id"] == event.id))
    end

    test "includes an event with a donation ticket tier", %{conn: conn} do
      event = event_fixture(%{state: :published})
      ticket_tier_fixture(%{event_id: event.id, type: :donation, price: nil})

      response = conn |> authed_conn() |> get(~p"/api/v1/app/events")

      assert %{"data" => data} = json_response(response, 200)
      assert Enum.any?(data, &(&1["id"] == event.id))
    end

    test "excludes an event with only a free ticket tier", %{conn: conn} do
      event = event_fixture(%{state: :published})

      ticket_tier_fixture(%{
        event_id: event.id,
        type: :free,
        price: Money.new(0, :USD)
      })

      response = conn |> authed_conn() |> get(~p"/api/v1/app/events")

      assert %{"data" => data} = json_response(response, 200)
      refute Enum.any?(data, &(&1["id"] == event.id))
    end

    test "excludes an event with no ticket tiers at all", %{conn: conn} do
      event = event_fixture(%{state: :published})

      response = conn |> authed_conn() |> get(~p"/api/v1/app/events")

      assert %{"data" => data} = json_response(response, 200)
      refute Enum.any?(data, &(&1["id"] == event.id))
    end

    test "returns 401 for a plain member", %{conn: conn} do
      response = conn |> authed_conn(:member) |> get(~p"/api/v1/app/events")

      assert json_response(response, 401)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/app/events")

      assert json_response(response, 401)
    end
  end
end
