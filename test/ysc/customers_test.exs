defmodule Ysc.CustomersTest do
  @moduledoc """
  Tests for Ysc.Customers context module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Customers
  alias Ysc.Accounts.User
  import Ysc.AccountsFixtures

  defp user_fixture_unique(attrs \\ %{}) do
    email =
      Map.get_lazy(attrs, :email, fn ->
        "cu#{:erlang.unique_integer([:positive, :monotonic])}@example.com"
      end)

    user_fixture(Map.put(attrs, :email, email))
  end

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    # Override default stub to return a specific payment method for assertions
    stub(Stripe.PaymentMethodMock, :retrieve, fn _id ->
      {:ok, %Stripe.PaymentMethod{id: "pm_test123", type: "card"}}
    end)

    :ok
  end

  describe "customer_from_stripe_id/1" do
    test "returns user with matching stripe_id" do
      user = user_fixture_unique()
      user = update_user_stripe_id(user, "cus_test_123")

      found = Customers.customer_from_stripe_id("cus_test_123")
      assert found.id == user.id
    end

    test "returns nil for non-existent stripe_id" do
      assert Customers.customer_from_stripe_id("cus_nonexistent") == nil
    end
  end

  describe "subscriptions/1" do
    test "returns subscriptions for a user" do
      user = user_fixture_unique()

      # Create a subscription for the user
      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_test_123",
          stripe_status: "active",
          name: "Test Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscriptions = Customers.subscriptions(user)
      assert subscriptions != []
      assert Enum.any?(subscriptions, &(&1.id == subscription.id))
    end

    test "returns all subscriptions when user has several" do
      user = user_fixture_unique()

      for i <- 1..2 do
        {:ok, _} =
          Ysc.Subscriptions.create_subscription(%{
            user_id: user.id,
            stripe_id: "sub_multi_#{i}_#{System.unique_integer([:positive])}",
            stripe_status: "active",
            name: "Membership #{i}",
            current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
          })
      end

      subs = Customers.subscriptions(user)
      assert length(subs) >= 2
    end

    test "returns empty list for user with no subscriptions" do
      user = user_fixture_unique()
      subscriptions = Customers.subscriptions(user)
      assert subscriptions == []
    end
  end

  describe "subscribed_to_price?/2" do
    test "returns true for trialing subscription with matching price" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_trialing_#{System.unique_integer([:positive])}",
          stripe_status: "trialing",
          name: "Trial",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _} =
        Ysc.Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: "price_trialing_x",
          stripe_product_id: "prod_x",
          stripe_id: "si_trialing",
          quantity: 1
        })

      assert Customers.subscribed_to_price?(user, "price_trialing_x")
    end

    test "returns true when user is subscribed to price" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_test_123",
          stripe_status: "active",
          name: "Test Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      # Create subscription item with price
      {:ok, _item} =
        Ysc.Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: "price_test_123",
          stripe_product_id: "prod_test_123",
          stripe_id: "si_test_123",
          quantity: 1
        })

      assert Customers.subscribed_to_price?(user, "price_test_123") == true
    end

    test "returns false when user is not subscribed to price" do
      user = user_fixture_unique()
      assert Customers.subscribed_to_price?(user, "price_nonexistent") == false
    end

    test "returns false when subscription is not active" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_inactive",
          stripe_status: "canceled",
          name: "Old",
          current_period_end: DateTime.add(DateTime.utc_now(), -1, :day)
        })

      {:ok, _} =
        Ysc.Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: "price_inactive",
          stripe_product_id: "prod_x",
          stripe_id: "si_inactive",
          quantity: 1
        })

      refute Customers.subscribed_to_price?(user, "price_inactive")
    end
  end

  describe "default_payment_method/1" do
    test "returns default payment method for user" do
      user = user_fixture_unique()

      # Create payment method and set as default
      {:ok, _method} =
        Ysc.Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_test123",
          provider_customer_id: "cus_test123",
          type: :card,
          provider_type: "card",
          is_default: true
        })

      method = Customers.default_payment_method(user)

      assert method != nil
      assert method.id == "pm_test123"
    end

    test "returns nil when user has no default payment method" do
      user = user_fixture_unique()
      refute Customers.default_payment_method(user)
    end

    test "returns nil when Stripe retrieve fails" do
      user = user_fixture_unique()

      {:ok, _} =
        Ysc.Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_fail",
          provider_customer_id: "cus_fail",
          type: :card,
          provider_type: "card",
          is_default: true
        })

      Mox.stub(Stripe.PaymentMethodMock, :retrieve, fn _id ->
        {:error,
         %Stripe.Error{
           message: "no such pm",
           source: :api,
           code: :resource_missing
         }}
      end)

      refute Customers.default_payment_method(user)
    end
  end

  describe "payment_methods/1" do
    test "returns payment methods for user" do
      user = user_fixture_unique()
      # Create a Stripe customer for the user (required for payment_methods)
      {:ok, stripe_customer} = Ysc.Customers.create_stripe_customer(user)
      user = Ysc.Repo.get!(Ysc.Accounts.User, user.id)

      {:ok, _method1} =
        Ysc.Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_test1",
          provider_customer_id: stripe_customer.id,
          type: :card,
          provider_type: "card"
        })

      # payment_methods calls Stripe API which will fail in tests
      # It returns an empty list on error, which is expected
      methods = Customers.payment_methods(user)
      assert is_list(methods)
    end

    test "returns card list from Stripe when list succeeds" do
      user = user_fixture_unique() |> update_user_stripe_id("cus_pm_list")

      Mox.stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:ok,
         %Stripe.List{
           data: [%Stripe.PaymentMethod{id: "pm_a", type: "card"}],
           has_more: false,
           object: "list",
           url: "/v1/payment_methods"
         }}
      end)

      pms = Customers.payment_methods(user)
      assert [%Stripe.PaymentMethod{id: "pm_a"}] = pms
    end

    test "returns empty list when Stripe list returns an error" do
      user = user_fixture_unique() |> update_user_stripe_id("cus_pm_err")

      Mox.stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:error, %Stripe.Error{message: "bad", source: :api, code: :api_error}}
      end)

      assert Customers.payment_methods(user) == []
    end
  end

  describe "invoices/1" do
    test "returns empty list when user has no Stripe customer id" do
      user = user_fixture_unique()
      assert user.stripe_id == nil
      assert Customers.invoices(user) == []
    end

    test "returns invoices for user" do
      user = user_fixture_unique()
      invoices = Customers.invoices(user)
      assert is_list(invoices)
    end

    test "returns invoice data when Stripe list succeeds" do
      user =
        user_fixture_unique()
        |> update_user_stripe_id(
          "cus_inv_#{System.unique_integer([:positive])}"
        )

      Mox.stub(Stripe.InvoiceMock, :list, fn _params ->
        {:ok,
         %Stripe.List{
           data: [%Stripe.Invoice{id: "in_test123", customer: user.stripe_id}],
           has_more: false,
           object: "list",
           url: "/v1/invoices"
         }}
      end)

      invoices = Customers.invoices(user)
      assert [%Stripe.Invoice{id: "in_test123"}] = invoices
    end

    test "returns empty list when Stripe invoice list fails" do
      user = user_fixture_unique() |> update_user_stripe_id("cus_inv_err")

      Mox.stub(Stripe.InvoiceMock, :list, fn _params ->
        {:error, %Stripe.Error{message: "fail", source: :api, code: :api_error}}
      end)

      assert Customers.invoices(user) == []
    end
  end

  describe "stripe_customer_params/2" do
    test "builds base Stripe customer params with title-cased name" do
      user =
        user_fixture_unique(%{
          first_name: "jane",
          last_name: "doe",
          phone_number: "+14159098268"
        })

      assert Customers.stripe_customer_params(user) == %{
               email: user.email,
               name: "Jane Doe",
               phone: "+14159098268",
               description: "User ID: #{user.id}",
               metadata: %{user_id: user.id}
             }
    end

    test "includes billing address when include_address is true" do
      user = user_fixture_unique()

      {:ok, _} =
        Ysc.Accounts.update_billing_address(user, %{
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "CA",
          "postal_code" => "94102",
          "country" => "US"
        })

      user = Ysc.Accounts.get_user!(user.id, [:billing_address])

      params = Customers.stripe_customer_params(user, include_address: true)

      assert params.address == %{
               line1: "123 Main St",
               city: "San Francisco",
               postal_code: "94102",
               country: "US",
               state: "CA"
             }
    end

    test "omits address when include_address is false" do
      user = user_fixture_unique()

      {:ok, _} =
        Ysc.Accounts.update_billing_address(user, %{
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "CA",
          "postal_code" => "94102",
          "country" => "US"
        })

      user = Ysc.Accounts.get_user!(user.id, [:billing_address])

      refute Map.has_key?(Customers.stripe_customer_params(user), :address)
    end
  end

  describe "payment_element_default_values/1" do
    test "includes email, name, phone, and full billing address" do
      user =
        user_fixture_unique(%{
          first_name: "jane",
          last_name: "doe",
          phone_number: "+14159098268"
        })

      {:ok, _} =
        Ysc.Accounts.update_billing_address(user, %{
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "CA",
          "postal_code" => "94102",
          "country" => "US"
        })

      details = Customers.payment_element_default_values(user)

      assert details == %{
               "email" => user.email,
               "name" => "Jane Doe",
               "phone" => "+14159098268",
               "address" => %{
                 "line1" => "123 Main St",
                 "city" => "San Francisco",
                 "state" => "CA",
                 "postal_code" => "94102",
                 "country" => "US"
               }
             }
    end

    test "omits phone when missing" do
      user =
        user_fixture_unique(%{
          first_name: "jane",
          last_name: "doe"
        })

      user =
        user
        |> User.update_user_changeset(%{phone_number: nil})
        |> Ysc.Repo.update!()

      details = Customers.payment_element_default_values(user)

      assert details["email"] == user.email
      assert details["name"] == "Jane Doe"
      refute Map.has_key?(details, "phone")
      refute Map.has_key?(details, "address")
    end

    test "omits address when user has none" do
      user = user_fixture_unique(%{phone_number: "+14159098268"})
      details = Customers.payment_element_default_values(user)

      refute Map.has_key?(details, "address")
      assert details["phone"] == "+14159098268"
    end

    test "omits blank address fields" do
      user = user_fixture_unique()

      {:ok, _} =
        Ysc.Accounts.update_billing_address(user, %{
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "",
          "postal_code" => "94102",
          "country" => "US"
        })

      details = Customers.payment_element_default_values(user)

      assert details["address"] == %{
               "line1" => "123 Main St",
               "city" => "San Francisco",
               "postal_code" => "94102",
               "country" => "US"
             }

      refute Map.has_key?(details["address"], "state")
    end

    test "payment_element_default_values_json encodes map" do
      user = user_fixture_unique(%{phone_number: "+14159098268"})
      json = Customers.payment_element_default_values_json(user)

      assert Jason.decode!(json)["email"] == user.email
      assert Customers.payment_element_default_values_json(nil) == "{}"
    end
  end

  describe "ensure_stripe_customer/1" do
    test "creates stripe customer when missing" do
      user = user_fixture_unique()
      assert user.stripe_id == nil

      ensured = Customers.ensure_stripe_customer(user)

      assert ensured.stripe_id
      assert String.starts_with?(ensured.stripe_id, "cus_test_")
    end

    test "returns user unchanged when stripe_id already set" do
      user = user_fixture_unique() |> update_user_stripe_id("cus_existing")

      assert Customers.ensure_stripe_customer(user).stripe_id == "cus_existing"
    end
  end

  describe "attach_customer_to_payment_intent_params/2" do
    test "attaches customer and receipt_email" do
      user =
        user_fixture_unique(%{email: "pay@example.com"})
        |> update_user_stripe_id("cus_attach")

      {params, returned_user} =
        Customers.attach_customer_to_payment_intent_params(
          %{amount: 1000},
          user
        )

      assert params.customer == "cus_attach"
      assert params.receipt_email == "pay@example.com"
      assert returned_user.id == user.id
    end

    test "creates customer when missing then attaches" do
      user = user_fixture_unique()

      {params, returned_user} =
        Customers.attach_customer_to_payment_intent_params(%{amount: 500}, user)

      assert returned_user.stripe_id
      assert params.customer == returned_user.stripe_id
      assert params.receipt_email == user.email
    end
  end

  describe "create_stripe_customer/1 and update_stripe_customer/1" do
    test "create_stripe_customer assigns stripe_id in test environment" do
      user = user_fixture_unique()
      assert user.stripe_id == nil

      assert {:ok, %Stripe.Customer{} = c} =
               Customers.create_stripe_customer(user)

      user = Ysc.Repo.get!(User, user.id)
      assert user.stripe_id == c.id
      assert String.starts_with?(user.stripe_id, "cus_test_")
    end

    test "create_stripe_customer includes billing address when present" do
      user = user_fixture_unique()

      {:ok, _} =
        Ysc.Accounts.update_billing_address(user, %{
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "CA",
          "postal_code" => "94102",
          "country" => "US"
        })

      user = Ysc.Accounts.get_user!(user.id, [:billing_address])

      parent = self()

      Mox.expect(Stripe.CustomerMock, :create, fn params, _opts ->
        send(parent, {:create_params, params})

        {:ok,
         %Stripe.Customer{
           id: "cus_addr_#{user.id}",
           email: params.email
         }}
      end)

      assert {:ok, _} = Customers.create_stripe_customer(user)

      assert_receive {:create_params, params}
      assert params.address.line1 == "123 Main St"
      assert params.address.state == "CA"
    end

    test "update_stripe_customer returns error when user has no stripe_id" do
      user = user_fixture_unique()

      assert Customers.update_stripe_customer(user) ==
               {:error, :no_stripe_customer}
    end

    test "update_stripe_customer succeeds in test when stripe_id is set" do
      user = user_fixture_unique() |> update_user_stripe_id("cus_update_test")

      assert {:ok, %Stripe.Customer{id: "cus_update_test"}} =
               Customers.update_stripe_customer(user)
    end
  end

  describe "create_setup_intent/2" do
    defmodule SetupIntentParamsCapture do
      @moduledoc false
      def create(params) do
        send(self(), {:setup_intent_params, params})
        Ysc.TestStripeSetupIntent.create(params)
      end
    end

    setup do
      original = Application.get_env(:ysc, :stripe_setup_intent_module)

      Application.put_env(
        :ysc,
        :stripe_setup_intent_module,
        SetupIntentParamsCapture
      )

      on_exit(fn ->
        Application.put_env(
          :ysc,
          :stripe_setup_intent_module,
          original
        )
      end)

      :ok
    end

    test "includes Stripe Link in default payment_method_types" do
      user = user_fixture_unique() |> update_user_stripe_id("cus_setup_link")

      assert {:ok, %Stripe.SetupIntent{}} = Customers.create_setup_intent(user)

      assert_receive {:setup_intent_params,
                      %{
                        payment_method_types: [
                          "card",
                          "us_bank_account",
                          "link"
                        ],
                        customer: "cus_setup_link",
                        usage: "off_session"
                      }}
    end

    test "honors stripe payment_method_types override" do
      user =
        user_fixture_unique() |> update_user_stripe_id("cus_setup_override")

      assert {:ok, %Stripe.SetupIntent{}} =
               Customers.create_setup_intent(user,
                 stripe: %{payment_method_types: ["card"]}
               )

      assert_receive {:setup_intent_params,
                      %{
                        payment_method_types: ["card"],
                        customer: "cus_setup_override"
                      }}
    end
  end

  describe "create_subscription/2" do
    test "returns error for sub-accounts" do
      primary = user_fixture_unique()

      sub =
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: "sub#{System.unique_integer([:positive])}@example.com",
            password: valid_user_password(),
            first_name: "Sub",
            last_name: "Account",
            phone_number: "+14159098268",
            date_of_birth: ~D[1990-01-01]
          },
          primary.id,
          hash_password: true,
          validate_email: true
        )
        |> Ysc.Repo.insert!()

      assert Customers.create_subscription(sub, %{}) ==
               {:error, :sub_accounts_cannot_create_subscriptions}
    end
  end

  # Helper function
  defp update_user_stripe_id(user, stripe_id) do
    user
    |> User.update_user_changeset(%{stripe_id: stripe_id})
    |> Ysc.Repo.update!()
  end
end
