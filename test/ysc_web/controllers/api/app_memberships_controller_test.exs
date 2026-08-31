defmodule YscWeb.Api.AppMembershipsControllerTest do
  @moduledoc """
  Tests for the admin/volunteer mobile app's membership plans and in-person
  sign-up endpoints (`AppMembershipsController` + `AppMembershipsJSON`).
  """
  use YscWeb.ConnCase, async: false

  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  setup :verify_on_exit!

  defp lifetime_member do
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
        refute plan["id"] == "lifetime"
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
    defp member_with_stripe_customer do
      user_fixture()
      |> Ecto.Changeset.change(stripe_id: "cus_member_door_sale")
      |> Ysc.Repo.update!()
    end

    defp stub_recent_payment_method!(
           customer_id,
           payment_method_id \\ "pm_test_card"
         ) do
      Mox.expect(
        Ysc.StripeMock,
        :retrieve_payment_method,
        fn ^payment_method_id ->
          {:ok,
           %Stripe.PaymentMethod{
             id: payment_method_id,
             customer: customer_id,
             created: System.system_time(:second) - 60
           }}
        end
      )
    end

    test "creates a subscription with the already-attached payment method as default",
         %{
           conn: conn
         } do
      member = member_with_stripe_customer()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      stripe_price_id =
        :ysc
        |> Application.get_env(:membership_plans, [])
        |> Enum.find(&(&1.id == :single))
        |> Map.fetch!(:stripe_price_id)

      # Deliberately does NOT stub/expect attach_payment_method: the payment
      # method arrives here already attached (via the prior SetupIntent flow
      # in create_setup_intent/2), and re-attaching an already-attached
      # payment method is a Stripe API error — see the moduledoc.
      stub_recent_payment_method!(member.stripe_id)

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

    test "rejects a payment method attached to a different Stripe customer", %{
      conn: conn
    } do
      member = member_with_stripe_customer()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :retrieve_payment_method, fn "pm_foreign" ->
        {:ok,
         %Stripe.PaymentMethod{
           id: "pm_foreign",
           customer: "cus_someone_else",
           created: System.system_time(:second)
         }}
      end)

      Mox.stub(Stripe.SubscriptionMock, :create, fn _params, _opts ->
        flunk("must not create a subscription with a foreign payment method")
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_foreign"
        })

      assert %{
               "error" =>
                 "payment method must be collected for this member via Terminal just before subscribe"
             } = json_response(response, 422)
    end

    test "rejects a stale payment method from a prior door-sale session", %{
      conn: conn
    } do
      member = member_with_stripe_customer()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :retrieve_payment_method, fn "pm_stale" ->
        {:ok,
         %Stripe.PaymentMethod{
           id: "pm_stale",
           customer: member.stripe_id,
           # Older than the in-person SetupIntent window.
           created: System.system_time(:second) - 60 * 60 - 1
         }}
      end)

      Mox.stub(Stripe.SubscriptionMock, :create, fn _params, _opts ->
        flunk("must not create a subscription with a stale payment method")
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_stale"
        })

      assert %{
               "error" =>
                 "payment method must be collected for this member via Terminal just before subscribe"
             } = json_response(response, 422)
    end

    test "rejects subscribe when the member has no Stripe customer yet", %{
      conn: conn
    } do
      member = user_fixture()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.stub(Ysc.StripeMock, :retrieve_payment_method, fn _id ->
        flunk(
          "must not retrieve a payment method without a member Stripe customer"
        )
      end)

      Mox.stub(Stripe.SubscriptionMock, :create, fn _params, _opts ->
        flunk("must not create a subscription without a bound payment method")
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_test_card"
        })

      assert %{
               "error" =>
                 "payment method must be collected for this member via Terminal just before subscribe"
             } = json_response(response, 422)
    end

    test "rejects subscribe when Stripe cannot retrieve the payment method", %{
      conn: conn
    } do
      member = member_with_stripe_customer()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :retrieve_payment_method, fn "pm_missing" ->
        {:error, :not_found}
      end)

      Mox.stub(Stripe.SubscriptionMock, :create, fn _params, _opts ->
        flunk("must not create a subscription when the payment method is missing")
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_missing"
        })

      assert %{
               "error" =>
                 "payment method must be collected for this member via Terminal just before subscribe"
             } = json_response(response, 422)
    end

    test "accepts a string-keyed payment method map from Stripe", %{conn: conn} do
      member = member_with_stripe_customer()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :retrieve_payment_method, fn "pm_map_keys" ->
        {:ok,
         %{
           "id" => "pm_map_keys",
           "customer" => member.stripe_id,
           "created" => System.system_time(:second) - 30
         }}
      end)

      Mox.stub(Stripe.SubscriptionMock, :create, fn params, _opts ->
        assert params.default_payment_method == "pm_map_keys"

        {:ok, %Stripe.Subscription{id: "sub_map_keys", status: "active"}}
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_map_keys"
        })

      assert %{"id" => "sub_map_keys", "status" => "active"} =
               json_response(response, 200)
    end

    test "rejects a payment method that is not attached to any customer", %{
      conn: conn
    } do
      member = member_with_stripe_customer()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :retrieve_payment_method, fn "pm_unattached" ->
        {:ok,
         %Stripe.PaymentMethod{
           id: "pm_unattached",
           customer: nil,
           created: System.system_time(:second)
         }}
      end)

      Mox.stub(Stripe.SubscriptionMock, :create, fn _params, _opts ->
        flunk("must not create a subscription with an unattached payment method")
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_unattached"
        })

      assert %{
               "error" =>
                 "payment method must be collected for this member via Terminal just before subscribe"
             } = json_response(response, 422)
    end

    test "rejects a payment method with no created timestamp", %{conn: conn} do
      member = member_with_stripe_customer()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :retrieve_payment_method, fn "pm_no_created" ->
        {:ok, %{"id" => "pm_no_created", "customer" => member.stripe_id}}
      end)

      Mox.stub(Stripe.SubscriptionMock, :create, fn _params, _opts ->
        flunk("must not create a subscription without a created timestamp")
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_no_created"
        })

      assert %{
               "error" =>
                 "payment method must be collected for this member via Terminal just before subscribe"
             } = json_response(response, 422)
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

    test "does not charge a lifetime member for a new annual plan", %{
      conn: conn
    } do
      member = lifetime_member()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.stub(Stripe.SubscriptionMock, :create, fn _params, _opts ->
        flunk("must not create a Stripe subscription for a lifetime member")
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_test_card"
        })

      assert %{"error" => "member already has an active membership"} =
               json_response(response, 422)
    end

    test "does not charge a family sub-account who already inherits membership",
         %{conn: conn} do
      primary = lifetime_member()

      member =
        user_fixture()
        |> Ecto.Changeset.change(primary_user_id: primary.id)
        |> Ysc.Repo.update!()

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.stub(Stripe.SubscriptionMock, :create, fn _params, _opts ->
        flunk("must not create a Stripe subscription for a family sub-account")
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_test_card"
        })

      assert %{"error" => "member already has an active membership"} =
               json_response(response, 422)
    end

    test "rejects the non-purchasable lifetime plan", %{conn: conn} do
      member = user_fixture()

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "lifetime",
          "payment_method_id" => "pm_test_card"
        })

      assert %{"error" => "invalid membership plan"} =
               json_response(response, 422)
    end
  end

  describe "POST /api/v1/app/memberships/subscribe_offline" do
    setup do
      on_exit(fn ->
        Application.delete_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback
        )
      end)

      :ok
    end

    defp stub_out_of_band_stripe(plan_id) do
      plan =
        :ysc
        |> Application.get_env(:membership_plans, [])
        |> Enum.find(&(&1.id == plan_id))

      now = System.system_time(:second)

      fake =
        Ysc.Stripe.SubscriptionFixtures.subscription(
          id: "sub_offline_#{System.unique_integer([:positive])}",
          status: "active",
          current_period_start: now,
          current_period_end: now + 365 * 86_400,
          price_id: plan.stripe_price_id,
          product_id: "prod_fake",
          subscription_item_id: "si_#{System.unique_integer([:positive])}"
        )

      Application.put_env(
        :ysc,
        :create_subscription_paid_out_of_band_stripe_callback,
        fn _user, _plan -> {:ok, fake} end
      )
    end

    test "records a cash membership and returns the new subscription", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      member = user_fixture()
      stub_out_of_band_stripe(:single)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe_offline", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method" => "cash",
          "note" => "envelope #7"
        })

      assert %{
               "status" => "active",
               "plan_id" => "single",
               "plan_name" => _
             } = json_response(response, 200)

      assert Ysc.Accounts.has_active_membership?(
               Ysc.Accounts.get_user!(member.id)
             )
    end

    test "defaults the payment method to cash when omitted", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      member = user_fixture()
      stub_out_of_band_stripe(:family)

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe_offline", %{
          "member_id" => member.id,
          "plan" => "family"
        })

      assert %{"plan_id" => "family"} = json_response(response, 200)
    end

    test "rejects an unknown payment method", %{conn: conn} do
      member = user_fixture()

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe_offline", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method" => "venmo"
        })

      assert %{"error" => "payment_method must be one of: cash, check, other"} =
               json_response(response, 422)
    end

    test "rejects the non-purchasable lifetime plan", %{conn: conn} do
      member = user_fixture()

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe_offline", %{
          "member_id" => member.id,
          "plan" => "lifetime"
        })

      assert %{"error" => "invalid membership plan"} =
               json_response(response, 422)
    end

    test "does not create a second membership for a lifetime member", %{
      conn: conn
    } do
      member = lifetime_member()

      Application.put_env(
        :ysc,
        :create_subscription_paid_out_of_band_stripe_callback,
        fn _user, _plan -> flunk("must not create a subscription") end
      )

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe_offline", %{
          "member_id" => member.id,
          "plan" => "single"
        })

      assert %{"error" => "member already has an active membership"} =
               json_response(response, 422)
    end

    test "returns 400 when plan is missing", %{conn: conn} do
      member = user_fixture()

      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe_offline", %{
          "member_id" => member.id
        })

      assert json_response(response, 400)
    end

    test "returns 404 for an unknown member", %{conn: conn} do
      response =
        post(conn, ~p"/api/v1/app/memberships/subscribe_offline", %{
          "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV",
          "plan" => "single"
        })

      assert %{"error" => "member not found"} = json_response(response, 404)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      member = user_fixture()

      response =
        conn
        |> delete_req_header("authorization")
        |> post(~p"/api/v1/app/memberships/subscribe_offline", %{
          "member_id" => member.id,
          "plan" => "single"
        })

      assert json_response(response, 401)
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

    test "does not collect a card for a lifetime member", %{conn: conn} do
      member = lifetime_member()
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.stub(Ysc.StripeMock, :create_setup_intent, fn _params ->
        flunk("must not create a SetupIntent for a lifetime member")
      end)

      response =
        post(conn, ~p"/api/v1/app/memberships/setup_intent", %{
          "member_id" => member.id
        })

      assert %{"error" => "member already has an active membership"} =
               json_response(response, 422)
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
