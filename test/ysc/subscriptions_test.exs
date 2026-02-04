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

  setup do
    user = user_fixture()
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
      user = user_fixture()

      assert Subscriptions.create_subscription_paid_out_of_band(user, :lifetime) ==
               {:error, :invalid_plan}
    end

    test "returns {:error, :invalid_plan} for unknown plan id" do
      user = user_fixture()

      assert Subscriptions.create_subscription_paid_out_of_band(
               user,
               :unknown_plan
             ) ==
               {:error, :invalid_plan}
    end

    test "returns {:error, :sub_accounts_cannot_create_subscriptions} for sub-account" do
      primary = user_fixture()

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
      user = user_fixture()

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
      user = user_fixture()
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
      user = user_fixture()
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
      user = user_fixture(%{stripe_id: "cus_test"})
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
end
