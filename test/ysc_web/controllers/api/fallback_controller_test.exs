defmodule YscWeb.Api.FallbackControllerTest do
  use YscWeb.ConnCase, async: true

  alias YscWeb.Api.FallbackController

  describe "call/2" do
    test "missing_property returns 400 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :missing_property})
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] =~ "property is required"
    end

    test "invalid_property returns 400 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_property})
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] =~ "invalid property"
    end

    test "not_found returns 404 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body) == %{"error" => "not found"}
    end

    test "invalid_date returns 400 JSON with field name", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:invalid_date, "start"}})
      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] =~ "start"
      assert body["error"] =~ "ISO 8601"
    end

    test "changeset returns 422 with field errors", %{conn: conn} do
      changeset =
        {%{}, %{title: :string}}
        |> Ecto.Changeset.cast(%{"title" => ""}, [:title])
        |> Ecto.Changeset.validate_required(:title)

      conn = FallbackController.call(conn, {:error, changeset})
      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation failed"
      assert is_map(body["errors"])
    end

    test "binary reason returns 422 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, "bad input"})
      assert conn.status == 422
      assert Jason.decode!(conn.resp_body) == %{"error" => "bad input"}
    end

    test "non-binary error reason returns 500 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unexpected_atom})
      assert conn.status == 500
      assert Jason.decode!(conn.resp_body)["error"] =~ "unexpected"
    end

    test "maps mobile-app not-found reasons to 404 JSON" do
      for {reason, message} <- [
            {:member_not_found, "member not found"},
            {:ticket_tier_not_found, "ticket tier not found"},
            {:event_not_found, "event not found"}
          ] do
        result = FallbackController.call(build_conn(), {:error, reason})
        assert result.status == 404, "#{reason} should be 404"
        assert Jason.decode!(result.resp_body) == %{"error" => message}
      end
    end

    test "maps mobile-app business-rule reasons to 422 JSON" do
      for {reason, message} <- [
            {:membership_required, "member does not have an active membership"},
            {:invalid_plan, "invalid membership plan"},
            {:terminal_not_configured,
             "Stripe Terminal is not configured for this environment"},
            {:user_already_has_active_subscription,
             "member already has an active membership"},
            {:sub_accounts_cannot_create_subscriptions,
             "sub-accounts cannot sign up for their own membership"},
            {:invalid_ticket_selection,
             "one or more selected ticket quantities are invalid"},
            {:tier_validation_failed,
             "one or more selected ticket tiers are sold out or unavailable"},
            {:insufficient_capacity,
             "not enough tickets remaining for the selected tiers"},
            {:event_capacity_exceeded, "this event is at capacity"},
            {:event_not_available,
             "this event is not available for ticket sales"},
            {:event_cancelled, "this event has been cancelled"},
            {:event_in_past, "this event has already happened"},
            {:reservation_lapsed,
             "the ticket reservation expired — please try again"},
            {:checkout_payment_in_progress,
             "a payment is already in progress for this member and event"}
          ] do
        result = FallbackController.call(build_conn(), {:error, reason})
        assert result.status == 422, "#{reason} should be 422"
        assert Jason.decode!(result.resp_body) == %{"error" => message}
      end
    end
  end
end
