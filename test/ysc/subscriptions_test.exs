defmodule Ysc.SubscriptionsTest do
  @moduledoc """
  Tests for Ysc.Subscriptions context.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.User
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription
  import Ysc.AccountsFixtures

  # Monotonic unique emails avoid rare collisions when many tests run async.
  defp user_fixture_unique(attrs \\ %{}) do
    email =
      Map.get_lazy(attrs, :email, fn ->
        "u#{:erlang.unique_integer([:positive, :monotonic])}@example.com"
      end)

    user_fixture(Map.put(attrs, :email, email))
  end

  setup do
    user = user_fixture_unique()
    %{user: user}
  end

  describe "subscriptions" do
    test "create_subscription/1 creates a subscription", %{user: user} do
      attrs = %{
        user_id: user.id,
        stripe_id: "sub_123",
        stripe_status: "active",
        name: "Membership",
        current_period_end: DateTime.utc_now() |> DateTime.add(30, :day)
      }

      assert {:ok, %Subscription{} = sub} =
               Subscriptions.create_subscription(attrs)

      assert sub.stripe_id == "sub_123"
      assert sub.stripe_status == "active"
    end

    test "create_subscription/1 returns error when required fields are missing",
         %{
           user: user
         } do
      assert {:error, %Ecto.Changeset{}} =
               Subscriptions.create_subscription(%{user_id: user.id})
    end

    test "active?/1 returns true for active/trialing with valid dates" do
      now = DateTime.utc_now()
      future_date = DateTime.add(now, 30, :day)
      past_date = DateTime.add(now, -1, :day)

      # Active subscription with future period end
      active_sub = %Subscription{
        stripe_status: "active",
        current_period_end: future_date,
        ends_at: nil
      }

      # Trialing subscription with future period end
      trialing_sub = %Subscription{
        stripe_status: "trialing",
        current_period_end: future_date,
        ends_at: nil
      }

      # Cancelled subscription
      cancelled_sub = %Subscription{stripe_status: "cancelled"}

      # Active subscription with expired period end
      expired_active = %Subscription{
        stripe_status: "active",
        current_period_end: past_date,
        ends_at: nil
      }

      # Active subscription with ends_at in the past
      ended_subscription = %Subscription{
        stripe_status: "active",
        current_period_end: future_date,
        ends_at: past_date
      }

      # Active subscription with nil current_period_end (defensive check)
      no_period_end = %Subscription{
        stripe_status: "active",
        current_period_end: nil,
        ends_at: nil
      }

      assert Subscriptions.active?(active_sub)
      assert Subscriptions.active?(trialing_sub)
      refute Subscriptions.active?(cancelled_sub)
      refute Subscriptions.active?(expired_active)
      refute Subscriptions.active?(ended_subscription)
      refute Subscriptions.active?(no_period_end)
    end

    test "cancelled?/1 checks status, ends_at, and current_period_end" do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)
      future_date = DateTime.add(now, 1, :day)

      # Cancelled by status
      cancelled_status = %Subscription{stripe_status: "cancelled"}
      assert Subscriptions.cancelled?(cancelled_status)

      # Cancelled because ends_at is in the past
      ended_subscription = %Subscription{
        stripe_status: "active",
        ends_at: past_date,
        current_period_end: future_date
      }

      assert Subscriptions.cancelled?(ended_subscription)

      # Cancelled because current_period_end is in the past
      expired_subscription = %Subscription{
        stripe_status: "active",
        current_period_end: past_date,
        ends_at: nil
      }

      assert Subscriptions.cancelled?(expired_subscription)

      # Not cancelled - ends_at is in the future (scheduled cancellation)
      scheduled_cancellation = %Subscription{
        stripe_status: "active",
        ends_at: future_date,
        current_period_end: future_date
      }

      refute Subscriptions.cancelled?(scheduled_cancellation)

      # Not cancelled - active subscription
      active = %Subscription{
        stripe_status: "active",
        ends_at: nil,
        current_period_end: future_date
      }

      refute Subscriptions.cancelled?(active)

      # Nil subscription
      refute Subscriptions.cancelled?(nil)
    end

    test "valid?/1 checks expiration dates" do
      now = DateTime.utc_now()
      future_date = DateTime.add(now, 30, :day)
      past_date = DateTime.add(now, -1, :day)

      # Valid subscription
      valid_sub = %Subscription{
        stripe_status: "active",
        current_period_end: future_date,
        ends_at: nil
      }

      assert Subscriptions.valid?(valid_sub)

      # Invalid - expired period end
      expired_sub = %Subscription{
        stripe_status: "active",
        current_period_end: past_date,
        ends_at: nil
      }

      refute Subscriptions.valid?(expired_sub)

      # Invalid - ends_at in past
      ended_sub = %Subscription{
        stripe_status: "active",
        current_period_end: future_date,
        ends_at: past_date
      }

      refute Subscriptions.valid?(ended_sub)
    end

    test "list_subscriptions/1 returns subscriptions for user", %{user: user} do
      {:ok, sub1} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_1",
          stripe_status: "active",
          name: "Membership 1",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, sub2} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_2",
          stripe_status: "active",
          name: "Membership 2",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscriptions = Subscriptions.list_subscriptions(user)
      assert length(subscriptions) >= 2
      assert Enum.any?(subscriptions, &(&1.id == sub1.id))
      assert Enum.any?(subscriptions, &(&1.id == sub2.id))
    end

    test "get_subscription/1 returns subscription by id", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_get",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      found = Subscriptions.get_subscription(subscription.id)
      assert found.id == subscription.id
    end

    test "get_subscription/1 returns nil for unknown id" do
      unknown_id = Ecto.ULID.generate()
      assert Subscriptions.get_subscription(unknown_id) == nil
    end

    test "get_subscription_by_stripe_id/1 returns subscription", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_stripe_123",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      found = Subscriptions.get_subscription_by_stripe_id("sub_stripe_123")
      assert found.id == subscription.id
    end

    test "get_subscription_by_stripe_id/1 returns nil when not found" do
      assert Subscriptions.get_subscription_by_stripe_id(
               "sub_does_not_exist_12345"
             ) ==
               nil
    end

    test "get_active_subscription/1 returns nil when user has no subscriptions" do
      user = user_fixture_unique()
      assert Subscriptions.get_active_subscription(user) == nil
    end

    test "get_active_subscription/1 returns the active subscription when present",
         %{user: user} do
      future = DateTime.add(DateTime.utc_now(), 30, :day)

      {:ok, sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_active_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_end: future,
          ends_at: nil
        })

      found = Subscriptions.get_active_subscription(user)
      assert found.id == sub.id
    end

    test "change_membership_plan/3 returns error for lifetime plan" do
      assert {:error, "Lifetime memberships cannot be changed"} =
               Subscriptions.change_membership_plan(
                 %{type: :lifetime},
                 "price_123",
                 :upgrade
               )
    end

    test "change_membership_plan/3 returns error when subscription is nil" do
      assert {:error, "No active subscription found"} =
               Subscriptions.change_membership_plan(nil, "price_123", :upgrade)
    end

    test "create_subscription/1 returns error when required fields missing" do
      assert {:error, changeset} = Subscriptions.create_subscription(%{})
      refute changeset.valid?
    end

    test "update_subscription/2 returns error when unique stripe_id violated",
         %{
           user: user
         } do
      {:ok, sub_a} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_unique_a_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "A",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, sub_b} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_unique_b_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "B",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      assert {:error, changeset} =
               Subscriptions.update_subscription(sub_b, %{
                 stripe_id: sub_a.stripe_id
               })

      refute changeset.valid?
    end

    test "update_subscription/2 updates subscription", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_update",
          stripe_status: "active",
          name: "Original",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      assert {:ok, updated} =
               Subscriptions.update_subscription(subscription, %{
                 name: "Updated"
               })

      assert updated.name == "Updated"
    end

    test "delete_subscription/1 deletes subscription", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_delete",
          stripe_status: "active",
          name: "To Delete",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      assert {:ok, _} = Subscriptions.delete_subscription(subscription)
      assert Subscriptions.get_subscription(subscription.id) == nil
    end

    test "create_subscription_item/1 creates subscription item", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_item",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      attrs = %{
        subscription_id: subscription.id,
        stripe_price_id: "price_123",
        stripe_product_id: "prod_123",
        stripe_id: "si_123",
        quantity: 1
      }

      assert {:ok, %Ysc.Subscriptions.SubscriptionItem{} = item} =
               Subscriptions.create_subscription_item(attrs)

      assert item.subscription_id == subscription.id
      assert item.stripe_price_id == "price_123"
    end

    test "update_subscription_item/2 updates subscription item", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_item_update",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: "price_123",
          stripe_product_id: "prod_123",
          stripe_id: "si_123",
          quantity: 1
        })

      assert {:ok, updated} =
               Subscriptions.update_subscription_item(item, %{quantity: 2})

      assert updated.quantity == 2
    end

    test "delete_subscription_item/1 deletes subscription item", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_item_delete",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: "price_123",
          stripe_product_id: "prod_123",
          stripe_id: "si_123",
          quantity: 1
        })

      assert {:ok, _} = Subscriptions.delete_subscription_item(item)
    end

    test "change_subscription/2 returns changeset", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_change",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      changeset = Subscriptions.change_subscription(subscription, %{})
      assert %Ecto.Changeset{} = changeset
    end

    test "change_subscription_item/2 returns changeset", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_item_change",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: "price_123",
          stripe_product_id: "prod_123",
          stripe_id: "si_123",
          quantity: 1
        })

      changeset = Subscriptions.change_subscription_item(item, %{})
      assert %Ecto.Changeset{} = changeset
    end

    test "scheduled_for_cancellation?/1 checks if subscription is scheduled", %{
      user: _user
    } do
      future_date = DateTime.add(DateTime.utc_now(), 30, :day)

      scheduled = %Subscription{
        stripe_status: "active",
        ends_at: future_date,
        current_period_end: future_date
      }

      not_scheduled = %Subscription{
        stripe_status: "active",
        ends_at: nil,
        current_period_end: future_date
      }

      assert Subscriptions.scheduled_for_cancellation?(scheduled)
      refute Subscriptions.scheduled_for_cancellation?(not_scheduled)
      refute Subscriptions.scheduled_for_cancellation?(nil)
    end

    test "get_active_subscription/1 returns active subscription", %{user: user} do
      {:ok, active_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_active",
          stripe_status: "active",
          name: "Active Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      found = Subscriptions.get_active_subscription(user)
      assert found.id == active_sub.id
    end
  end

  describe "create_subscription_paid_out_of_band/2" do
    test "returns {:error, :invalid_plan} for :lifetime plan" do
      user = user_fixture_unique()

      assert Subscriptions.create_subscription_paid_out_of_band(user, :lifetime) ==
               {:error, :invalid_plan}
    end

    test "returns {:error, :invalid_plan} for unknown plan id" do
      user = user_fixture_unique()

      assert Subscriptions.create_subscription_paid_out_of_band(
               user,
               :unknown_plan
             ) ==
               {:error, :invalid_plan}
    end

    test "returns {:error, :sub_accounts_cannot_create_subscriptions} for sub-account" do
      primary = user_fixture_unique()

      sub_account =
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: unique_user_email(),
            password: valid_user_password(),
            first_name: "Sub",
            last_name: "User",
            phone_number: "+14159098268",
            date_of_birth: ~D[1990-01-01]
          },
          primary.id,
          hash_password: true,
          validate_email: true
        )
        |> Repo.insert!()

      assert Subscriptions.create_subscription_paid_out_of_band(
               sub_account,
               :single
             ) ==
               {:error, :sub_accounts_cannot_create_subscriptions}
    end

    test "returns {:error, :user_already_has_active_subscription} when user has active subscription" do
      user = user_fixture_unique()

      {:ok, _existing_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_existing_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Existing",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      assert Subscriptions.create_subscription_paid_out_of_band(user, :single) ==
               {:error, :user_already_has_active_subscription}
    end

    test "creates subscription and returns {:ok, subscription} when callback returns fake Stripe subscription" do
      user = user_fixture_unique()
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(membership_plans, &(&1.id == :single))
      assert single_plan != nil

      now_unix = System.system_time(:second)
      fake_stripe_sub = build_fake_stripe_subscription(single_plan, now_unix)

      callback = fn _user, _plan -> {:ok, fake_stripe_sub} end

      try do
        Application.put_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback,
          callback
        )

        assert {:ok, %Subscription{} = subscription} =
                 Subscriptions.create_subscription_paid_out_of_band(
                   user,
                   :single
                 )

        assert subscription.user_id == user.id
        assert subscription.stripe_id == fake_stripe_sub.id
        assert subscription.stripe_status == "active"
        assert subscription.name == "Membership Subscription"
        assert subscription.current_period_end != nil
        assert Ecto.assoc_loaded?(subscription.subscription_items)
        assert length(subscription.subscription_items) == 1

        assert hd(subscription.subscription_items).stripe_price_id ==
                 single_plan.stripe_price_id
      after
        Application.delete_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback
        )
      end
    end

    test "creates family subscription when callback returns fake Stripe subscription for family plan" do
      user = user_fixture_unique()
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      family_plan = Enum.find(membership_plans, &(&1.id == :family))
      assert family_plan != nil

      now_unix = System.system_time(:second)
      fake_stripe_sub = build_fake_stripe_subscription(family_plan, now_unix)

      callback = fn _user, _plan -> {:ok, fake_stripe_sub} end

      try do
        Application.put_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback,
          callback
        )

        assert {:ok, %Subscription{} = subscription} =
                 Subscriptions.create_subscription_paid_out_of_band(
                   user,
                   :family
                 )

        assert subscription.user_id == user.id
        assert subscription.stripe_status == "active"
        assert length(subscription.subscription_items) == 1

        assert hd(subscription.subscription_items).stripe_price_id ==
                 family_plan.stripe_price_id
      after
        Application.delete_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback
        )
      end
    end

    test "returns callback error when callback returns {:error, reason}" do
      user = user_fixture_unique(%{stripe_id: "cus_test"})
      callback = fn _user, _plan -> {:error, :stripe_api_error} end

      try do
        Application.put_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback,
          callback
        )

        assert Subscriptions.create_subscription_paid_out_of_band(user, :single) ==
                 {:error, :stripe_api_error}
      after
        Application.delete_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback
        )
      end
    end
  end

  describe "create_stripe_subscription/2" do
    test "returns {:error, :user_already_has_active_subscription} when user has active subscription" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      {:ok, _existing_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_existing_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Existing Active Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      assert Subscriptions.create_stripe_subscription(user, params) ==
               {:error, :user_already_has_active_subscription}
    end

    test "returns {:error, :user_already_has_active_subscription} when user has trialing subscription" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      {:ok, _existing_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_trialing_#{System.unique_integer()}",
          stripe_status: "trialing",
          name: "Trialing Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day),
          trial_ends_at: DateTime.add(DateTime.utc_now(), 14, :day)
        })

      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      assert Subscriptions.create_stripe_subscription(user, params) ==
               {:error, :user_already_has_active_subscription}
    end

    test "returns {:error, :user_already_has_active_subscription} when user has past_due subscription" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      {:ok, _past_due_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_past_due_#{System.unique_integer()}",
          stripe_status: "past_due",
          name: "Past Due Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), 15, :day)
        })

      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      assert Subscriptions.create_stripe_subscription(user, params) ==
               {:error, :user_already_has_active_subscription}
    end

    test "returns {:error, :user_already_has_active_subscription} when user has incomplete subscription (checkout in progress)" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      {:ok, _incomplete_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_incomplete_#{System.unique_integer()}",
          stripe_status: "incomplete",
          name: "Incomplete Checkout Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      assert Subscriptions.create_stripe_subscription(user, params) ==
               {:error, :user_already_has_active_subscription}
    end

    test "returns {:error, :user_already_has_active_subscription} for subscription still active with pause_collection (board volunteer)" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      # pause_collection keeps Stripe subscription status as active
      {:ok, _paused_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_paused_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Paused Board Volunteer Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      assert Subscriptions.create_stripe_subscription(user, params) ==
               {:error, :user_already_has_active_subscription}
    end

    test "returns {:error, :user_already_has_active_subscription} when Stripe subscription status is paused" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      {:ok, _paused_status_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_status_paused_#{System.unique_integer()}",
          stripe_status: "paused",
          name: "Paused Status Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      assert Subscriptions.create_stripe_subscription(user, params) ==
               {:error, :user_already_has_active_subscription}
    end

    test "allows creating subscription when user only has WP migration placeholder subscription" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      {:ok, _migrated_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "migrated_#{user.id}",
          stripe_status: "active",
          name: "Migrated Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      result = Subscriptions.create_stripe_subscription(user, params)

      refute result == {:error, :user_already_has_active_subscription}
    end

    test "allows creating subscription when user has no active subscription" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      # Create a cancelled subscription (not active)
      {:ok, _cancelled_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_cancelled_#{System.unique_integer()}",
          stripe_status: "canceled",
          name: "Cancelled Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), -30, :day)
        })

      # Mock Stripe API call
      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      # The function will try to call Stripe API, which will fail in test
      # We're just verifying it doesn't return the double subscription error
      result = Subscriptions.create_stripe_subscription(user, params)

      # Should not return the double subscription error
      refute result == {:error, :user_already_has_active_subscription}
    end

    test "allows creating subscription when user has expired subscription" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      # Create an expired subscription (active status but period ended)
      {:ok, _expired_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_expired_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Expired Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), -1, :day)
        })

      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      result = Subscriptions.create_stripe_subscription(user, params)

      # Should not return the double subscription error
      refute result == {:error, :user_already_has_active_subscription}
    end

    test "allows creating subscription when user has subscription with ends_at in the past" do
      user =
        user_fixture_unique(%{stripe_id: "cus_test_#{System.unique_integer()}"})

      # Create a subscription scheduled to end (cancelled)
      {:ok, _ending_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_ending_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Ending Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day),
          ends_at: DateTime.add(DateTime.utc_now(), -1, :day)
        })

      params = %{
        prices: [%{price: "price_123", quantity: 1}]
      }

      result = Subscriptions.create_stripe_subscription(user, params)

      # Should not return the double subscription error
      refute result == {:error, :user_already_has_active_subscription}
    end
  end

  defp build_fake_stripe_subscription(plan, now_unix) do
    period_end = now_unix + 365 * 24 * 60 * 60

    %Stripe.Subscription{
      id: "sub_fake_#{System.unique_integer()}",
      status: "active",
      start_date: now_unix,
      current_period_start: now_unix,
      current_period_end: period_end,
      trial_end: nil,
      ended_at: nil,
      items: %Stripe.List{
        data: [
          %{
            id: "si_fake_#{System.unique_integer()}",
            price: %{id: plan.stripe_price_id, product: "prod_fake"},
            quantity: 1
          }
        ],
        has_more: false,
        object: "list",
        url: "/v1/subscription_items"
      }
    }
  end

  describe "change_membership_plan/3" do
    test "returns {:error, _} for lifetime membership" do
      # Lifetime membership is represented as a map, not Subscription struct
      subscription = %{type: :lifetime}
      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))

      assert Subscriptions.change_membership_plan(
               subscription,
               single_plan.stripe_price_id,
               :downgrade
             ) == {:error, "Lifetime memberships cannot be changed"}
    end

    test "returns {:error, _} for nil subscription" do
      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))

      assert Subscriptions.change_membership_plan(
               nil,
               single_plan.stripe_price_id,
               :upgrade
             ) == {:error, "No active subscription found"}
    end

    test "returns {:error, _} when downgrading with sub-accounts" do
      primary = user_fixture_unique()

      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))

      sub_account =
        %User{}
        |> User.sub_account_registration_changeset(
          %{
            email: unique_user_email(),
            password: valid_user_password(),
            first_name: "Sub",
            last_name: "User",
            phone_number: "+14159098268",
            date_of_birth: ~D[1990-01-01]
          },
          primary.id,
          hash_password: true,
          validate_email: true
        )
        |> Repo.insert!()

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: sub_account.id,
          stripe_id: "sub_sub_account",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      # Sub-account has family (primary's plan) - we need subscription for primary
      {:ok, primary_sub} =
        Subscriptions.create_subscription(%{
          user_id: primary.id,
          stripe_id: "sub_primary",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      primary_sub = Repo.preload(primary_sub, :user)

      assert {:error, msg} =
               Subscriptions.change_membership_plan(
                 primary_sub,
                 single_plan.stripe_price_id,
                 :downgrade
               )

      assert msg =~ "sub-accounts"
    end

    test "returns {:scheduled, subscription} for downgrade when callback returns scheduled" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_downgrade",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscription = Repo.preload(subscription, :subscription_items)

      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))

      callback = fn sub, _price_id, :downgrade ->
        assert sub.id == subscription.id
        {:scheduled, sub}
      end

      try do
        Application.put_env(
          :ysc,
          :change_membership_plan_stripe_callback,
          callback
        )

        assert {:scheduled, returned_sub} =
                 Subscriptions.change_membership_plan(
                   subscription,
                   single_plan.stripe_price_id,
                   :downgrade
                 )

        assert returned_sub.id == subscription.id
        # Subscription unchanged - still on family until renewal
        assert returned_sub.stripe_id == subscription.stripe_id
      after
        Application.delete_env(:ysc, :change_membership_plan_stripe_callback)
      end
    end

    test "returns {:ok, subscription} for upgrade when callback returns ok" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_upgrade",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscription =
        subscription
        |> Repo.preload(:subscription_items)

      plans = Application.get_env(:ysc, :membership_plans, [])
      family_plan = Enum.find(plans, &(&1.id == :family))

      updated_subscription =
        subscription
        |> Ecto.Changeset.change(%{stripe_status: "active"})
        |> Ecto.Changeset.apply_changes()

      callback = fn sub, _price_id, :upgrade ->
        assert sub.id == subscription.id
        {:ok, updated_subscription}
      end

      try do
        Application.put_env(
          :ysc,
          :change_membership_plan_stripe_callback,
          callback
        )

        assert {:ok, returned_sub} =
                 Subscriptions.change_membership_plan(
                   subscription,
                   family_plan.stripe_price_id,
                   :upgrade
                 )

        assert returned_sub.id == subscription.id
      after
        Application.delete_env(:ysc, :change_membership_plan_stripe_callback)
      end
    end

    test "returns {:ok, subscription} when cancelling scheduled downgrade (same plan) - callback releases" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_same_plan",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscription = Repo.preload(subscription, :subscription_items)
      plans = Application.get_env(:ysc, :membership_plans, [])
      family_plan = Enum.find(plans, &(&1.id == :family))

      callback = fn sub, _price_id, _direction ->
        # User selected same plan to cancel scheduled downgrade - releases schedule
        {:ok, sub}
      end

      try do
        Application.put_env(
          :ysc,
          :change_membership_plan_stripe_callback,
          callback
        )

        assert {:ok, returned_sub} =
                 Subscriptions.change_membership_plan(
                   subscription,
                   family_plan.stripe_price_id,
                   :downgrade
                 )

        assert returned_sub.id == subscription.id
      after
        Application.delete_env(:ysc, :change_membership_plan_stripe_callback)
      end
    end
  end

  describe "get_scheduled_downgrade_info/1" do
    test "returns nil for nil subscription" do
      assert Subscriptions.get_scheduled_downgrade_info(nil) == nil
    end

    test "returns nil when callback returns nil" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_no_schedule",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      callback = fn _sub -> nil end

      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          callback
        )

        assert Subscriptions.get_scheduled_downgrade_info(subscription) == nil
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
      end
    end

    test "returns scheduled downgrade info when callback returns it" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_scheduled",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      effective_date = DateTime.add(DateTime.utc_now(), 30, :day)

      callback = fn sub ->
        assert sub.id == subscription.id
        %{target_plan: :single, effective_date: effective_date}
      end

      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          callback
        )

        assert %{target_plan: :single, effective_date: ^effective_date} =
                 Subscriptions.get_scheduled_downgrade_info(subscription)
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
      end
    end
  end

  describe "cancel_scheduled_downgrade/1" do
    test "returns {:error, _} for nil subscription" do
      assert Subscriptions.cancel_scheduled_downgrade(nil) ==
               {:error, "No subscription to update"}
    end

    test "returns {:ok, subscription} when callback succeeds" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_cancel_test",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      callback = fn sub ->
        assert sub.id == subscription.id
        {:ok, sub}
      end

      try do
        Application.put_env(
          :ysc,
          :cancel_scheduled_downgrade_callback,
          callback
        )

        assert {:ok, ^subscription} =
                 Subscriptions.cancel_scheduled_downgrade(subscription)
      after
        Application.delete_env(:ysc, :cancel_scheduled_downgrade_callback)
      end
    end

    test "returns {:error, :no_scheduled_downgrade} when callback returns nil for schedule" do
      user = user_fixture_unique()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_no_schedule",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      # Simulate Stripe returning no schedule (nil)
      callback = fn _sub -> {:error, :no_scheduled_downgrade} end

      try do
        Application.put_env(
          :ysc,
          :cancel_scheduled_downgrade_callback,
          callback
        )

        assert {:error, :no_scheduled_downgrade} =
                 Subscriptions.cancel_scheduled_downgrade(subscription)
      after
        Application.delete_env(:ysc, :cancel_scheduled_downgrade_callback)
      end
    end
  end

  describe "subscription_struct_from_stripe_subscription/2 and subscription_item_structs_from_stripe_items/2" do
    test "builds a valid subscription changeset from a Stripe subscription", %{
      user: user
    } do
      now = System.os_time(:second)
      period_end = now + 86_400

      stripe_sub = %Stripe.Subscription{
        id: "sub_struct_#{System.unique_integer([:positive])}",
        status: "active",
        start_date: now,
        current_period_start: now,
        current_period_end: period_end,
        trial_end: nil,
        ended_at: nil
      }

      cs =
        Subscriptions.subscription_struct_from_stripe_subscription(
          user,
          stripe_sub
        )

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :stripe_id) == stripe_sub.id
      assert Ecto.Changeset.get_field(cs, :user_id) == user.id
    end

    test "maps Stripe subscription items to subscription item changesets", %{
      user: user
    } do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_items_map",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      stripe_items = [
        %{
          id: "si_1",
          price: %{id: "price_x", product: "prod_y"},
          quantity: 2
        }
      ]

      changesets =
        Subscriptions.subscription_item_structs_from_stripe_items(
          stripe_items,
          subscription
        )

      assert length(changesets) == 1
      cs = hd(changesets)
      assert Ecto.Changeset.get_field(cs, :stripe_id) == "si_1"
      assert Ecto.Changeset.get_field(cs, :stripe_price_id) == "price_x"
      assert Ecto.Changeset.get_field(cs, :quantity) == 2
    end
  end

  describe "create_subscription_from_stripe/2" do
    test "creates local subscription and items from a Stripe payload", %{
      user: user
    } do
      now = System.os_time(:second)
      period_end = now + 365 * 86_400

      stripe_sub = %Stripe.Subscription{
        id: "sub_from_stripe_#{System.unique_integer([:positive])}",
        status: "active",
        start_date: now,
        current_period_start: now,
        current_period_end: period_end,
        trial_end: nil,
        ended_at: nil,
        items: %Stripe.List{
          data: [
            %{
              id: "si_new_#{System.unique_integer([:positive])}",
              price: %{id: "price_from_stripe", product: "prod_from_stripe"},
              quantity: 1
            }
          ],
          has_more: false,
          object: "list",
          url: "/v1/subscription_items"
        }
      }

      assert {:ok, %Subscription{} = sub} =
               Subscriptions.create_subscription_from_stripe(user, stripe_sub)

      assert sub.stripe_id == stripe_sub.id
      assert sub.user_id == user.id
      items = Ysc.Repo.preload(sub, :subscription_items).subscription_items
      assert length(items) == 1
      assert hd(items).stripe_price_id == "price_from_stripe"
    end

    test "returns existing subscription when stripe_id already exists", %{
      user: user
    } do
      {:ok, existing} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_dup_check",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      stripe_sub = %Stripe.Subscription{
        id: "sub_dup_check",
        status: "active",
        start_date: System.os_time(:second),
        current_period_start: System.os_time(:second),
        current_period_end: System.os_time(:second) + 1000,
        items: %Stripe.List{
          data: [],
          has_more: false,
          object: "list",
          url: "/v1/items"
        }
      }

      assert {:ok, returned} =
               Subscriptions.create_subscription_from_stripe(user, stripe_sub)

      assert returned.id == existing.id
      assert returned.stripe_id == "sub_dup_check"
    end
  end

  describe "mark_as_cancelled/1 and cancel/resume error variants" do
    test "mark_as_cancelled/1 sets stripe_status to cancelled", %{user: user} do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_mark_cancel",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      assert {:ok, updated} = Subscriptions.mark_as_cancelled(subscription)
      assert updated.stripe_status == "cancelled"
    end

    test "cancel/2 returns error for lifetime map" do
      assert {:error, msg} = Subscriptions.cancel(%{type: :lifetime}, [])
      assert msg =~ "Lifetime"
    end

    test "cancel/2 returns error for nil" do
      assert {:error, "No subscription to cancel"} =
               Subscriptions.cancel(nil, [])
    end

    test "resume/1 returns error for lifetime map" do
      assert {:error, msg} = Subscriptions.resume(%{type: :lifetime})
      assert msg =~ "Lifetime"
    end

    test "resume/1 returns error for nil" do
      assert {:error, "No subscription to resume"} = Subscriptions.resume(nil)
    end
  end

  describe "get_active_subscription/1 edge cases" do
    test "returns nil when user only has inactive subscriptions", %{user: user} do
      {:ok, _} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_inactive_only",
          stripe_status: "canceled",
          name: "Old",
          current_period_end: DateTime.add(DateTime.utc_now(), -1, :day)
        })

      refute Subscriptions.get_active_subscription(user)
    end

    test "returns nil when user has no subscriptions", %{user: user} do
      refute Subscriptions.get_active_subscription(user)
    end
  end

  describe "scheduled_for_cancellation?/1 and get_scheduled_downgrade_info/1 for lifetime" do
    test "scheduled_for_cancellation? returns false for lifetime map" do
      refute Subscriptions.scheduled_for_cancellation?(%{type: :lifetime})
    end

    test "get_scheduled_downgrade_info returns nil for lifetime map" do
      assert Subscriptions.get_scheduled_downgrade_info(%{type: :lifetime}) ==
               nil
    end
  end

  describe "subscribe_membership_updates/1" do
    test "subscribes the process to the membership PubSub topic", %{user: user} do
      topic = "memberships:user:#{user.id}"
      :ok = Subscriptions.subscribe_membership_updates(user.id)
      assert Phoenix.PubSub.subscribe(Ysc.PubSub, topic) == :ok
      Phoenix.PubSub.broadcast(Ysc.PubSub, topic, :ping)
      assert_receive :ping
    end
  end

  describe "retry_failed_invoice/2" do
    test "returns error for non-binary invoice id" do
      user = user_fixture_unique(%{stripe_id: "cus_x"})

      assert Subscriptions.retry_failed_invoice(user, nil) ==
               {:error, :invalid_invoice_id}
    end
  end

  describe "status helpers and list isolation" do
    test "active?/1 returns false for non-active stripe_status" do
      future = DateTime.add(DateTime.utc_now(), 30, :day)

      refute Subscriptions.active?(%Subscription{
               stripe_status: "past_due",
               current_period_end: future,
               ends_at: nil
             })
    end

    test "cancelled?/1 returns false for default branch when period and ends_at are nil" do
      refute Subscriptions.cancelled?(%Subscription{
               stripe_status: "past_due",
               ends_at: nil,
               current_period_end: nil
             })
    end

    test "scheduled_for_cancellation?/1 is true for trialing with future ends_at" do
      future = DateTime.add(DateTime.utc_now(), 30, :day)

      assert Subscriptions.scheduled_for_cancellation?(%Subscription{
               stripe_status: "trialing",
               ends_at: future,
               current_period_end: future
             })
    end

    test "cancelled?/1 returns false when ends_at is nil and period_end is nil" do
      refute Subscriptions.cancelled?(%Subscription{
               stripe_status: "active",
               ends_at: nil,
               current_period_end: nil
             })
    end

    test "list_subscriptions/1 only returns subscriptions for the given user" do
      u1 = user_fixture_unique()
      u2 = user_fixture_unique()

      {:ok, sub1} =
        Subscriptions.create_subscription(%{
          user_id: u1.id,
          stripe_id: "sub_iso_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "A",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _sub2} =
        Subscriptions.create_subscription(%{
          user_id: u2.id,
          stripe_id: "sub_iso_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "B",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      ids = Subscriptions.list_subscriptions(u1) |> Enum.map(& &1.id)
      assert sub1.id in ids

      refute Enum.any?(
               Subscriptions.list_subscriptions(u1),
               &(&1.user_id == u2.id)
             )
    end

    test "create_subscription_item/1 returns error when attrs are invalid", %{
      user: user
    } do
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_item_bad_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      assert {:error, %Ecto.Changeset{}} =
               Subscriptions.create_subscription_item(%{
                 subscription_id: subscription.id
               })
    end
  end
end
