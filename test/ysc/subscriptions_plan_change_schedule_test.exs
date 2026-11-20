defmodule Ysc.SubscriptionsPlanChangeScheduleTest do
  @moduledoc """
  Public plan-change and cancel-downgrade callers must `release` Stripe
  schedules, never `cancel` them. Helper tests of `apply_downgrade_schedule/3`
  would still pass if these callers went back to `cancel` (which ends the
  live membership).
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.FakeSubscriptionScheduleApi, as: Api
  alias Ysc.Repo
  alias Ysc.Stripe.SubscriptionFixtures
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription

  @period_start 1_784_999_477
  @period_end 1_794_873_600

  setup :verify_on_exit!

  defp plans do
    plans = Application.get_env(:ysc, :membership_plans, [])
    single = Enum.find(plans, &(&1.id == :single))
    family = Enum.find(plans, &(&1.id == :family))
    assert single && family, "membership_plans must include single and family"
    {single, family}
  end

  defp local_subscription!(user, stripe_id, price_id) do
    {:ok, subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: stripe_id,
        stripe_status: "active",
        name: "Family",
        current_period_start: DateTime.from_unix!(@period_start),
        current_period_end: DateTime.from_unix!(@period_end)
      })

    {:ok, _item} =
      Subscriptions.create_subscription_item(%{
        subscription_id: subscription.id,
        stripe_id: "si_#{System.unique_integer([:positive])}",
        stripe_product_id: "prod_family",
        stripe_price_id: price_id,
        quantity: 1
      })

    Repo.preload(subscription, [:subscription_items, :user])
  end

  defp stripe_sub(stripe_id, price_id, schedule) do
    SubscriptionFixtures.subscription(
      id: stripe_id,
      status: "active",
      price_id: price_id,
      current_period_start: @period_start,
      current_period_end: @period_end,
      schedule: schedule
    )
  end

  defp stripe_error(message) do
    {:error,
     %Stripe.Error{
       source: :stripe,
       code: :invalid_request_error,
       message: message
     }}
  end

  defp with_initial_retrieve(stripe_sub, fun) do
    try do
      Application.put_env(
        :ysc,
        :subscription_retrieve_initial_plan_change_callback,
        fn _sid, _opts -> {:ok, stripe_sub} end
      )

      fun.()
    after
      Application.delete_env(
        :ysc,
        :subscription_retrieve_initial_plan_change_callback
      )
    end
  end

  describe "change_membership_plan/4 downgrade" do
    test "creates a renewal schedule and never cancels it" do
      user = user_fixture()
      {single, family} = plans()
      stripe_id = "sub_downgrade_#{System.unique_integer([:positive])}"

      subscription =
        local_subscription!(user, stripe_id, family.stripe_price_id)

      with_initial_retrieve(
        stripe_sub(stripe_id, family.stripe_price_id, nil),
        fn ->
          assert {:scheduled, returned} =
                   Subscriptions.change_membership_plan(
                     subscription,
                     single.stripe_price_id,
                     :downgrade,
                     Api
                   )

          assert returned.id == subscription.id
          reloaded = Repo.get!(Subscription, subscription.id)
          assert reloaded.stripe_status == "active"
          assert DateTime.to_unix(reloaded.current_period_end) == @period_end

          assert_received {:create, [%{from_subscription: ^stripe_id}]}
          assert_received {:update, ["sub_sched_fake", params]}
          assert params.end_behavior == "release"
          refute_received {:cancel, _}
        end
      )
    end

    test "releases, and never cancels, the new schedule when the phase update fails" do
      user = user_fixture()
      {single, family} = plans()
      stripe_id = "sub_downgrade_fail_#{System.unique_integer([:positive])}"

      subscription =
        local_subscription!(user, stripe_id, family.stripe_price_id)

      error = stripe_error("invalid phases")
      Api.put_result(:update, error)

      with_initial_retrieve(
        stripe_sub(stripe_id, family.stripe_price_id, nil),
        fn ->
          assert ^error =
                   Subscriptions.change_membership_plan(
                     subscription,
                     single.stripe_price_id,
                     :downgrade,
                     Api
                   )

          reloaded = Repo.get!(Subscription, subscription.id)
          assert DateTime.to_unix(reloaded.current_period_end) == @period_end
          assert_received {:create, [%{from_subscription: ^stripe_id}]}
          assert_received {:release, ["sub_sched_fake"]}
          refute_received {:cancel, _}
        end
      )
    end
  end

  describe "change_membership_plan/4 upgrade and same-price" do
    test "releases an existing schedule on upgrade and never cancels it" do
      user = user_fixture()
      {single, family} = plans()
      stripe_id = "sub_upgrade_sched_#{System.unique_integer([:positive])}"

      subscription =
        local_subscription!(user, stripe_id, single.stripe_price_id)

      try do
        Application.put_env(
          :ysc,
          :subscription_retrieve_initial_plan_change_callback,
          fn _sid, _opts ->
            {:ok,
             stripe_sub(stripe_id, single.stripe_price_id, "sub_sched_old")}
          end
        )

        Application.put_env(
          :ysc,
          :subscription_update_plan_change_callback,
          fn _sid, _params -> {:ok, %Stripe.Subscription{}} end
        )

        Application.put_env(
          :ysc,
          :subscription_retrieve_after_plan_change_callback,
          fn _sid ->
            {:ok,
             SubscriptionFixtures.subscription(
               id: stripe_id,
               status: "active",
               price_id: family.stripe_price_id,
               current_period_start: @period_start,
               current_period_end: @period_end
             )}
          end
        )

        assert {:ok, _returned} =
                 Subscriptions.change_membership_plan(
                   subscription,
                   family.stripe_price_id,
                   :upgrade,
                   Api
                 )

        assert_received {:release, ["sub_sched_old"]}
        refute_received {:cancel, _}
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

    test "releases an existing schedule when the same price is selected and never cancels it" do
      user = user_fixture()
      {_single, family} = plans()
      stripe_id = "sub_same_price_#{System.unique_integer([:positive])}"

      subscription =
        local_subscription!(user, stripe_id, family.stripe_price_id)

      with_initial_retrieve(
        stripe_sub(stripe_id, family.stripe_price_id, "sub_sched_old"),
        fn ->
          assert {:ok, returned} =
                   Subscriptions.change_membership_plan(
                     subscription,
                     family.stripe_price_id,
                     :upgrade,
                     Api
                   )

          assert returned.id == subscription.id
          assert_received {:release, ["sub_sched_old"]}
          refute_received {:cancel, _}
        end
      )
    end
  end

  describe "cancel_scheduled_downgrade/2" do
    test "releases the live schedule and never cancels it" do
      user = user_fixture()
      {_single, family} = plans()
      stripe_id = "sub_cancel_sched_#{System.unique_integer([:positive])}"

      subscription =
        local_subscription!(user, stripe_id, family.stripe_price_id)

      original_retriever =
        Application.get_env(:ysc, :stripe_subscription_retriever)

      try do
        Application.put_env(
          :ysc,
          :stripe_subscription_retriever,
          Stripe.SubscriptionMock
        )

        expect(Stripe.SubscriptionMock, :retrieve, fn ^stripe_id ->
          {:ok, stripe_sub(stripe_id, family.stripe_price_id, "sub_sched_old")}
        end)

        assert {:ok, returned} =
                 Subscriptions.cancel_scheduled_downgrade(subscription, Api)

        assert returned.id == subscription.id
        assert_received {:release, ["sub_sched_old"]}
        refute_received {:cancel, _}
      after
        if original_retriever do
          Application.put_env(
            :ysc,
            :stripe_subscription_retriever,
            original_retriever
          )
        else
          Application.delete_env(:ysc, :stripe_subscription_retriever)
        end
      end
    end
  end
end
