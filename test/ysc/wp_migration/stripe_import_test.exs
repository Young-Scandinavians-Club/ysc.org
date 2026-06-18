defmodule Ysc.WpMigration.StripeImportTest do
  use Ysc.DataCase, async: true

  import Mox

  alias Ysc.WpMigration.StripeImport

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
end
