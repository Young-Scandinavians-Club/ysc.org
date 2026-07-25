defmodule Ysc.WpMigration.StripeImportTest do
  use Ysc.DataCase, async: true

  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.Payments
  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription
  alias Ysc.WpMigration.StripeImport

  setup :verify_on_exit!

  describe "importable_subscription?/1" do
    test "accepts open subscription statuses" do
      assert StripeImport.importable_subscription?(%{status: "active"})
      assert StripeImport.importable_subscription?(%{status: "trialing"})
      assert StripeImport.importable_subscription?(%{status: "past_due"})
    end

    test "rejects completed subscriptions" do
      refute StripeImport.importable_subscription?(%{status: "canceled"})

      refute StripeImport.importable_subscription?(%{
               status: "incomplete_expired"
             })
    end

    test "accepts canceled subs that still have a future period end" do
      future =
        DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_unix()

      assert StripeImport.importable_subscription?(%{
               status: "canceled",
               cancel_at_period_end: true,
               current_period_end: future
             })
    end
  end

  describe "report" do
    test "records failures and writes json report" do
      report =
        StripeImport.new_report()
        |> StripeImport.record_failure(%{
          category: "stripe_customer_link",
          user_id: "user-1",
          email: "test@example.com",
          reason: "code=api_connection_error"
        })

      assert StripeImport.failure_count(report) == 1

      tmp =
        System.tmp_dir!()
        |> Path.join("stripe-import-#{System.unique_integer()}")
        |> tap(&File.mkdir_p!/1)

      on_exit(fn -> File.rm_rf!(tmp) end)

      path = StripeImport.write_report(report, tmp)
      assert File.exists?(path)

      payload = path |> File.read!() |> Jason.decode!()
      assert payload["failure_count"] == 1
      assert hd(payload["failures"])["category"] == "stripe_customer_link"
    end
  end

  describe "link_wp_stripe_customer/4" do
    test "does not create a fresh customer on transient retrieve failures" do
      user = %Ysc.Accounts.User{
        id: "01TESTUSER00000000000000001",
        email: "member@example.com",
        stripe_id: nil
      }

      Stripe.CustomerMock
      |> expect(:retrieve, fn "cus_wp", _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :api_connection_error,
           message: "connection reset",
           extra: %{}
         }}
      end)

      context = %{
        user_id: user.id,
        email: user.email,
        wp_user_id: "123",
        wp_stripe_customer_id: "cus_wp"
      }

      report = StripeImport.new_report()

      assert {:error, reason, failed_report} =
               StripeImport.link_wp_stripe_customer(
                 user,
                 "cus_wp",
                 context,
                 report
               )

      assert reason =~ "api_connection_error"
      assert StripeImport.failure_count(failed_report) == 1
    end

    test "keeps existing stripe_id when wp customer is missing but existing is valid" do
      user = %Ysc.Accounts.User{
        id: "01TESTUSER00000000000000002",
        email: "member@example.com",
        stripe_id: "cus_existing"
      }

      Stripe.CustomerMock
      |> expect(:retrieve, fn "cus_wp", _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :resource_missing,
           message: "missing",
           extra: %{}
         }}
      end)
      |> expect(:retrieve, fn "cus_existing", _opts ->
        {:ok, %Stripe.Customer{id: "cus_existing"}}
      end)

      context = %{
        user_id: user.id,
        email: user.email,
        wp_user_id: "123",
        wp_stripe_customer_id: "cus_wp"
      }

      report = StripeImport.new_report()

      assert {:ok, ^user, report} =
               StripeImport.link_wp_stripe_customer(
                 user,
                 "cus_wp",
                 context,
                 report
               )

      assert StripeImport.failure_count(report) == 0
    end
  end

  describe "set_customer_default_payment_method/4" do
    test "updates Stripe customer invoice_settings.default_payment_method" do
      user = user_with_stripe_id("pm-sync@example.com", "cus_pm_sync")

      Stripe.CustomerMock
      |> expect(:update, fn "cus_pm_sync", params, _opts ->
        assert get_in(params, [:invoice_settings, :default_payment_method]) ==
                 "pm_default_123"

        {:ok,
         %Stripe.Customer{
           id: "cus_pm_sync",
           invoice_settings: %{default_payment_method: "pm_default_123"}
         }}
      end)

      context = %{
        user_id: user.id,
        email: user.email,
        wp_user_id: "99",
        wp_stripe_customer_id: "cus_pm_sync"
      }

      assert {:ok, report} =
               StripeImport.set_customer_default_payment_method(
                 user,
                 "pm_default_123",
                 context,
                 StripeImport.new_report()
               )

      assert StripeImport.failure_count(report) == 0
    end

    test "records failure when Stripe customer update fails" do
      user = user_with_stripe_id("pm-fail@example.com", "cus_pm_fail")

      Stripe.CustomerMock
      |> expect(:update, fn "cus_pm_fail", _params, _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :api_error,
           message: "boom",
           extra: %{}
         }}
      end)

      context = %{
        user_id: user.id,
        email: user.email,
        wp_user_id: "100",
        wp_stripe_customer_id: "cus_pm_fail"
      }

      assert {:error, _reason, report} =
               StripeImport.set_customer_default_payment_method(
                 user,
                 "pm_bad",
                 context,
                 StripeImport.new_report()
               )

      assert StripeImport.failure_count(report) == 1

      assert hd(report.failures).category ==
               "stripe_customer_default_payment_method"
    end
  end

  describe "enforce_auto_renew_for_user/4" do
    test "clears cancel_at_period_end, attaches PM, and clears local ends_at" do
      user = user_with_stripe_id("auto-renew@example.com", "cus_auto_renew")

      {:ok, _pm} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_auto_renew",
          provider_customer_id: "cus_auto_renew",
          type: :card,
          provider_type: "card",
          is_default: true
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
          stripe_id: "sub_imported_auto",
          stripe_status: "active",
          current_period_end: renewal,
          start_date: renewal,
          ends_at: renewal
        })
        |> Repo.insert()

      Stripe.SubscriptionMock
      |> expect(:update, fn "sub_imported_auto", params, _opts ->
        assert params.cancel_at_period_end == false
        assert params.default_payment_method == "pm_auto_renew"

        period_end = DateTime.to_unix(renewal)

        {:ok,
         %Stripe.Subscription{
           id: "sub_imported_auto",
           status: "active",
           cancel_at_period_end: false,
           items: %Stripe.List{
             data: [
               %Stripe.SubscriptionItem{
                 id: "si_auto",
                 current_period_end: period_end
               }
             ],
             has_more: false,
             object: "list",
             url: "/v1/subscription_items"
           }
         }}
      end)

      context = %{
        user_id: user.id,
        email: user.email,
        wp_user_id: "200",
        wp_stripe_customer_id: user.stripe_id
      }

      report =
        StripeImport.enforce_auto_renew_for_user(
          user,
          context,
          StripeImport.new_report()
        )

      assert StripeImport.failure_count(report) == 0
      updated = Repo.get!(Subscription, subscription.id)
      assert is_nil(updated.ends_at)
    end
  end

  defp user_with_stripe_id(email, stripe_id) do
    user = user_fixture(%{email: email})

    user
    |> Ecto.Changeset.change(%{stripe_id: stripe_id})
    |> Repo.update!()
  end
end
