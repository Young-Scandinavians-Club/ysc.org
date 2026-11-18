defmodule Ysc.SubscriptionsDowngradePhasesTest do
  use Ysc.DataCase, async: false

  import Mox

  alias Ysc.FakeSubscriptionScheduleApi, as: Api
  alias Ysc.Subscriptions

  setup :verify_on_exit!

  @period_start 1_784_999_477
  @period_end 1_794_873_600

  defp stripe_sub(status) do
    %{
      status: status,
      items: %{
        data: [
          %{
            current_period_start: @period_start,
            current_period_end: @period_end
          }
        ]
      },
      current_period_start: @period_start,
      current_period_end: @period_end
    }
  end

  defp item, do: %{price: %{id: "price_family"}, quantity: 1}

  describe "downgrade_phases/3" do
    test "keeps trial_end on phase 1 for a trialing subscription" do
      [phase1, phase2] =
        Subscriptions.downgrade_phases(
          stripe_sub("trialing"),
          item(),
          "price_single"
        )

      assert phase1.trial_end == @period_end
      assert phase1.end_date == @period_end
      assert [%{price: "price_family"}] = phase1.items
      assert phase2.start_date == @period_end
      assert [%{price: "price_single"}] = phase2.items
    end

    test "does not set trial_end for an active subscription" do
      [phase1, _phase2] =
        Subscriptions.downgrade_phases(
          stripe_sub("active"),
          item(),
          "price_single"
        )

      refute Map.has_key?(phase1, :trial_end)
    end
  end

  describe "apply_downgrade_schedule/3" do
    defp sub_without_schedule do
      %{
        id: "sub_1",
        status: "active",
        schedule: nil,
        trial_settings: nil
      }
    end

    defp trialing_pause_sub do
      %{
        id: "sub_trial_pause",
        status: "trialing",
        schedule: nil,
        trial_settings: %{end_behavior: %{missing_payment_method: "pause"}}
      }
    end

    test "releases, and never cancels, the schedule when the phase update fails" do
      error =
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message: "boom"
         }}

      Api.put_result(:update, error)

      assert ^error =
               Subscriptions.apply_downgrade_schedule(
                 sub_without_schedule(),
                 [%{}, %{}],
                 Api
               )

      assert_received {:create, [%{from_subscription: "sub_1"}]}
      assert_received {:update, ["sub_sched_fake", _]}
      assert_received {:release, ["sub_sched_fake"]}
      refute_received {:cancel, _}
    end

    test "returns the schedule and does not release it on success" do
      assert {:ok, %{id: "sub_sched_fake"}} =
               Subscriptions.apply_downgrade_schedule(
                 sub_without_schedule(),
                 [%{}, %{}],
                 Api
               )

      refute_received {:release, _}
      refute_received {:cancel, _}
    end

    test "switches trialing+pause to create_invoice before creating the schedule" do
      expect(Stripe.SubscriptionMock, :update, fn "sub_trial_pause", params ->
        assert get_in(params, [
                 :trial_settings,
                 :end_behavior,
                 :missing_payment_method
               ]) ==
                 "create_invoice"

        {:ok, %{id: "sub_trial_pause", status: "trialing"}}
      end)

      assert {:ok, %{id: "sub_sched_fake"}} =
               Subscriptions.apply_downgrade_schedule(
                 trialing_pause_sub(),
                 [%{}, %{}],
                 Api
               )

      assert_received {:create, [%{from_subscription: "sub_trial_pause"}]}
    end

    test "does not create a schedule when the pause→create_invoice update fails" do
      error =
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :invalid_request_error,
           message: "cannot update trial settings"
         }}

      expect(Stripe.SubscriptionMock, :update, fn "sub_trial_pause", _params ->
        error
      end)

      assert ^error =
               Subscriptions.apply_downgrade_schedule(
                 trialing_pause_sub(),
                 [%{}, %{}],
                 Api
               )

      refute_received {:create, _}
    end

    test "does not touch trial_settings for an active subscription" do
      expect(Stripe.SubscriptionMock, :update, 0, fn _id, _params ->
        flunk("active subscriptions must not update trial_settings")
      end)

      assert {:ok, _} =
               Subscriptions.apply_downgrade_schedule(
                 sub_without_schedule(),
                 [%{}, %{}],
                 Api
               )
    end
  end
end
