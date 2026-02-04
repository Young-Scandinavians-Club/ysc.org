defmodule Ysc.Accounts.MembershipCacheTest do
  @moduledoc """
  Tests for Ysc.Accounts.MembershipCache module.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Accounts.MembershipCache
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  import Ysc.AccountsFixtures

  setup do
    # Clear cache before each test
    MembershipCache.invalidate_all()
    :ok
  end

  describe "get_active_membership/1" do
    test "returns nil for nil user" do
      assert MembershipCache.get_active_membership(nil) == nil
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
