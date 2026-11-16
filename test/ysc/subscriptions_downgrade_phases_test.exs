defmodule Ysc.SubscriptionsDowngradePhasesTest do
  use ExUnit.Case, async: true

  alias Ysc.Subscriptions

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
end
