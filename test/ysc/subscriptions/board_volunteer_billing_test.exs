defmodule Ysc.Subscriptions.BoardVolunteerBillingTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Subscriptions.BoardVolunteerBilling
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Subscriptions.SubscriptionItem

  describe "grace_resume_at_unix_from/1" do
    test "shifts six calendar months and returns unix timestamp" do
      from = ~U[2025-01-15 14:30:45Z]

      unix = BoardVolunteerBilling.grace_resume_at_unix_from(from)
      expected_dt = from |> Timex.shift(months: 6) |> DateTime.truncate(:second)
      assert unix == DateTime.to_unix(expected_dt)
    end

    test "January 31 plus six months yields July 31" do
      from = ~U[2025-01-31 08:00:00Z]
      unix = BoardVolunteerBilling.grace_resume_at_unix_from(from)
      back = DateTime.from_unix!(unix, :second)
      assert back.year == 2025
      assert back.month == 7
      assert back.day == 31
    end
  end

  describe "membership_subscription_for_pause?/1" do
    setup do
      single_price =
        :ysc
        |> Application.fetch_env!(:membership_plans)
        |> Enum.find(&(&1.id == :single))
        |> Map.fetch!(:stripe_price_id)

      %{membership_price_id: single_price}
    end

    test "accepts active subscription with configured membership price", %{
      membership_price_id: price_id
    } do
      sub = %Subscription{
        stripe_id: "sub_active_membership",
        stripe_status: "active",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: price_id}
        ]
      }

      assert BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end

    test "accepts trialing subscription", %{membership_price_id: price_id} do
      sub = %Subscription{
        stripe_id: "sub_trial",
        stripe_status: "trialing",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: price_id}
        ]
      }

      assert BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end

    test "rejects migrated placeholder stripe id", %{
      membership_price_id: price_id
    } do
      sub = %Subscription{
        stripe_id: "migrated_sub_123",
        stripe_status: "active",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: price_id}
        ]
      }

      refute BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end

    test "rejects non-membership price", %{membership_price_id: price_id} do
      sub = %Subscription{
        stripe_id: "sub_x",
        stripe_status: "active",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: "#{price_id}_other"}
        ]
      }

      refute BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end

    test "rejects past_due status", %{membership_price_id: price_id} do
      sub = %Subscription{
        stripe_id: "sub_x",
        stripe_status: "past_due",
        subscription_items: [
          %SubscriptionItem{stripe_price_id: price_id}
        ]
      }

      refute BoardVolunteerBilling.membership_subscription_for_pause?(sub)
    end
  end

  describe "sync_for_user/1" do
    test "returns :ok without calling Stripe in test mode" do
      user = user_fixture()
      assert :ok == BoardVolunteerBilling.sync_for_user(user)
    end
  end

  describe "stripe_pause_collection_params/1" do
    test "household on board clears resumes_at so Stripe drops a stale grace date" do
      assert %{pause_collection: %{behavior: "void", resumes_at: ""}} ==
               BoardVolunteerBilling.stripe_pause_collection_params(true)
    end

    test "household off board sets resumes_at six months ahead" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert %{pause_collection: %{behavior: "void", resumes_at: unix}} =
               BoardVolunteerBilling.stripe_pause_collection_params(false)

      expected_now = BoardVolunteerBilling.grace_resume_at_unix_from(now)

      expected_next =
        BoardVolunteerBilling.grace_resume_at_unix_from(
          DateTime.add(now, 1, :second)
        )

      assert unix in [expected_now, expected_next]
    end
  end
end
