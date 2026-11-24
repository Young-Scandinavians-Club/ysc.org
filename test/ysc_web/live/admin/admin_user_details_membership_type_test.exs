defmodule YscWeb.AdminUserDetailsMembershipTypeLiveTest do
  @moduledoc """
  Admin membership-tab plan change calls `Subscriptions.change_membership_plan/3`
  (default schedule API). Context tests of arity 4 never exercise datetime
  parse, flash, or the LiveView process's Stripe wiring — a regression that
  cancelled schedules (#1878 leftover) would not fail those tests.
  """
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.FakeSubscriptionScheduleApi, as: Api
  alias Ysc.Repo
  alias Ysc.Stripe.SubscriptionFixtures
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription

  setup :register_and_log_in_admin

  setup do
    previous_schedule =
      Application.get_env(:ysc, :stripe_subscription_schedule_module)

    previous_downgrade_cb =
      Application.get_env(:ysc, :get_scheduled_downgrade_info_callback)

    previous_retrieve_cb =
      Application.get_env(
        :ysc,
        :subscription_retrieve_initial_plan_change_callback
      )

    Api.start_agent()

    Application.put_env(:ysc, :stripe_subscription_schedule_module, Api)

    Application.put_env(:ysc, :get_scheduled_downgrade_info_callback, fn _ ->
      nil
    end)

    on_exit(fn ->
      Api.stop_agent()

      restore_env(:stripe_subscription_schedule_module, previous_schedule)
      restore_env(:get_scheduled_downgrade_info_callback, previous_downgrade_cb)

      restore_env(
        :subscription_retrieve_initial_plan_change_callback,
        previous_retrieve_cb
      )
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:ysc, key)

  defp restore_env(key, value), do: Application.put_env(:ysc, key, value)

  defp register_and_log_in_admin(%{conn: conn}) do
    user = user_fixture(%{role: :admin})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp plans do
    plans = Application.get_env(:ysc, :membership_plans, [])
    single = Enum.find(plans, &(&1.id == :single))
    family = Enum.find(plans, &(&1.id == :family))
    assert single && family, "membership_plans must include single and family"
    {single, family}
  end

  defp period_bounds do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    start = DateTime.add(now, -30, :day)
    ends = DateTime.add(now, 365, :day)
    {start, ends}
  end

  defp family_subscription!(user) do
    {_single, family} = plans()
    stripe_id = "sub_#{System.unique_integer([:positive])}"
    {period_start, period_end} = period_bounds()

    {:ok, subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: stripe_id,
        stripe_status: "active",
        name: "Family",
        current_period_start: period_start,
        current_period_end: period_end
      })

    {:ok, _item} =
      Subscriptions.create_subscription_item(%{
        subscription_id: subscription.id,
        stripe_id: "si_#{System.unique_integer([:positive])}",
        stripe_product_id: "prod_family",
        stripe_price_id: family.stripe_price_id,
        quantity: 1
      })

    {Repo.preload(subscription, [:subscription_items, :user]), family}
  end

  defp stripe_sub(stripe_id, price_id, schedule, period_start, period_end) do
    SubscriptionFixtures.subscription(
      id: stripe_id,
      status: "active",
      price_id: price_id,
      current_period_start: DateTime.to_unix(period_start),
      current_period_end: DateTime.to_unix(period_end),
      schedule: schedule
    )
  end

  defp with_initial_retrieve(stripe_sub, fun) do
    previous =
      Application.get_env(
        :ysc,
        :subscription_retrieve_initial_plan_change_callback
      )

    try do
      Application.put_env(
        :ysc,
        :subscription_retrieve_initial_plan_change_callback,
        fn _sid, _opts -> {:ok, stripe_sub} end
      )

      fun.()
    after
      restore_env(
        :subscription_retrieve_initial_plan_change_callback,
        previous
      )
    end
  end

  defp stripe_error(message) do
    {:error,
     %Stripe.Error{
       source: :stripe,
       code: :invalid_request_error,
       message: message
     }}
  end

  defp open_membership_tab(conn, user) do
    {:ok, view, _html} =
      live(conn, ~p"/admin/users/#{user.id}/details/membership")

    render_async(view)
    view
  end

  defp submit_membership_type(view, type) do
    view
    |> form("#admin-membership-type-form", %{
      "membership_type" => %{"membership_type" => type}
    })
    |> render_submit()
  end

  defp cancel_calls?(calls) do
    Enum.any?(calls, fn
      {:cancel, _} -> true
      _ -> false
    end)
  end

  describe "update membership type" do
    test "schedules a family-to-single downgrade and never cancels the Stripe schedule",
         %{conn: conn} do
      user = user_fixture()
      {subscription, family} = family_subscription!(user)
      {single, _} = plans()
      stripe_id = subscription.stripe_id

      with_initial_retrieve(
        stripe_sub(
          stripe_id,
          family.stripe_price_id,
          nil,
          subscription.current_period_start,
          subscription.current_period_end
        ),
        fn ->
          view = open_membership_tab(conn, user)
          assert has_element?(view, "#admin-membership-type-form")

          html = submit_membership_type(view, "single")

          assert html =~ "Downgrade scheduled"
          assert html =~ "Single"

          assert has_element?(
                   view,
                   "#flash-mirror",
                   "Downgrade scheduled"
                 )

          reloaded = Repo.get!(Subscription, subscription.id)
          assert reloaded.stripe_status == "active"

          assert DateTime.to_unix(reloaded.current_period_end) ==
                   DateTime.to_unix(subscription.current_period_end)

          calls = Api.calls()

          assert {:create, [%{from_subscription: ^stripe_id}]} =
                   Enum.find(calls, &match?({:create, _}, &1))

          assert Enum.any?(calls, fn
                   {:update, ["sub_sched_fake", params]} ->
                     params.end_behavior == "release"

                   _ ->
                     false
                 end)

          refute cancel_calls?(calls)

          assert single.amount < family.amount
        end
      )
    end

    test "releases, and never cancels, a new schedule when the phase update fails",
         %{conn: conn} do
      user = user_fixture()
      {subscription, family} = family_subscription!(user)
      stripe_id = subscription.stripe_id
      Api.put_result(:update, stripe_error("invalid phases"))

      with_initial_retrieve(
        stripe_sub(
          stripe_id,
          family.stripe_price_id,
          nil,
          subscription.current_period_start,
          subscription.current_period_end
        ),
        fn ->
          view = open_membership_tab(conn, user)
          html = submit_membership_type(view, "single")

          assert html =~ "Failed to change membership type"

          assert has_element?(
                   view,
                   "#flash-mirror",
                   "Failed to change membership type"
                 )

          reloaded = Repo.get!(Subscription, subscription.id)
          assert reloaded.stripe_status == "active"

          assert DateTime.to_unix(reloaded.current_period_end) ==
                   DateTime.to_unix(subscription.current_period_end)

          calls = Api.calls()

          assert {:create, [%{from_subscription: ^stripe_id}]} =
                   Enum.find(calls, &match?({:create, _}, &1))

          assert {:release, ["sub_sched_fake"]} in calls
          refute cancel_calls?(calls)
        end
      )
    end

    test "releases an existing schedule when the same plan is selected and never cancels it",
         %{conn: conn} do
      user = user_fixture()
      {subscription, family} = family_subscription!(user)
      stripe_id = subscription.stripe_id

      Application.put_env(
        :ysc,
        :get_scheduled_downgrade_info_callback,
        fn _ ->
          %{
            target_plan: :single,
            effective_date: subscription.current_period_end
          }
        end
      )

      with_initial_retrieve(
        stripe_sub(
          stripe_id,
          family.stripe_price_id,
          "sub_sched_old",
          subscription.current_period_start,
          subscription.current_period_end
        ),
        fn ->
          view = open_membership_tab(conn, user)
          html = submit_membership_type(view, "family")

          assert html =~ "Scheduled downgrade cancelled"

          assert has_element?(
                   view,
                   "#flash-mirror",
                   "Scheduled downgrade cancelled"
                 )

          reloaded = Repo.get!(Subscription, subscription.id)
          assert reloaded.stripe_status == "active"

          calls = Api.calls()
          assert {:release, ["sub_sched_old"]} in calls
          refute cancel_calls?(calls)
        end
      )
    end
  end
end
