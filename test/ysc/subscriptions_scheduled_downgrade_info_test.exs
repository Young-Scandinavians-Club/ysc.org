defmodule Ysc.SubscriptionsScheduledDowngradeInfoTest do
  @moduledoc """
  Public `get_scheduled_downgrade_info/2` must retrieve the Stripe schedule
  and parse its next phase. Callback tests of the same function skip that
  path entirely, so a retrieve/parse regression would not fail them.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.FakeSubscriptionScheduleApi, as: Api
  alias Ysc.Stripe.SubscriptionFixtures
  alias Ysc.Subscriptions

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

  defp local_subscription!(user, stripe_id) do
    {:ok, subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: stripe_id,
        stripe_status: "active",
        name: "Family",
        current_period_start: DateTime.from_unix!(@period_start),
        current_period_end: DateTime.from_unix!(@period_end)
      })

    subscription
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

  defp with_subscription_retrieve(result, fun) do
    original = Application.get_env(:ysc, :stripe_subscription_retriever)
    Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)

    try do
      Application.put_env(
        :ysc,
        :stripe_subscription_retriever,
        Stripe.SubscriptionMock
      )

      expect(Stripe.SubscriptionMock, :retrieve, fn stripe_id ->
        case result do
          {:ok, stripe_sub} ->
            assert stripe_id == stripe_sub.id
            {:ok, stripe_sub}

          {:error, _} = error ->
            error
        end
      end)

      fun.()
    after
      if original do
        Application.put_env(
          :ysc,
          :stripe_subscription_retriever,
          original
        )
      else
        Application.delete_env(:ysc, :stripe_subscription_retriever)
      end
    end
  end

  describe "get_scheduled_downgrade_info/2" do
    test "reads the next-phase plan from atom-keyed phases with a price id" do
      user = user_fixture()
      {single, family} = plans()
      stripe_id = "sub_downgrade_info_#{System.unique_integer([:positive])}"
      schedule_id = "sub_sched_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(user, stripe_id)

      Api.put_result(
        :retrieve,
        {:ok,
         %{
           id: schedule_id,
           phases: [
             %{items: [%{price: family.stripe_price_id}]},
             %{
               items: [%{price: single.stripe_price_id}],
               start_date: @period_end
             }
           ]
         }}
      )

      with_subscription_retrieve(
        {:ok, stripe_sub(stripe_id, family.stripe_price_id, schedule_id)},
        fn ->
          assert %{
                   target_plan: :single,
                   effective_date: effective_date
                 } =
                   Subscriptions.get_scheduled_downgrade_info(
                     subscription,
                     Api
                   )

          assert DateTime.to_unix(effective_date) == @period_end
          assert_received {:retrieve, [^schedule_id]}
        end
      )
    end

    test "reads the next-phase plan from string-keyed phases with a nested price" do
      user = user_fixture()
      {_single, family} = plans()
      stripe_id = "sub_downgrade_info_#{System.unique_integer([:positive])}"
      schedule_id = "sub_sched_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(user, stripe_id)

      Api.put_result(
        :retrieve,
        {:ok,
         %{
           id: schedule_id,
           phases: [
             %{"items" => [%{"price" => "price_current"}]},
             %{
               "items" => [%{"price" => %{"id" => family.stripe_price_id}}],
               "start_date" => @period_end
             }
           ]
         }}
      )

      with_subscription_retrieve(
        {:ok, stripe_sub(stripe_id, "price_current", schedule_id)},
        fn ->
          assert %{
                   target_plan: :family,
                   effective_date: effective_date
                 } =
                   Subscriptions.get_scheduled_downgrade_info(
                     subscription,
                     Api
                   )

          assert DateTime.to_unix(effective_date) == @period_end
          assert_received {:retrieve, [^schedule_id]}
        end
      )
    end

    test "reads a nested atom price object on the next phase" do
      user = user_fixture()
      {single, family} = plans()
      stripe_id = "sub_downgrade_info_#{System.unique_integer([:positive])}"
      schedule_id = "sub_sched_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(user, stripe_id)

      Api.put_result(
        :retrieve,
        {:ok,
         %{
           id: schedule_id,
           phases: [
             %{items: [%{price: %{id: family.stripe_price_id}}]},
             %{
               items: [%{price: %{id: single.stripe_price_id}}],
               start_date: @period_end
             }
           ]
         }}
      )

      with_subscription_retrieve(
        {:ok, stripe_sub(stripe_id, family.stripe_price_id, schedule_id)},
        fn ->
          assert %{target_plan: :single} =
                   Subscriptions.get_scheduled_downgrade_info(
                     subscription,
                     Api
                   )

          assert_received {:retrieve, [^schedule_id]}
        end
      )
    end

    test "returns nil when Stripe has no schedule and does not retrieve one" do
      user = user_fixture()
      {_single, family} = plans()
      stripe_id = "sub_downgrade_info_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(user, stripe_id)

      with_subscription_retrieve(
        {:ok, stripe_sub(stripe_id, family.stripe_price_id, nil)},
        fn ->
          assert Subscriptions.get_scheduled_downgrade_info(
                   subscription,
                   Api
                 ) == nil

          refute_received {:retrieve, _}
        end
      )
    end

    test "returns nil when schedule retrieve fails" do
      user = user_fixture()
      {_single, family} = plans()
      stripe_id = "sub_downgrade_info_#{System.unique_integer([:positive])}"
      schedule_id = "sub_sched_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(user, stripe_id)
      error = stripe_error("no such schedule")
      Api.put_result(:retrieve, error)

      with_subscription_retrieve(
        {:ok, stripe_sub(stripe_id, family.stripe_price_id, schedule_id)},
        fn ->
          assert Subscriptions.get_scheduled_downgrade_info(
                   subscription,
                   Api
                 ) == nil

          assert_received {:retrieve, [^schedule_id]}
        end
      )
    end

    test "returns nil when subscription retrieve fails" do
      user = user_fixture()
      stripe_id = "sub_downgrade_info_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(user, stripe_id)

      with_subscription_retrieve(stripe_error("no such subscription"), fn ->
        assert Subscriptions.get_scheduled_downgrade_info(subscription, Api) ==
                 nil

        refute_received {:retrieve, _}
      end)
    end

    test "returns nil when the schedule has fewer than two phases" do
      user = user_fixture()
      {_single, family} = plans()
      stripe_id = "sub_downgrade_info_#{System.unique_integer([:positive])}"
      schedule_id = "sub_sched_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(user, stripe_id)

      Api.put_result(
        :retrieve,
        {:ok,
         %{
           id: schedule_id,
           phases: [%{items: [%{price: family.stripe_price_id}]}]
         }}
      )

      with_subscription_retrieve(
        {:ok, stripe_sub(stripe_id, family.stripe_price_id, schedule_id)},
        fn ->
          assert Subscriptions.get_scheduled_downgrade_info(
                   subscription,
                   Api
                 ) == nil

          assert_received {:retrieve, [^schedule_id]}
        end
      )
    end

    test "returns nil when the next-phase price is not a membership plan" do
      user = user_fixture()
      {_single, family} = plans()
      stripe_id = "sub_downgrade_info_#{System.unique_integer([:positive])}"
      schedule_id = "sub_sched_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(user, stripe_id)

      Api.put_result(
        :retrieve,
        {:ok,
         %{
           id: schedule_id,
           phases: [
             %{items: [%{price: family.stripe_price_id}]},
             %{
               items: [%{price: "price_not_a_membership"}],
               start_date: @period_end
             }
           ]
         }}
      )

      with_subscription_retrieve(
        {:ok, stripe_sub(stripe_id, family.stripe_price_id, schedule_id)},
        fn ->
          assert Subscriptions.get_scheduled_downgrade_info(
                   subscription,
                   Api
                 ) == nil

          assert_received {:retrieve, [^schedule_id]}
        end
      )
    end
  end
end
