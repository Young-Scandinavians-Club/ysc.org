defmodule Ysc.Stripe.SubscriptionHelpersTest do
  use ExUnit.Case, async: true

  alias Ysc.Stripe.SubscriptionHelpers

  describe "current_period_start/1 and current_period_end/1" do
    test "reads legacy top-level fields from maps" do
      subscription = %{
        current_period_start: 1_700_000_000,
        current_period_end: 1_700_086_400
      }

      assert SubscriptionHelpers.current_period_start(subscription) ==
               1_700_000_000

      assert SubscriptionHelpers.current_period_end(subscription) ==
               1_700_086_400
    end

    test "reads period boundaries from the first subscription item" do
      subscription = %Stripe.Subscription{
        id: "sub_test",
        items: %Stripe.List{
          data: [
            %Stripe.SubscriptionItem{
              id: "si_test",
              current_period_start: 1_800_000_000,
              current_period_end: 1_800_086_400
            }
          ]
        }
      }

      assert SubscriptionHelpers.current_period_start(subscription) ==
               1_800_000_000

      assert SubscriptionHelpers.current_period_end(subscription) ==
               1_800_086_400
    end

    test "prefers legacy top-level fields when both are present" do
      subscription = %{
        current_period_start: 1_700_000_000,
        current_period_end: 1_700_086_400,
        items: %{
          data: [
            %{
              current_period_start: 1_800_000_000,
              current_period_end: 1_800_086_400
            }
          ]
        }
      }

      assert SubscriptionHelpers.current_period_start(subscription) ==
               1_700_000_000

      assert SubscriptionHelpers.current_period_end(subscription) ==
               1_700_086_400
    end

    test "reads string-keyed legacy fields and item collections" do
      subscription = %{
        "current_period_start" => 1_700_000_000,
        "current_period_end" => 1_700_086_400,
        "items" => %{
          "data" => [
            %{
              "current_period_start" => 1_900_000_000,
              "current_period_end" => 1_900_086_400
            }
          ]
        }
      }

      assert SubscriptionHelpers.current_period_start(subscription) ==
               1_700_000_000

      assert SubscriptionHelpers.current_period_end(subscription) ==
               1_700_086_400
    end

    test "returns nil when no period data is available" do
      subscription = %{items: %{data: []}}

      assert SubscriptionHelpers.current_period_start(subscription) == nil
      assert SubscriptionHelpers.current_period_end(subscription) == nil
    end
  end
end
