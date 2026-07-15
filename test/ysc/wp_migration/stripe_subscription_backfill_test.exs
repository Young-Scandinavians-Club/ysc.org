defmodule Ysc.WpMigration.StripeSubscriptionBackfillTest do
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.User
  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Subscriptions.SubscriptionItem
  alias Ysc.WpMigration.Load

  setup do
    plans = Application.get_env(:ysc, :membership_plans, [])
    single_price = Enum.find(plans, &(&1.id == :single)).stripe_price_id

    {:ok, single_price: single_price}
  end

  describe "create_migration_stripe_subscriptions/1" do
    test "dry run reports migrated subscriptions with a future period end", %{
      single_price: single_price
    } do
      user =
        user_fixture(%{
          email: "backfill@example.com",
          stripe_id: "cus_backfill"
        })

      renewal =
        DateTime.utc_now()
        |> DateTime.add(30, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user.id,
          name: "Membership Subscription",
          stripe_id: "migrated_#{user.id}",
          stripe_status: "active",
          current_period_end: renewal,
          start_date: renewal
        })
        |> Repo.insert()

      %SubscriptionItem{}
      |> SubscriptionItem.changeset(%{
        stripe_id: "migrated_item_#{subscription.id}",
        stripe_product_id: "prod_test",
        stripe_price_id: single_price,
        quantity: 1,
        subscription_id: subscription.id
      })
      |> Repo.insert!()

      assert {:ok, %{stats: %{dry_run: 1, skipped: 0, created: 0}}} =
               Load.create_migration_stripe_subscriptions(
                 dry_run: true,
                 only_emails: [user.email]
               )
    end

    test "skips migrated subscriptions whose period has ended", %{
      single_price: single_price
    } do
      user =
        user_fixture(%{email: "expired@example.com", stripe_id: "cus_expired"})

      renewal =
        DateTime.utc_now()
        |> DateTime.add(-30, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user.id,
          name: "Membership Subscription",
          stripe_id: "migrated_#{user.id}",
          stripe_status: "canceled",
          current_period_end: renewal,
          start_date: renewal,
          ends_at: renewal
        })
        |> Repo.insert()

      %SubscriptionItem{}
      |> SubscriptionItem.changeset(%{
        stripe_id: "migrated_item_#{subscription.id}",
        stripe_product_id: "prod_test",
        stripe_price_id: single_price,
        quantity: 1,
        subscription_id: subscription.id
      })
      |> Repo.insert!()

      assert {:ok, %{stats: %{skipped: 1, created: 0}}} =
               Load.create_migration_stripe_subscriptions(
                 only_emails: [user.email]
               )
    end

    test "awards lifetime membership for far-future migrated subscriptions", %{
      single_price: single_price
    } do
      user =
        user_fixture(%{
          email: "lifetime@example.com",
          stripe_id: "cus_lifetime"
        })

      renewal =
        DateTime.utc_now()
        |> DateTime.add(10 * 365, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user.id,
          name: "Membership Subscription",
          stripe_id: "migrated_#{user.id}",
          stripe_status: "active",
          current_period_end: renewal,
          start_date: renewal
        })
        |> Repo.insert()

      %SubscriptionItem{}
      |> SubscriptionItem.changeset(%{
        stripe_id: "migrated_item_#{subscription.id}",
        stripe_product_id: "prod_test",
        stripe_price_id: single_price,
        quantity: 1,
        subscription_id: subscription.id
      })
      |> Repo.insert!()

      assert {:ok, %{stats: %{lifetime: 1, created: 0}}} =
               Load.create_migration_stripe_subscriptions(
                 only_emails: [user.email]
               )

      updated_user = Repo.get!(User, user.id)
      assert updated_user.lifetime_membership_awarded_at != nil

      refute Repo.exists?(
               from s in Subscription,
                 where:
                   s.user_id == ^user.id and like(s.stripe_id, "migrated_%")
             )
    end
  end
end
