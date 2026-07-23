defmodule Ysc.SubscriptionsPlanChangeTest do
  @moduledoc """
  Tests for plan change behavior (upgrade/downgrade), especially when Stripe
  returns "incomplete" (e.g. manual membership with no payment method).
  Uses async: false because tests set Application callbacks.
  """
  use Ysc.DataCase, async: false

  import Mox

  alias Ysc.Accounts
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription
  import Ysc.AccountsFixtures

  describe "change_membership_plan upgrade with Stripe status incomplete" do
    test "leaves DB unchanged when Stripe returns status incomplete (e.g. no payment method)" do
      # Manual (paid elsewhere) members have no payment method; upgrade creates an
      # invoice that cannot be paid, so Stripe sets status to "incomplete". We must
      # not overwrite our DB so the user keeps membership until payment completes.
      user = user_fixture()
      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))
      family_plan = Enum.find(plans, &(&1.id == :family))

      assert single_plan && family_plan,
             "membership_plans must include single and family"

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_incomplete_test_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_incomplete_#{System.unique_integer()}",
          stripe_product_id: "prod_single",
          stripe_price_id: single_plan.stripe_price_id,
          quantity: 1
        })

      subscription = Repo.preload(subscription, :subscription_items)

      stripe_sub_initial =
        Ysc.Stripe.SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          items: %Stripe.List{
            data: [
              %{
                id: "si_incomplete",
                price: single_plan.stripe_price_id,
                quantity: 1
              }
            ],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          },
          schedule: nil
        )

      ts = System.os_time(:second)

      stripe_sub_incomplete =
        Ysc.Stripe.SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          status: "incomplete",
          current_period_start: ts,
          current_period_end: ts + 30 * 24 * 60 * 60
        )

      try do
        Application.put_env(
          :ysc,
          :subscription_retrieve_initial_plan_change_callback,
          fn _sid, _opts ->
            {:ok, stripe_sub_initial}
          end
        )

        Application.put_env(
          :ysc,
          :subscription_update_plan_change_callback,
          fn _sid, _params ->
            {:ok, %Stripe.Subscription{}}
          end
        )

        Application.put_env(
          :ysc,
          :subscription_retrieve_after_plan_change_callback,
          fn _sid ->
            {:ok, stripe_sub_incomplete}
          end
        )

        assert {:ok, returned_sub} =
                 Subscriptions.change_membership_plan(
                   subscription,
                   family_plan.stripe_price_id,
                   :upgrade
                 )

        # Returned subscription is the same record (we did not persist "incomplete")
        assert returned_sub.id == subscription.id

        # DB must still show active so user keeps membership
        reloaded = Repo.get!(Subscription, subscription.id)

        assert reloaded.stripe_status == "active",
               "Expected stripe_status to remain active when Stripe returned incomplete"
      after
        Application.delete_env(
          :ysc,
          :subscription_retrieve_initial_plan_change_callback
        )

        Application.delete_env(:ysc, :subscription_update_plan_change_callback)

        Application.delete_env(
          :ysc,
          :subscription_retrieve_after_plan_change_callback
        )
      end
    end

    test "updates DB when Stripe returns status active after plan change" do
      user = user_fixture()
      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))
      family_plan = Enum.find(plans, &(&1.id == :family))

      assert single_plan && family_plan,
             "membership_plans must include single and family"

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_active_after_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_active_#{System.unique_integer()}",
          stripe_product_id: "prod_single",
          stripe_price_id: single_plan.stripe_price_id,
          quantity: 1
        })

      subscription = Repo.preload(subscription, :subscription_items)

      stripe_sub_initial =
        Ysc.Stripe.SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          items: %Stripe.List{
            data: [
              %{id: "si_act", price: single_plan.stripe_price_id, quantity: 1}
            ],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          },
          schedule: nil
        )

      ts = System.os_time(:second)

      stripe_sub_active =
        Ysc.Stripe.SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          status: "active",
          current_period_start: ts,
          current_period_end: ts + 30 * 24 * 60 * 60
        )

      try do
        Application.put_env(
          :ysc,
          :subscription_retrieve_initial_plan_change_callback,
          fn _sid, _opts ->
            {:ok, stripe_sub_initial}
          end
        )

        Application.put_env(
          :ysc,
          :subscription_update_plan_change_callback,
          fn _sid, _params ->
            {:ok, %Stripe.Subscription{}}
          end
        )

        Application.put_env(
          :ysc,
          :subscription_retrieve_after_plan_change_callback,
          fn _sid ->
            {:ok, stripe_sub_active}
          end
        )

        assert {:ok, returned_sub} =
                 Subscriptions.change_membership_plan(
                   subscription,
                   family_plan.stripe_price_id,
                   :upgrade
                 )

        assert returned_sub.id == subscription.id

        reloaded = Repo.get!(Subscription, subscription.id)
        assert reloaded.stripe_status == "active"
        assert reloaded.current_period_end != nil
      after
        Application.delete_env(
          :ysc,
          :subscription_retrieve_initial_plan_change_callback
        )

        Application.delete_env(:ysc, :subscription_update_plan_change_callback)

        Application.delete_env(
          :ysc,
          :subscription_retrieve_after_plan_change_callback
        )
      end
    end

    test "uses proration_behavior none when upgrading a board household membership" do
      user = user_fixture()
      {:ok, user} = Ysc.Accounts.assign_board_position(user, :president)

      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))
      family_plan = Enum.find(plans, &(&1.id == :family))

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_board_upgrade_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_board_#{System.unique_integer()}",
          stripe_product_id: "prod_single",
          stripe_price_id: single_plan.stripe_price_id,
          quantity: 1
        })

      subscription = Repo.preload(subscription, [:subscription_items, :user])

      stripe_sub_initial =
        Ysc.Stripe.SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          items: %Stripe.List{
            data: [
              %{
                id: "si_board",
                price: single_plan.stripe_price_id,
                quantity: 1
              }
            ],
            has_more: false,
            object: "list",
            url: "/v1/subscription_items"
          },
          schedule: nil
        )

      ts = System.os_time(:second)

      stripe_sub_active =
        Ysc.Stripe.SubscriptionFixtures.subscription(
          id: subscription.stripe_id,
          status: "active",
          current_period_start: ts,
          current_period_end: ts + 30 * 24 * 60 * 60
        )

      try do
        Application.put_env(
          :ysc,
          :subscription_retrieve_initial_plan_change_callback,
          fn _sid, _opts ->
            {:ok, stripe_sub_initial}
          end
        )

        Application.put_env(
          :ysc,
          :subscription_update_plan_change_callback,
          fn _sid, params ->
            assert params.proration_behavior == "none"
            {:ok, %Stripe.Subscription{}}
          end
        )

        Application.put_env(
          :ysc,
          :subscription_retrieve_after_plan_change_callback,
          fn _sid ->
            {:ok, stripe_sub_active}
          end
        )

        assert {:ok, _returned_sub} =
                 Subscriptions.change_membership_plan(
                   subscription,
                   family_plan.stripe_price_id,
                   :upgrade
                 )
      after
        Application.delete_env(
          :ysc,
          :subscription_retrieve_initial_plan_change_callback
        )

        Application.delete_env(:ysc, :subscription_update_plan_change_callback)

        Application.delete_env(
          :ysc,
          :subscription_retrieve_after_plan_change_callback
        )
      end
    end
  end

  describe "create_stripe_subscription/2 board billing" do
    test "merges pause_collection into Stripe create params for board households" do
      user =
        user_fixture(%{stripe_id: "cus_board_create_#{System.unique_integer()}"})

      {:ok, user} = Accounts.assign_board_position(user, :president)

      params = %{
        prices: [%{price: "price_board_test", quantity: 1}]
      }

      expect(Stripe.SubscriptionMock, :create, fn stripe_params ->
        assert stripe_params.pause_collection == %{behavior: :void}
        assert stripe_params.cancel_at_period_end == false
        assert stripe_params.customer == user.stripe_id

        {:ok,
         Ysc.Stripe.SubscriptionFixtures.subscription(
           id: "sub_board_#{System.unique_integer()}"
         )}
      end)

      assert {:ok, %Stripe.Subscription{}} =
               Subscriptions.create_stripe_subscription(user, params)

      verify!()
    end
  end
end
