defmodule YscWeb.Api.AppMembershipsControllerTest do
  @moduledoc """
  Tests for the admin/volunteer mobile app's membership plans and in-person
  sign-up endpoints (`AppMembershipsController` + `AppMembershipsJSON`).
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Accounts

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

  describe "GET /api/v1/app/memberships/plans" do
    test "lists configured plans without leaking stripe_price_id", %{conn: conn} do
      response = get(conn, ~p"/api/v1/app/memberships/plans")

      assert %{"data" => plans} = json_response(response, 200)
      assert is_list(plans) and plans != []

      Enum.each(plans, fn plan ->
        assert Map.has_key?(plan, "id")
        assert Map.has_key?(plan, "name")
        assert Map.has_key?(plan, "amount")
        refute Map.has_key?(plan, "stripe_price_id")
      end)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> get(~p"/api/v1/app/memberships/plans")

      assert json_response(response, 401)
    end
  end

  describe "POST /api/v1/app/memberships/subscribe" do
    test "attaches the payment method and creates a subscription", %{conn: conn} do
      member = user_fixture()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      stripe_price_id =
        :ysc
        |> Application.get_env(:membership_plans, [])
        |> Enum.find(&(&1.id == :single))
        |> Map.fetch!(:stripe_price_id)

      Mox.expect(Ysc.StripeMock, :attach_payment_method, fn "pm_test_card",
                                                            params ->
        assert is_binary(params.customer)
        {:ok, %Stripe.PaymentMethod{id: "pm_test_card"}}
      end)

      Mox.stub(Stripe.SubscriptionMock, :create, fn params, opts ->
        assert params.default_payment_method == "pm_test_card"

        assert opts[:headers]["Idempotency-Key"] ==
                 "app_membership_#{member.id}_#{stripe_price_id}"

        {:ok, %Stripe.Subscription{id: "sub_test_123", status: "active"}}
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_test_card"
        })

      assert %{"id" => "sub_test_123", "status" => "active"} =
               json_response(response, 200)
    end

    test "returns an error for an unknown plan", %{conn: conn} do
      member = user_fixture()

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "not-a-real-plan",
          "payment_method_id" => "pm_test_card"
        })

      assert json_response(response, 422)
    end

    test "returns 400 when required fields are missing", %{conn: conn} do
      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{"plan" => "single"})

      assert json_response(response, 400)
    end

    test "returns 404 for an unknown member", %{conn: conn} do
      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV",
          "plan" => "single",
          "payment_method_id" => "pm_test_card"
        })

      assert %{"error" => "member not found"} = json_response(response, 404)
    end
  end

  describe "POST /api/v1/app/memberships/setup_intent" do
    test "creates a card-present SetupIntent for the member's Stripe customer",
         %{conn: conn} do
      member = user_fixture()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_setup_intent, fn params ->
        assert is_binary(params.customer)
        assert params.payment_method_types == ["card_present"]

        {:ok,
         %Stripe.SetupIntent{
           id: "seti_test_123",
           client_secret: "seti_test_123_secret_abc"
         }}
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/setup_intent", %{
          "member_id" => member.id
        })

      assert %{"client_secret" => "seti_test_123_secret_abc"} =
               json_response(response, 200)
    end

    test "returns 404 for an unknown member", %{conn: conn} do
      response =
        post(conn, ~p"/api/v1/app/memberships/setup_intent", %{
          "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        })

      assert %{"error" => "member not found"} = json_response(response, 404)
    end

    test "returns 400 when member_id is missing", %{conn: conn} do
      response = post(conn, ~p"/api/v1/app/memberships/setup_intent", %{})

      assert json_response(response, 400)
    end
  end

  describe "GET /api/v1/app/memberships/status" do
    test "reports no active membership for a member without one", %{conn: conn} do
      member = user_fixture()

      response =
        get(conn, ~p"/api/v1/app/memberships/status", %{
          "member_id" => member.id
        })

      assert %{"has_active_membership" => false} = json_response(response, 200)
    end

    test "reports lifetime membership details", %{conn: conn} do
      member =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      response =
        get(conn, ~p"/api/v1/app/memberships/status", %{
          "member_id" => member.id
        })

      assert %{
               "has_active_membership" => true,
               "plan_type" => "lifetime",
               "plan_name" => "Lifetime Membership",
               "renewal_date" => nil,
               "cancel_at_period_end" => false
             } = json_response(response, 200)
    end

    test "reports active subscription details", %{conn: conn} do
      member = user_fixture()

      period_end =
        DateTime.utc_now()
        |> DateTime.add(30, :day)
        |> DateTime.truncate(:second)

      plans = Application.fetch_env!(:ysc, :membership_plans)
      single = Enum.find(plans, &(&1.id == :single))

      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: member.id,
          stripe_id: "sub_status_test",
          stripe_status: "active",
          name: "Test Membership",
          current_period_end: period_end,
          cancel_at_period_end: false
        })

      {:ok, _} =
        Ysc.Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_status_test",
          stripe_product_id: "prod_test",
          stripe_price_id: single.stripe_price_id,
          quantity: 1
        })

      response =
        get(conn, ~p"/api/v1/app/memberships/status", %{
          "member_id" => member.id
        })

      assert %{
               "has_active_membership" => true,
               "plan_type" => "single",
               "plan_name" => "Single Membership",
               "cancel_at_period_end" => false
             } = json_response(response, 200)

      assert {:ok, renewal_date, _} =
               response
               |> json_response(200)
               |> Map.fetch!("renewal_date")
               |> DateTime.from_iso8601()

      assert DateTime.diff(renewal_date, period_end, :second) == 0
    end

    test "returns 404 for an unknown member", %{conn: conn} do
      response =
        get(conn, ~p"/api/v1/app/memberships/status", %{
          "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        })

      assert %{"error" => "member not found"} = json_response(response, 404)
    end

    test "returns 400 when member_id is missing", %{conn: conn} do
      response = get(conn, ~p"/api/v1/app/memberships/status", %{})

      assert json_response(response, 400)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> get(~p"/api/v1/app/memberships/status", %{
          "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        })

      assert json_response(response, 401)
    end
  end
end
