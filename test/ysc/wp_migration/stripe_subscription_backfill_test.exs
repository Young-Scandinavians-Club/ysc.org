defmodule Ysc.WpMigration.StripeSubscriptionBackfillTest do
  use Ysc.DataCase, async: true

  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.User
  alias Ysc.Payments
  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Subscriptions.SubscriptionItem
  alias Ysc.WpMigration.Load

  setup :verify_on_exit!

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

    test "creates Stripe subscription with default_payment_method when auto-renewing",
         %{
           single_price: single_price
         } do
      user =
        user_fixture(%{email: "create-with-pm@example.com"})
        |> Ecto.Changeset.change(%{stripe_id: "cus_create_pm"})
        |> Repo.update!()

      {:ok, _pm} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_create_sub",
          provider_customer_id: "cus_create_pm",
          type: :card,
          provider_type: "card",
          is_default: true
        })

      renewal =
        DateTime.utc_now()
        |> DateTime.add(45, :day)
        |> DateTime.truncate(:second)

      {:ok, subscription} =
        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user.id,
          name: "Membership Subscription",
          stripe_id: "migrated_#{user.id}",
          stripe_status: "active",
          current_period_end: renewal,
          start_date: renewal,
          ends_at: nil
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

      Stripe.SubscriptionMock
      |> expect(:create, fn params, _opts ->
        assert params.customer == "cus_create_pm"
        assert params.default_payment_method == "pm_create_sub"
        refute Map.get(params, :cancel_at_period_end)

        period_end = DateTime.to_unix(renewal)

        {:ok,
         %Stripe.Subscription{
           id: "sub_created_with_pm",
           status: "trialing",
           customer: "cus_create_pm",
           trial_end: period_end,
           items: %Stripe.List{
             data: [
               %Stripe.SubscriptionItem{
                 id: "si_created_pm",
                 price: %Stripe.Price{id: single_price, product: "prod_test"},
                 current_period_end: period_end
               }
             ],
             has_more: false,
             object: "list",
             url: "/v1/subscription_items"
           }
         }}
      end)

      assert {:ok, %{stats: %{created: 1}}} =
               Load.create_migration_stripe_subscriptions(
                 only_emails: [user.email]
               )

      updated = Repo.get_by!(Subscription, user_id: user.id)
      assert updated.stripe_id == "sub_created_with_pm"
      assert is_nil(updated.ends_at)
    end
  end
end
