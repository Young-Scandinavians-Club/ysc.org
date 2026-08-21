defmodule YscWeb.Api.AppPaymentsControllerTest do
  @moduledoc """
  Tests for the admin/volunteer mobile app's Stripe Terminal connection-token
  endpoint (`AppPaymentsController` + `AppPaymentsJSON`).
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  setup %{conn: conn} do
    user = user_fixture(%{role: :admin})
    token = Accounts.generate_user_mobile_token(user)

    original_location_id =
      Application.get_env(:ysc, :stripe_terminal_location_id)

    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_terminal_location_id, original_location_id)
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn}
  end

  describe "POST /api/v1/app/payments/connection_token" do
    test "returns 422 when no Terminal location is configured", %{conn: conn} do
      Application.put_env(:ysc, :stripe_terminal_location_id, nil)

      response = post(conn, ~p"/api/v1/app/payments/connection_token")

      assert json_response(response, 422)
    end

    test "returns a connection token secret when configured", %{conn: conn} do
      Application.put_env(:ysc, :stripe_terminal_location_id, "tml_test_123")
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_terminal_connection_token, fn params ->
        assert params.location == "tml_test_123"
        {:ok, %Stripe.Terminal.ConnectionToken{secret: "pst_test_secret"}}
      end)

      response = post(conn, ~p"/api/v1/app/payments/connection_token")

      assert %{"secret" => "pst_test_secret"} = json_response(response, 200)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> post(~p"/api/v1/app/payments/connection_token")

      assert json_response(response, 401)
    end
  end
end
