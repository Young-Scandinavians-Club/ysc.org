defmodule Ysc.Accounts.MembershipCacheTest do
  @moduledoc """
  Tests for Ysc.Accounts.MembershipCache module.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Accounts.MembershipCache
  alias Ysc.Accounts
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription
  import Ysc.AccountsFixtures

  setup do
    MembershipCache.invalidate_all()
    :ok
  end

  describe "get_active_membership/1" do
    test "returns nil for nil user" do
      assert MembershipCache.get_active_membership(nil) == nil
    end

    test "sub-account inherits primary membership" do
      primary =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      sub =
        user_fixture()
        |> Ecto.Changeset.change(primary_user_id: primary.id)
        |> Ysc.Repo.update!()

      membership = MembershipCache.get_active_membership(sub)
      assert membership.type == :lifetime
      assert membership.user_id == primary.id
    end

    test "returns lifetime membership struct for user with lifetime membership" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      membership = MembershipCache.get_active_membership(user)

      assert membership.type == :lifetime
      assert membership.user_id == user.id
      assert membership.awarded_at != nil
    end

    test "returns subscription for user with active subscription" do
      user = user_fixture()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_test_123",
          stripe_status: "active",
          name: "Test Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      # Reload user to ensure subscriptions association is available
      user = Accounts.get_user!(user.id, [:subscriptions])
      membership = MembershipCache.get_active_membership(user)

      assert membership != nil
      assert membership.id == subscription.id
      assert membership.user_id == user.id
    end

    test "returns nil for user with no membership" do
      user = user_fixture()
      assert MembershipCache.get_active_membership(user) == nil
    end

    test "loads subscriptions from DB when user struct has subscriptions not preloaded" do
      user = user_fixture()

      period_end =
        DateTime.utc_now()
        |> DateTime.add(30, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_noload_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_start:
            DateTime.utc_now() |> DateTime.truncate(:second),
          current_period_end: period_end
        })

      plans = Application.fetch_env!(:ysc, :membership_plans)
      single = Enum.find(plans, &(&1.id == :single))
      assert single

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_noload_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_test",
          stripe_price_id: single.stripe_price_id,
          quantity: 1
        })

      bare_user = Repo.get!(Accounts.User, user.id)
      assert match?(%Ecto.Association.NotLoaded{}, bare_user.subscriptions)

      membership = MembershipCache.get_active_membership(bare_user)
      assert membership.id == subscription.id
    end

    test "uses preloaded subscriptions when association is loaded" do
      user = user_fixture()

      period_end =
        DateTime.utc_now()
        |> DateTime.add(30, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_preloaded_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_start:
            DateTime.utc_now() |> DateTime.truncate(:second),
          current_period_end: period_end
        })

      plans = Application.fetch_env!(:ysc, :membership_plans)
      single = Enum.find(plans, &(&1.id == :single))
      assert single

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_preloaded_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_test",
          stripe_price_id: single.stripe_price_id,
          quantity: 1
        })

      subscription = Repo.preload(subscription, :subscription_items)
      user = Repo.get!(Accounts.User, user.id)
      user = %{user | subscriptions: [subscription]}

      membership = MembershipCache.get_active_membership(user)
      assert membership.id == subscription.id
    end

    test "when multiple active subscriptions exist, picks the higher-priced plan" do
      user = user_fixture()
      plans = Application.fetch_env!(:ysc, :membership_plans)
      single = Enum.find(plans, &(&1.id == :single))
      family = Enum.find(plans, &(&1.id == :family))
      assert single && family

      period_end =
        DateTime.utc_now()
        |> DateTime.add(30, :day)
        |> DateTime.truncate(:second)

      start =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      {:ok, cheap_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_cheap_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_start: start,
          current_period_end: period_end
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          subscription_id: cheap_sub.id,
          stripe_id: "si_cheap_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_a",
          stripe_price_id: single.stripe_price_id,
          quantity: 1
        })

      {:ok, pricey_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_pricey_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_start: start,
          current_period_end: period_end
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          subscription_id: pricey_sub.id,
          stripe_id: "si_pricey_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_b",
          stripe_price_id: family.stripe_price_id,
          quantity: 1
        })

      # User must not have subscriptions preloaded on the struct so that
      # `Customers.subscriptions/1` loads each subscription with `subscription_items`
      # (required for price comparison in `get_most_expensive_subscription/1`).
      user_bare = Repo.get!(Accounts.User, user.id)
      membership = MembershipCache.get_active_membership(user_bare)
      assert membership.id == pricey_sub.id
    end

    test "caches membership after first lookup" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      # First call - should fetch from DB
      membership1 = MembershipCache.get_active_membership(user)

      # Second call - should use cache
      membership2 = MembershipCache.get_active_membership(user)

      assert membership1.type == membership2.type
      assert membership1.user_id == membership2.user_id
    end

    test "invalidates expired cached subscriptions" do
      user = user_fixture()

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_test_expired",
          stripe_status: "active",
          name: "Expired Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      # Reload user with subscriptions
      user = Accounts.get_user!(user.id, [:subscriptions])

      # First call - should fetch from DB
      membership1 = MembershipCache.get_active_membership(user)
      assert membership1 != nil
      assert membership1.id == subscription.id

      # Manually expire the subscription
      Subscriptions.update_subscription(
        subscription,
        %{current_period_end: DateTime.add(DateTime.utc_now(), -2, :day)}
      )

      # Reload user again
      user = Accounts.get_user!(user.id, [:subscriptions])

      # Next call should detect expired membership and fetch fresh
      membership2 = MembershipCache.get_active_membership(user)
      assert membership2 == nil
    end

    test "invalid subscription left in cache is detected and cleared" do
      user = user_fixture()
      plans = Application.fetch_env!(:ysc, :membership_plans)
      single = Enum.find(plans, &(&1.id == :single))
      assert single

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_stale_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_stale_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_x",
          stripe_price_id: single.stripe_price_id,
          quantity: 1
        })

      user = Accounts.get_user!(user.id, [:subscriptions])
      assert MembershipCache.get_active_membership(user).id == subscription.id

      {:ok, _} =
        Subscriptions.update_subscription(subscription, %{
          current_period_end: DateTime.add(DateTime.utc_now(), -2, :day)
        })

      expired =
        Repo.get!(Subscription, subscription.id)
        |> Repo.preload(:subscription_items)

      assert {:ok, true} =
               Cachex.put(
                 :ysc_cache,
                 "membership:#{user.id}:active",
                 expired,
                 expire: :timer.minutes(5)
               )

      user = Accounts.get_user!(user.id, [:subscriptions])
      assert MembershipCache.get_active_membership(user) == nil
    end
  end

  describe "get_membership_plan_type/1" do
    test "returns nil for nil user" do
      assert MembershipCache.get_membership_plan_type(nil) == nil
    end

    test "returns :lifetime for user with lifetime membership" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      plan_type = MembershipCache.get_membership_plan_type(user)
      assert plan_type == :lifetime
    end

    test "returns nil for user with no membership" do
      user = user_fixture()
      assert MembershipCache.get_membership_plan_type(user) == nil
    end

    test "returns plan id from subscription items (e.g. :family)" do
      user = user_fixture()
      plans = Application.fetch_env!(:ysc, :membership_plans)
      family = Enum.find(plans, &(&1.id == :family))
      assert family

      period_end =
        DateTime.utc_now()
        |> DateTime.add(30, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_plan_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_start:
            DateTime.utc_now() |> DateTime.truncate(:second),
          current_period_end: period_end
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_plan_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_family",
          stripe_price_id: family.stripe_price_id,
          quantity: 1
        })

      user = Accounts.get_user!(user.id, [:subscriptions])
      assert MembershipCache.get_membership_plan_type(user) == :family
    end

    test "caches plan type after first lookup" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      plan_type1 = MembershipCache.get_membership_plan_type(user)
      plan_type2 = MembershipCache.get_membership_plan_type(user)

      assert plan_type1 == plan_type2
      assert plan_type1 == :lifetime
    end
  end

  describe "get_membership_data/1" do
    test "returns {nil, nil} for nil user" do
      assert MembershipCache.get_membership_data(nil) == {nil, nil}
    end

    test "returns both membership and plan type" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      {membership, plan_type} = MembershipCache.get_membership_data(user)

      assert membership.type == :lifetime
      assert plan_type == :lifetime
    end
  end

  describe "batch_membership_data_for_users/1" do
    test "returns membership data keyed by user id" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      MembershipCache.invalidate_user(user.id)

      data = MembershipCache.batch_membership_data_for_users([user])

      assert {membership, plan_type} = Map.fetch!(data, user.id)
      assert membership.type == :lifetime
      assert plan_type == :lifetime
    end

    test "validates cached subscriptions in a single query" do
      users = for _ <- 1..3, do: user_fixture()

      Enum.each(users, fn user ->
        {:ok, _subscription} =
          Ysc.Subscriptions.create_subscription(%{
            user_id: user.id,
            stripe_id: "sub_batch_#{System.unique_integer([:positive])}",
            stripe_status: "active",
            name: "Membership",
            current_period_end:
              DateTime.utc_now()
              |> DateTime.add(30, :day)
              |> DateTime.truncate(:second)
          })

        MembershipCache.invalidate_user(user.id)

        assert %Ysc.Subscriptions.Subscription{} =
                 MembershipCache.get_active_membership(user)
      end)

      subscriptions_pattern = ~r/FROM "subscriptions"/i

      {_data, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            MembershipCache.batch_membership_data_for_users(users)
          end,
          pattern: subscriptions_pattern,
          caller_pids: [self()]
        )

      assert query_count <= 1
    end
  end

  describe "invalidate_user/1" do
    test "invalidates cache for user by ID" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      # Populate cache
      _membership = MembershipCache.get_active_membership(user)
      _plan_type = MembershipCache.get_membership_plan_type(user)

      # Invalidate
      assert :ok = MembershipCache.invalidate_user(user.id)

      # Cache should be cleared (will fetch from DB again)
      membership_after = MembershipCache.get_active_membership(user)
      assert membership_after.type == :lifetime
    end

    test "invalidates cache for user by struct" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      # Populate cache
      _membership = MembershipCache.get_active_membership(user)

      # Invalidate using struct
      assert :ok = MembershipCache.invalidate_user(user)

      # Cache should be cleared
      membership_after = MembershipCache.get_active_membership(user)
      assert membership_after.type == :lifetime
    end

    test "handles invalid input gracefully" do
      assert :ok = MembershipCache.invalidate_user(:invalid)
    end
  end

  describe "invalidate_all/0" do
    test "invalidates all membership caches" do
      user1 =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      user2 =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      # Populate caches
      _membership1 = MembershipCache.get_active_membership(user1)
      _membership2 = MembershipCache.get_active_membership(user2)

      # Invalidate all
      assert :ok = MembershipCache.invalidate_all()

      # Caches should be cleared
      membership1_after = MembershipCache.get_active_membership(user1)
      membership2_after = MembershipCache.get_active_membership(user2)

      assert membership1_after.type == :lifetime
      assert membership2_after.type == :lifetime
    end
  end
end
