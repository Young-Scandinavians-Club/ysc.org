defmodule Ysc.SubscriptionsPeriodEndScheduleTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.FakeSubscriptionScheduleApi, as: Api
  alias Ysc.Stripe.SubscriptionFixtures
  alias Ysc.Subscriptions

  @period_start 1_784_999_477
  @period_end 1_794_873_600
  @new_end @period_end + 86_400

  setup :verify_on_exit!

  defp stripe_sub do
    %{
      id: "sub_1",
      status: "active",
      items: %{
        data: [
          %{
            price: %{id: "price_family"},
            quantity: 1,
            current_period_start: @period_start,
            current_period_end: @period_end
          }
        ]
      },
      current_period_start: @period_start,
      current_period_end: @period_end
    }
  end

  defp stripe_error(message) do
    {:error,
     %Stripe.Error{
       source: :stripe,
       code: :invalid_request_error,
       message: message
     }}
  end

  describe "release_existing_schedules/2" do
    test "releases an active schedule and never cancels it" do
      Api.put_result(
        :list,
        {:ok, %{data: [%{id: "sub_sched_old", status: "active"}]}}
      )

      assert :ok = Subscriptions.release_existing_schedules("sub_1", Api)

      assert_received {:list, [%{subscription: "sub_1"}]}
      assert_received {:release, ["sub_sched_old"]}
      refute_received {:cancel, _}
    end

    test "skips canceled, released, and completed schedules" do
      Api.put_result(
        :list,
        {:ok,
         %{
           data: [
             %{id: "sub_sched_canceled", status: "canceled"},
             %{id: "sub_sched_released", status: "released"},
             %{id: "sub_sched_completed", status: "completed"}
           ]
         }}
      )

      assert :ok = Subscriptions.release_existing_schedules("sub_1", Api)

      refute_received {:release, _}
      refute_received {:cancel, _}
    end

    test "returns :ok when the subscription has no schedules" do
      assert :ok = Subscriptions.release_existing_schedules("sub_1", Api)

      assert_received {:list, [%{subscription: "sub_1"}]}
      refute_received {:release, _}
      refute_received {:cancel, _}
    end

    test "fails closed when release of an active schedule errors" do
      error = stripe_error("cannot release")

      Api.put_result(
        :list,
        {:ok, %{data: [%{id: "sub_sched_old", status: "active"}]}}
      )

      Api.put_result(:release, error)

      assert ^error = Subscriptions.release_existing_schedules("sub_1", Api)
      assert_received {:release, ["sub_sched_old"]}
      refute_received {:cancel, _}
    end
  end

  describe "create_period_end_schedule/3" do
    test "releases, and never cancels, the schedule when the phase update fails" do
      error = stripe_error("invalid end date")
      Api.put_result(:update, error)

      assert ^error =
               Subscriptions.create_period_end_schedule(
                 stripe_sub(),
                 @new_end,
                 Api
               )

      assert_received {:create, [%{from_subscription: "sub_1"}]}
      assert_received {:update, ["sub_sched_fake", params]}
      assert params.end_behavior == "release"
      assert [%{end_date: @new_end}] = params.phases
      assert_received {:release, ["sub_sched_fake"]}
      refute_received {:cancel, _}
    end

    test "returns the schedule and does not release it on success" do
      assert {:ok, %{id: "sub_sched_fake"}} =
               Subscriptions.create_period_end_schedule(
                 stripe_sub(),
                 @new_end,
                 Api
               )

      assert_received {:create, [%{from_subscription: "sub_1"}]}
      refute_received {:release, _}
      refute_received {:cancel, _}
    end

    test "does not cancel or release when schedule create fails" do
      error = stripe_error("already has a schedule")
      Api.put_result(:create, error)

      assert ^error =
               Subscriptions.create_period_end_schedule(
                 stripe_sub(),
                 @new_end,
                 Api
               )

      refute_received {:update, _}
      refute_received {:release, _}
      refute_received {:cancel, _}
    end
  end

  describe "update_period_end/3" do
    defp local_subscription!(stripe_id) do
      user = user_fixture()

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

    defp expect_retrieve(stripe_id, times \\ 2) do
      stripe =
        SubscriptionFixtures.subscription(
          id: stripe_id,
          status: "active",
          price_id: "price_family",
          current_period_start: @period_start,
          current_period_end: @period_end
        )

      expect(Stripe.SubscriptionMock, :retrieve, times, fn ^stripe_id ->
        {:ok, stripe}
      end)

      stripe
    end

    test "releases an existing active schedule and never cancels it" do
      stripe_id = "sub_period_end_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(stripe_id)
      expect_retrieve(stripe_id)

      Api.put_result(
        :list,
        {:ok, %{data: [%{id: "sub_sched_old", status: "active"}]}}
      )

      assert {:ok, updated} =
               Subscriptions.update_period_end(
                 subscription,
                 DateTime.from_unix!(@new_end),
                 Api
               )

      assert DateTime.to_unix(updated.current_period_end) == @new_end
      assert_received {:list, [%{subscription: ^stripe_id}]}
      assert_received {:release, ["sub_sched_old"]}
      assert_received {:create, [%{from_subscription: ^stripe_id}]}
      assert_received {:update, ["sub_sched_fake", params]}
      assert params.end_behavior == "release"
      refute_received {:cancel, _}
    end

    test "releases, and never cancels, the new schedule when the phase update fails" do
      stripe_id = "sub_period_end_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(stripe_id)
      expect_retrieve(stripe_id, 1)
      error = stripe_error("invalid end date")
      Api.put_result(:update, error)

      assert ^error =
               Subscriptions.update_period_end(
                 subscription,
                 DateTime.from_unix!(@new_end),
                 Api
               )

      reloaded = Subscriptions.get_subscription(subscription.id)
      assert DateTime.to_unix(reloaded.current_period_end) == @period_end
      assert_received {:create, [%{from_subscription: ^stripe_id}]}
      assert_received {:release, ["sub_sched_fake"]}
      refute_received {:cancel, _}
    end

    test "does not cancel or attach a schedule when retrieve fails" do
      stripe_id = "sub_period_end_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(stripe_id)
      error = stripe_error("no such subscription")

      expect(Stripe.SubscriptionMock, :retrieve, fn ^stripe_id -> error end)

      assert ^error =
               Subscriptions.update_period_end(
                 subscription,
                 DateTime.from_unix!(@new_end),
                 Api
               )

      refute_received {:list, _}
      refute_received {:create, _}
      refute_received {:cancel, _}
    end

    test "arity 2 uses the env schedule API and never cancels" do
      stripe_id = "sub_period_end_#{System.unique_integer([:positive])}"
      subscription = local_subscription!(stripe_id)
      expect_retrieve(stripe_id)

      previous =
        Application.get_env(:ysc, :stripe_subscription_schedule_module)

      Application.put_env(:ysc, :stripe_subscription_schedule_module, Api)

      try do
        Api.put_result(
          :list,
          {:ok, %{data: [%{id: "sub_sched_old", status: "active"}]}}
        )

        assert {:ok, updated} =
                 Subscriptions.update_period_end(
                   subscription,
                   DateTime.from_unix!(@new_end)
                 )

        assert DateTime.to_unix(updated.current_period_end) == @new_end
        assert_received {:list, [%{subscription: ^stripe_id}]}
        assert_received {:release, ["sub_sched_old"]}
        assert_received {:create, [%{from_subscription: ^stripe_id}]}
        refute_received {:cancel, _}
      after
        if previous do
          Application.put_env(
            :ysc,
            :stripe_subscription_schedule_module,
            previous
          )
        else
          Application.delete_env(:ysc, :stripe_subscription_schedule_module)
        end
      end
    end
  end
end
