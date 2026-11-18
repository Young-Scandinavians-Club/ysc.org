defmodule Ysc.SubscriptionsPeriodEndScheduleTest do
  use Ysc.DataCase, async: false

  alias Ysc.FakeSubscriptionScheduleApi, as: Api
  alias Ysc.Subscriptions

  @period_start 1_784_999_477
  @period_end 1_794_873_600
  @new_end @period_end + 86_400

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
end
