defmodule Ysc.SubscriptionsActivationTest do
  # async: false — mutates Application env `:membership_plans`
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.MembershipCache
  alias Ysc.Payments
  alias Ysc.Subscriptions

  setup :verify_on_exit!

  defp user_with_default_pm(attrs \\ %{}) do
    user =
      user_fixture(
        Map.merge(
          %{
            state: :active
          },
          attrs
        )
      )

    user =
      user
      |> Ysc.Accounts.User.update_user_changeset(%{
        stripe_id: "cus_act_#{System.unique_integer([:positive])}"
      })
      |> Ysc.Repo.update!()

    {:ok, _pm} =
      Payments.insert_payment_method(%{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_act_#{System.unique_integer([:positive])}",
        provider_customer_id: user.stripe_id,
        type: :card,
        provider_type: "card",
        is_default: true
      })

    user
  end

  describe "activate_membership_with_saved_payment_method/2" do
    test "returns error when return_url is missing" do
      user = user_with_default_pm()

      assert {:error, :missing_return_url} =
               Subscriptions.activate_membership_with_saved_payment_method(user)
    end

    test "returns error when no payment method is on file" do
      user =
        user_fixture(%{
          state: :active,
          stripe_id: "cus_act_#{System.unique_integer([:positive])}"
        })

      assert {:error, :no_payment_method} =
               Subscriptions.activate_membership_with_saved_payment_method(
                 user,
                 return_url: "http://localhost/finalize"
               )
    end

    test "returns already_active when a blocking subscription exists" do
      user = user_with_default_pm()

      {:ok, _sub} =
        Subscriptions.create_subscription(%{
          name: "Existing",
          stripe_id: "sub_existing_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          user_id: user.id,
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      assert {:ok, :already_active} =
               Subscriptions.activate_membership_with_saved_payment_method(
                 user,
                 return_url: "http://localhost/finalize"
               )
    end

    test "retries an incomplete subscription with the saved payment method" do
      user = user_with_default_pm()
      stripe_sub_id = "sub_incomplete_#{System.unique_integer([:positive])}"
      invoice_id = "in_act_retry_#{System.unique_integer([:positive])}"

      {:ok, _incomplete_sub} =
        Subscriptions.create_subscription(%{
          name: "Incomplete",
          stripe_id: stripe_sub_id,
          stripe_status: "incomplete",
          user_id: user.id,
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      default_pm = Payments.get_default_payment_method(user)

      expect(Stripe.SubscriptionMock, :update, fn ^stripe_sub_id, params ->
        assert params[:default_payment_method] == default_pm.provider_id

        {:ok,
         %Stripe.Subscription{
           id: stripe_sub_id,
           status: "incomplete",
           latest_invoice: %Stripe.Invoice{id: invoice_id}
         }}
      end)

      expect(Stripe.InvoiceMock, :pay, fn ^invoice_id, params ->
        assert params[:payment_method] == default_pm.provider_id
        {:ok, %Stripe.Invoice{id: invoice_id, status: "paid"}}
      end)

      expect(Stripe.SubscriptionMock, :retrieve, fn ^stripe_sub_id ->
        {:ok,
         Ysc.Stripe.SubscriptionFixtures.subscription(
           id: stripe_sub_id,
           customer: user.stripe_id,
           status: "active"
         )}
      end)

      assert {:ok, :activated} =
               Subscriptions.activate_membership_with_saved_payment_method(
                 user,
                 membership_type: :single,
                 return_url: "http://localhost/finalize"
               )

      # Local status is synced by Stripe webhooks; the critical outcome is that
      # activation entered the incomplete-subscription retry path instead of
      # short-circuiting to :already_active.
      assert %Subscriptions.Subscription{stripe_id: ^stripe_sub_id} =
               Subscriptions.get_subscription_by_stripe_id(stripe_sub_id)
    end

    test "creates stripe subscription and persists locally" do
      user = user_with_default_pm()
      stripe_sub_id = "sub_new_#{System.unique_integer([:positive])}"

      expect(Stripe.SubscriptionMock, :create, fn params ->
        assert params.customer == user.stripe_id
        assert is_binary(params.default_payment_method)

        {:ok,
         Ysc.Stripe.SubscriptionFixtures.subscription(
           id: stripe_sub_id,
           customer: user.stripe_id,
           status: "active"
         )}
      end)

      assert {:ok, :activated} =
               Subscriptions.activate_membership_with_saved_payment_method(
                 user,
                 membership_type: :single,
                 return_url: "http://localhost/finalize"
               )

      assert %Subscriptions.Subscription{} =
               Subscriptions.get_subscription_by_stripe_id(stripe_sub_id)

      _ = MembershipCache.invalidate_user(user.id)
      assert MembershipCache.get_active_membership(user)
    end

    test "returns already_active when Stripe reports an existing subscription" do
      user = user_with_default_pm()

      expect(Stripe.SubscriptionMock, :create, fn _params ->
        {:error, :user_already_has_active_subscription}
      end)

      assert {:ok, :already_active} =
               Subscriptions.activate_membership_with_saved_payment_method(
                 user,
                 return_url: "http://localhost/finalize"
               )
    end

    test "returns error when Stripe subscription create fails" do
      user = user_with_default_pm()

      expect(Stripe.SubscriptionMock, :create, fn _params ->
        {:error,
         %Stripe.Error{
           message: "card declined",
           code: "card_declined",
           source: :stripe
         }}
      end)

      assert {:error,
              %Stripe.Error{
                message: "card declined",
                code: "card_declined",
                source: :stripe
              }} =
               Subscriptions.activate_membership_with_saved_payment_method(
                 user,
                 return_url: "http://localhost/finalize"
               )
    end

    test "returns error when membership price id is not configured" do
      user = user_with_default_pm()
      plans = Application.get_env(:ysc, :membership_plans)

      on_exit(fn -> Application.put_env(:ysc, :membership_plans, plans) end)
      Application.put_env(:ysc, :membership_plans, [])

      assert {:error, :no_price_id} =
               Subscriptions.activate_membership_with_saved_payment_method(
                 user,
                 return_url: "http://localhost/finalize"
               )
    end

    test "still returns activated when local persistence fails after Stripe success" do
      user = user_with_default_pm()
      stripe_sub_id = "sub_dup_#{System.unique_integer([:positive])}"

      {:ok, _} =
        Subscriptions.create_subscription(%{
          name: "Collision",
          stripe_id: stripe_sub_id,
          stripe_status: "canceled",
          user_id: user.id,
          current_period_end: DateTime.add(DateTime.utc_now(), -1, :day)
        })

      expect(Stripe.SubscriptionMock, :create, fn _params ->
        {:ok,
         Ysc.Stripe.SubscriptionFixtures.subscription(
           id: stripe_sub_id,
           customer: user.stripe_id,
           status: "active"
         )}
      end)

      assert {:ok, :activated} =
               Subscriptions.activate_membership_with_saved_payment_method(
                 user,
                 return_url: "http://localhost/finalize"
               )
    end
  end
end
