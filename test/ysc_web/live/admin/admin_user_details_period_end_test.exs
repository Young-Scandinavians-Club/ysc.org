defmodule YscWeb.AdminUserDetailsPeriodEndLiveTest do
  @moduledoc """
  Admin membership-tab period-end submit calls `Subscriptions.update_period_end/2`
  (default schedule API). Context tests of arity 3 never exercise datetime
  parse, flash, or the LiveView process's Stripe wiring — a regression that
  cancelled schedules (#1878) would not fail those tests.
  """
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.FakeSubscriptionScheduleApi, as: Api
  alias Ysc.Repo
  alias Ysc.Stripe.SubscriptionFixtures
  alias Ysc.Subscriptions
  alias YscWeb.TimeZone

  setup :register_and_log_in_admin

  setup do
    previous = Application.get_env(:ysc, :stripe_subscription_schedule_module)
    Api.start_agent()

    Application.put_env(:ysc, :stripe_subscription_schedule_module, Api)

    on_exit(fn ->
      Api.stop_agent()

      if previous do
        Application.put_env(
          :ysc,
          :stripe_subscription_schedule_module,
          previous
        )
      else
        Application.delete_env(:ysc, :stripe_subscription_schedule_module)
      end
    end)

    :ok
  end

  defp register_and_log_in_admin(%{conn: conn}) do
    user = user_fixture(%{role: :admin})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp active_subscription_for(user) do
    {:ok, subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: "sub_#{System.unique_integer([:positive])}",
        stripe_status: "active",
        name: "Membership",
        current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
      })

    subscription
  end

  defp stub_retrieve(stripe_id) do
    stripe =
      SubscriptionFixtures.subscription(
        id: stripe_id,
        status: "active",
        price_id: "price_family"
      )

    stub(Stripe.SubscriptionMock, :retrieve, fn ^stripe_id ->
      {:ok, stripe}
    end)

    stripe
  end

  defp open_membership_tab(conn, user) do
    {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

    view
    |> element("a[href$='/details/membership']")
    |> render_click()

    view
  end

  defp submit_period_end(view, formatted) do
    view
    |> form("#admin-membership-period-form", %{
      "membership" => %{"period_end_date" => formatted}
    })
    |> render_submit()
  end

  defp stripe_error(message) do
    {:error,
     %Stripe.Error{
       source: :stripe,
       code: :invalid_request_error,
       message: message
     }}
  end

  defp cancel_calls?(calls) do
    Enum.any?(calls, fn
      {:cancel, _} -> true
      _ -> false
    end)
  end

  describe "update membership period" do
    test "releases an existing schedule and never cancels it", %{conn: conn} do
      user = user_fixture()
      subscription = active_subscription_for(user)
      stub_retrieve(subscription.stripe_id)

      Api.put_result(
        :list,
        {:ok, %{data: [%{id: "sub_sched_old", status: "active"}]}}
      )

      new_end =
        DateTime.utc_now()
        |> DateTime.add(30, :day)
        |> DateTime.truncate(:second)

      formatted = TimeZone.format_datetime_local(new_end)
      {:ok, parsed} = TimeZone.parse_datetime_local(formatted)

      view = open_membership_tab(conn, user)
      assert has_element?(view, "#admin-membership-period-form")

      html = submit_period_end(view, formatted)

      assert has_element?(
               view,
               "#flash-mirror",
               "Membership period updated successfully"
             )

      assert html =~ "Membership period updated successfully"

      reloaded = Repo.get!(Subscriptions.Subscription, subscription.id)

      assert DateTime.to_unix(reloaded.current_period_end) ==
               DateTime.to_unix(parsed)

      calls = Api.calls()
      stripe_id = subscription.stripe_id

      assert {:list, [%{subscription: ^stripe_id}]} =
               Enum.find(calls, &match?({:list, _}, &1))

      assert {:release, ["sub_sched_old"]} in calls

      assert {:create, [%{from_subscription: ^stripe_id}]} =
               Enum.find(calls, &match?({:create, _}, &1))

      assert Enum.any?(calls, fn
               {:update, ["sub_sched_fake", params]} ->
                 params.end_behavior == "release"

               _ ->
                 false
             end)

      refute cancel_calls?(calls)
    end

    test "releases, and never cancels, a new schedule when the phase update fails",
         %{conn: conn} do
      user = user_fixture()
      subscription = active_subscription_for(user)
      original_end = subscription.current_period_end
      stub_retrieve(subscription.stripe_id)
      Api.put_result(:update, stripe_error("invalid end date"))

      formatted =
        DateTime.utc_now()
        |> DateTime.add(30, :day)
        |> TimeZone.format_datetime_local()

      view = open_membership_tab(conn, user)
      html = submit_period_end(view, formatted)

      assert html =~ "Failed to update membership period"

      assert has_element?(
               view,
               "#flash-mirror",
               "Failed to update membership period"
             )

      reloaded = Repo.get!(Subscriptions.Subscription, subscription.id)
      assert reloaded.current_period_end == original_end

      calls = Api.calls()
      stripe_id = subscription.stripe_id

      assert {:create, [%{from_subscription: ^stripe_id}]} =
               Enum.find(calls, &match?({:create, _}, &1))

      assert {:release, ["sub_sched_fake"]} in calls
      refute cancel_calls?(calls)
    end

    test "rejects an invalid date without calling Stripe schedules", %{
      conn: conn
    } do
      user = user_fixture()
      subscription = active_subscription_for(user)
      original_end = subscription.current_period_end

      view = open_membership_tab(conn, user)
      html = submit_period_end(view, "not-a-date")

      assert html =~ "Invalid date format."
      assert has_element?(view, "#flash-mirror", "Invalid date format.")

      reloaded = Repo.get!(Subscriptions.Subscription, subscription.id)
      assert reloaded.current_period_end == original_end
      assert Api.calls() == []
    end
  end
end
