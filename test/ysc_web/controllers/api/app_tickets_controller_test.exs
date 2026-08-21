defmodule YscWeb.Api.AppTicketsControllerTest do
  @moduledoc """
  Tests for the admin/volunteer mobile app's in-person ticket purchase
  endpoint (`AppTicketsController` + `AppTicketsJSON`).
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Accounts

  defp member_with_active_membership do
    Ysc.Ledgers.ensure_basic_accounts()

    user_fixture()
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()
  end

  setup %{conn: conn} do
    admin = user_fixture(%{role: :admin})
    token = Accounts.generate_user_mobile_token(admin)

    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn}
  end

  describe "POST /api/v1/app/tickets/:ticket_tier_id/payment_intent" do
    test "creates a ticket order and a card-present payment intent", %{
      conn: conn
    } do
      member = member_with_active_membership()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        assert params.payment_method_types == ["card_present"]
        assert params.capture_method == "automatic"
        refute Map.has_key?(params, :automatic_payment_methods)
        assert params.amount == 5000

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_test_card_present",
           client_secret: "pi_test_card_present_secret",
           amount: 5000,
           currency: "usd"
         }}
      end)

      response =
        post(conn, ~p"/api/v1/app/tickets/#{tier.id}/payment_intent", %{
          "member_id" => member.id
        })

      assert %{
               "client_secret" => "pi_test_card_present_secret",
               "amount" => 5000,
               "ticket_order_id" => ticket_order_id
             } = json_response(response, 200)

      assert is_binary(ticket_order_id)
    end

    test "returns an error when the member has no active membership", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      member = user_fixture()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/tickets/#{tier.id}/payment_intent", %{
          "member_id" => member.id
        })

      assert json_response(response, 422)
    end

    test "returns 404 for an unknown ticket tier", %{conn: conn} do
      member = member_with_active_membership()

      response =
        post(
          conn,
          ~p"/api/v1/app/tickets/01ARZ3NDEKTSV4RRFFQ69G5FAV/payment_intent",
          %{
            "member_id" => member.id
          }
        )

      assert %{"error" => "ticket tier not found"} =
               json_response(response, 404)
    end

    test "returns 400 when member_id is missing", %{conn: conn} do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/tickets/#{tier.id}/payment_intent", %{})

      assert json_response(response, 400)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> post(
          ~p"/api/v1/app/tickets/01ARZ3NDEKTSV4RRFFQ69G5FAV/payment_intent",
          %{
            "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV"
          }
        )

      assert json_response(response, 401)
    end
  end
end
