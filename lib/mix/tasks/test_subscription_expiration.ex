defmodule Mix.Tasks.TestSubscriptionExpiration do
  @moduledoc """
  Mix task for testing subscription expiration and auto-renewal scenarios.

  This task is useful for:
  - Testing subscription expiration handling
  - Testing auto-renewal failure scenarios
  - Verifying expiration worker behavior
  - Testing cache invalidation on expiration
  - Manual testing of subscription lifecycle

  ## Usage:

      # Show help
      mix test_subscription_expiration --help

      # Show subscription status for a user
      mix test_subscription_expiration status --user USER_EMAIL
      mix test_subscription_expiration status --user-id USER_ID

      # Expire a subscription (sets current_period_end to past)
      mix test_subscription_expiration expire --user USER_EMAIL
      mix test_subscription_expiration expire --user-id USER_ID
      mix test_subscription_expiration expire --user USER_EMAIL --days-ago 1

      # Simulate payment failure (sets subscription to past_due)
      mix test_subscription_expiration simulate-payment-failure --user USER_EMAIL

      # Run expiration worker manually
      mix test_subscription_expiration run-worker

      # Check for expired subscriptions
      mix test_subscription_expiration check-expired

      # List users with subscriptions (filterable by email)
      mix test_subscription_expiration list-users
      mix test_subscription_expiration list-users --email-pattern PATTERN

      # Restore a subscription (sets dates to future)
      mix test_subscription_expiration restore --user USER_EMAIL

      # Trigger auto-renewal in Stripe (forces Stripe to attempt payment)
      mix test_subscription_expiration trigger-renewal --user USER_EMAIL

  ## Options:

      --user EMAIL           User email address
      --user-id ID           User ID (ULID)
      --email-pattern PATTERN Filter users by email pattern (SQL LIKE, e.g., "%@example.com")
      --days-ago N           Number of days ago to set expiration (default: 1)
      --days-future N        Number of days in future for restore (default: 30)
      --dry-run              Show what would happen without making changes
  """

  use Mix.Task
  require Logger

  import Ecto.Query

  @shortdoc "Test subscription expiration and auto-renewal scenarios"

  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.{ExpirationWorker, Subscription}

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    case parse_args(args) do
      {:help} ->
        show_help()

      {:status, opts} ->
        show_status(opts)

      {:expire, opts} ->
        expire_subscription(opts)

      {:simulate_payment_failure, opts} ->
        simulate_payment_failure(opts)

      {:run_worker} ->
        run_expiration_worker()

      {:check_expired} ->
        check_expired_subscriptions()

      {:list_users, opts} ->
        list_users_with_subscriptions(opts)

      {:restore, opts} ->
        restore_subscription(opts)

      {:trigger_renewal, opts} ->
        verify_stripe_config()
        trigger_renewal(opts)

      {:error, message} ->
        IO.puts("❌ Error: #{message}")
        show_help()
        System.halt(1)

      _ ->
        show_help()
    end
  end

  defp parse_args(args) do
    case args do
      ["--help"] ->
        {:help}

      ["status" | rest] ->
        {:status, parse_opts(rest)}

      ["expire" | rest] ->
        {:expire, parse_opts(rest)}

      ["simulate-payment-failure" | rest] ->
        {:simulate_payment_failure, parse_opts(rest)}

      ["run-worker"] ->
        {:run_worker}

      ["check-expired"] ->
        {:check_expired}

      ["list-users" | rest] ->
        {:list_users, parse_opts(rest)}

      ["restore" | rest] ->
        {:restore, parse_opts(rest)}

      ["trigger-renewal" | rest] ->
        {:trigger_renewal, parse_opts(rest)}

      _ ->
        {:error, "Invalid command. Use --help for usage information."}
    end
  end

  defp parse_opts(args) do
    Enum.reduce(args, %{dry_run: false}, fn
      "--user", acc ->
        Map.put(acc, :user_email, :next)

      "--user-id", acc ->
        Map.put(acc, :user_id, :next)

      "--days-ago", acc ->
        Map.put(acc, :days_ago, :next)

      "--days-future", acc ->
        Map.put(acc, :days_future, :next)

      "--email-pattern", acc ->
        Map.put(acc, :email_pattern, :next)

      "--dry-run", acc ->
        Map.put(acc, :dry_run, true)

      value, acc ->
        cond do
          acc[:user_email] == :next ->
            Map.put(acc, :user_email, value)

          acc[:user_id] == :next ->
            Map.put(acc, :user_id, value)

          acc[:days_ago] == :next ->
            days = String.to_integer(value)
            Map.put(acc, :days_ago, days)

          acc[:days_future] == :next ->
            days = String.to_integer(value)
            Map.put(acc, :days_future, days)

          acc[:email_pattern] == :next ->
            Map.put(acc, :email_pattern, value)

          true ->
            acc
        end
    end)
    |> Map.update(:days_ago, 1, & &1)
    |> Map.update(:days_future, 30, & &1)
  end

  defp show_status(opts) do
    case get_user(opts) do
      nil ->
        search_term =
          cond do
            email = Map.get(opts, :user_email) -> "email: #{email}"
            user_id = Map.get(opts, :user_id) -> "ID: #{user_id}"
            true -> "specified criteria"
          end

        IO.puts("❌ User not found with #{search_term}")
        IO.puts("💡 Tip: Use 'list-users' to find users with subscriptions")
        System.halt(1)

      user ->
        user = Repo.preload(user, :subscriptions)
        subscriptions = user.subscriptions

        IO.puts("📊 Subscription Status for #{user.email}")
        IO.puts("=" |> String.duplicate(60))
        IO.puts("User ID: #{user.id}")
        IO.puts("Active Membership: #{Accounts.has_active_membership?(user)}")
        IO.puts("")

        if Enum.empty?(subscriptions) do
          IO.puts("No subscriptions found")
        else
          Enum.each(subscriptions, fn sub ->
            IO.puts("Subscription: #{sub.stripe_id}")
            IO.puts("  Status: #{sub.stripe_status}")

            IO.puts(
              "  Current Period End: #{format_date(sub.current_period_end)}"
            )

            IO.puts("  Ends At: #{format_date(sub.ends_at)}")
            IO.puts("  Active?: #{Subscriptions.active?(sub)}")
            IO.puts("  Valid?: #{Subscriptions.valid?(sub)}")
            IO.puts("  Cancelled?: #{Subscriptions.cancelled?(sub)}")
            IO.puts("")
          end)
        end
    end
  end

  defp expire_subscription(opts) do
    case get_user(opts) do
      nil ->
        search_term =
          cond do
            email = Map.get(opts, :user_email) -> "email: #{email}"
            user_id = Map.get(opts, :user_id) -> "ID: #{user_id}"
            true -> "specified criteria"
          end

        IO.puts("❌ User not found with #{search_term}")
        System.halt(1)

      user ->
        user = Repo.preload(user, :subscriptions)
        subscriptions = user.subscriptions

        if Enum.empty?(subscriptions) do
          IO.puts("❌ No subscriptions found for user")
          System.halt(1)
        end

        days_ago = Map.get(opts, :days_ago, 1)
        dry_run = Map.get(opts, :dry_run, false)
        now = DateTime.utc_now()
        expired_date = DateTime.add(now, -days_ago * 24 * 60 * 60, :second)

        IO.puts("🔄 Expiring subscription(s) for #{user.email}")
        IO.puts("Setting current_period_end to #{format_date(expired_date)}")

        if dry_run do
          IO.puts("🔍 DRY RUN - No changes will be made")
        else
          Enum.each(subscriptions, fn sub ->
            case Subscriptions.update_subscription(sub, %{
                   current_period_end: expired_date
                 }) do
              {:ok, _updated_sub} ->
                IO.puts("✅ Expired subscription #{sub.stripe_id}")
                MembershipCache.invalidate_user(user.id)
                IO.puts("   Cache invalidated for user")

              {:error, changeset} ->
                IO.puts(
                  "❌ Failed to expire subscription #{sub.stripe_id}: #{inspect(changeset.errors)}"
                )
            end
          end)
        end
    end
  end

  defp simulate_payment_failure(opts) do
    case get_user(opts) do
      nil ->
        search_term =
          cond do
            email = Map.get(opts, :user_email) -> "email: #{email}"
            user_id = Map.get(opts, :user_id) -> "ID: #{user_id}"
            true -> "specified criteria"
          end

        IO.puts("❌ User not found with #{search_term}")
        System.halt(1)

      user ->
        user = Repo.preload(user, :subscriptions)
        subscriptions = user.subscriptions

        if Enum.empty?(subscriptions) do
          IO.puts("❌ No subscriptions found for user")
          System.halt(1)
        end

        dry_run = Map.get(opts, :dry_run, false)
        now = DateTime.utc_now()
        expired_date = DateTime.add(now, -1, :day)

        IO.puts("🔄 Simulating payment failure for #{user.email}")
        IO.puts("Setting status to 'past_due' and current_period_end to past")

        if dry_run do
          IO.puts("🔍 DRY RUN - No changes will be made")
        else
          Enum.each(subscriptions, fn sub ->
            case Subscriptions.update_subscription(sub, %{
                   stripe_status: "past_due",
                   current_period_end: expired_date
                 }) do
              {:ok, _updated_sub} ->
                IO.puts(
                  "✅ Simulated payment failure for subscription #{sub.stripe_id}"
                )

                MembershipCache.invalidate_user(user.id)
                IO.puts("   Cache invalidated for user")

              {:error, changeset} ->
                IO.puts(
                  "❌ Failed to update subscription #{sub.stripe_id}: #{inspect(changeset.errors)}"
                )
            end
          end)
        end
    end
  end

  defp run_expiration_worker do
    IO.puts("🔄 Running subscription expiration worker...")

    {expired_count, failed_count} =
      ExpirationWorker.check_and_expire_subscriptions()

    IO.puts(
      "✅ Worker completed: #{expired_count} expired, #{failed_count} failed"
    )
  end

  defp check_expired_subscriptions do
    IO.puts("🔍 Checking for expired subscriptions...")
    IO.puts("=" |> String.duplicate(60))

    now = DateTime.utc_now()

    expired_subscriptions =
      from(s in Subscription,
        where: s.stripe_status in ["active", "trialing"],
        where:
          (not is_nil(s.current_period_end) and s.current_period_end < ^now) or
            (not is_nil(s.ends_at) and s.ends_at < ^now),
        preload: [:user]
      )
      |> Repo.all()

    if Enum.empty?(expired_subscriptions) do
      IO.puts("✅ No expired subscriptions found")
    else
      IO.puts("Found #{length(expired_subscriptions)} expired subscription(s):")
      IO.puts("")

      Enum.each(expired_subscriptions, fn sub ->
        user = sub.user
        IO.puts("Subscription: #{sub.stripe_id}")
        IO.puts("  User: #{user.email} (#{user.id})")
        IO.puts("  Status: #{sub.stripe_status}")
        IO.puts("  Current Period End: #{format_date(sub.current_period_end)}")
        IO.puts("  Ends At: #{format_date(sub.ends_at)}")
        IO.puts("  Active?: #{Subscriptions.active?(sub)}")
        IO.puts("  Valid?: #{Subscriptions.valid?(sub)}")
        IO.puts("")
      end)
    end
  end

  defp list_users_with_subscriptions(opts) do
    IO.puts("🔍 Listing users with subscriptions...")
    IO.puts("=" |> String.duplicate(60))

    alias Ysc.Accounts.User

    base_query = from(u in User, where: u.state != :deleted)

    query =
      case Map.get(opts, :email_pattern) do
        nil ->
          base_query

        pattern ->
          from(u in base_query, where: ilike(u.email, ^pattern))
      end

    # Get users with subscriptions
    users =
      query
      |> preload(:subscriptions)
      |> limit(100)
      |> Repo.all()

    users_with_subs =
      Enum.filter(users, fn user ->
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            # Fetch subscriptions if not loaded
            subscriptions = Subscriptions.list_subscriptions(user)
            subscriptions != []

          subscriptions when is_list(subscriptions) ->
            subscriptions != []

          _ ->
            false
        end
      end)

    if Enum.empty?(users_with_subs) do
      IO.puts("No users with subscriptions found")
    else
      IO.puts("Found #{length(users_with_subs)} user(s) with subscriptions:")
      IO.puts("")

      Enum.each(users_with_subs, fn user ->
        subscriptions =
          case user.subscriptions do
            %Ecto.Association.NotLoaded{} ->
              Subscriptions.list_subscriptions(user)

            subs when is_list(subs) ->
              subs

            _ ->
              []
          end

        active_count =
          Enum.count(subscriptions, fn sub ->
            Subscriptions.active?(sub)
          end)

        IO.puts("User: #{user.email}")
        IO.puts("  ID: #{user.id}")

        IO.puts(
          "  Subscriptions: #{length(subscriptions)} total, #{active_count} active"
        )

        IO.puts(
          "  Has Active Membership: #{Accounts.has_active_membership?(user)}"
        )

        IO.puts("")
      end)
    end
  end

  defp restore_subscription(opts) do
    case get_user(opts) do
      nil ->
        search_term =
          cond do
            email = Map.get(opts, :user_email) -> "email: #{email}"
            user_id = Map.get(opts, :user_id) -> "ID: #{user_id}"
            true -> "specified criteria"
          end

        IO.puts("❌ User not found with #{search_term}")
        System.halt(1)

      user ->
        user = Repo.preload(user, :subscriptions)
        subscriptions = user.subscriptions

        if Enum.empty?(subscriptions) do
          IO.puts("❌ No subscriptions found for user")
          System.halt(1)
        end

        days_future = Map.get(opts, :days_future, 30)
        dry_run = Map.get(opts, :dry_run, false)
        now = DateTime.utc_now()
        future_date = DateTime.add(now, days_future * 24 * 60 * 60, :second)

        IO.puts("🔄 Restoring subscription(s) for #{user.email}")

        IO.puts(
          "Setting current_period_end to #{format_date(future_date)} and status to 'active'"
        )

        if dry_run do
          IO.puts("🔍 DRY RUN - No changes will be made")
        else
          Enum.each(subscriptions, fn sub ->
            case Subscriptions.update_subscription(sub, %{
                   stripe_status: "active",
                   current_period_end: future_date,
                   ends_at: nil
                 }) do
              {:ok, _updated_sub} ->
                IO.puts("✅ Restored subscription #{sub.stripe_id}")
                MembershipCache.invalidate_user(user.id)
                IO.puts("   Cache invalidated for user")

              {:error, changeset} ->
                IO.puts(
                  "❌ Failed to restore subscription #{sub.stripe_id}: #{inspect(changeset.errors)}"
                )
            end
          end)
        end
    end
  end

  defp trigger_renewal(opts) do
    case get_user(opts) do
      nil ->
        search_term =
          cond do
            email = Map.get(opts, :user_email) -> "email: #{email}"
            user_id = Map.get(opts, :user_id) -> "ID: #{user_id}"
            true -> "specified criteria"
          end

        IO.puts("❌ User not found with #{search_term}")
        System.halt(1)

      user ->
        user = Repo.preload(user, :subscriptions)
        subscriptions = user.subscriptions

        if Enum.empty?(subscriptions) do
          IO.puts("❌ No subscriptions found for user")
          System.halt(1)
        end

        dry_run = Map.get(opts, :dry_run, false)

        IO.puts("🔄 Triggering auto-renewal in Stripe for #{user.email}")

        IO.puts(
          "This will force Stripe to immediately attempt to charge the customer"
        )

        IO.puts(
          "Setting billing_cycle_anchor to 'now' to reset the billing cycle"
        )

        IO.puts(
          "Note: This will create prorations for unused time in the current period"
        )

        if dry_run do
          IO.puts("🔍 DRY RUN - No changes will be made")
          IO.puts("")
          IO.puts("Would update subscription(s) in Stripe:")

          Enum.each(subscriptions, fn sub ->
            IO.puts("  - #{sub.stripe_id} (status: #{sub.stripe_status})")
          end)
        else
          Enum.each(subscriptions, fn sub ->
            IO.puts("")
            IO.puts("Processing subscription: #{sub.stripe_id}")

            # Update subscription in Stripe to trigger renewal
            # Setting billing_cycle_anchor to "now" resets the billing cycle
            # and generates an immediate invoice, forcing Stripe to attempt payment
            # proration_behavior: "create_prorations" ensures proper handling of unused time
            # Note: For existing subscriptions, billing_cycle_anchor must be "now", "unchanged", or unset
            case Stripe.Subscription.update(sub.stripe_id, %{
                   billing_cycle_anchor: "now",
                   proration_behavior: "create_prorations"
                 }) do
              {:ok, stripe_subscription} ->
                IO.puts("✅ Updated subscription in Stripe")
                IO.puts("   New status: #{stripe_subscription.status}")

                IO.puts(
                  "   Current period end: #{format_date(DateTime.from_unix!(stripe_subscription.current_period_end))}"
                )

                # Sync local subscription from Stripe
                attrs = %{
                  stripe_status: stripe_subscription.status,
                  current_period_start:
                    stripe_subscription.current_period_start &&
                      DateTime.from_unix!(
                        stripe_subscription.current_period_start
                      ),
                  current_period_end:
                    stripe_subscription.current_period_end &&
                      DateTime.from_unix!(
                        stripe_subscription.current_period_end
                      )
                }

                case Subscriptions.update_subscription(sub, attrs) do
                  {:ok, _updated_sub} ->
                    IO.puts("✅ Synced local subscription")
                    MembershipCache.invalidate_user(user.id)
                    IO.puts("   Cache invalidated for user")

                  {:error, changeset} ->
                    IO.puts(
                      "⚠️  Updated in Stripe but failed to sync locally: #{inspect(changeset.errors)}"
                    )
                end

                # Check if an invoice was created (renewal attempt)
                IO.puts("")
                IO.puts("💡 Stripe will now attempt to charge the customer")

                IO.puts(
                  "   Check Stripe dashboard or webhooks for payment result"
                )

                IO.puts(
                  "   If payment fails, you should receive invoice.payment_failed webhook"
                )

              {:error, %Stripe.Error{} = error} ->
                IO.puts(
                  "❌ Failed to update subscription in Stripe: #{error.message}"
                )

                if error.code do
                  IO.puts("   Error code: #{error.code}")
                end

              {:error, error} ->
                IO.puts(
                  "❌ Failed to update subscription in Stripe: #{inspect(error)}"
                )
            end
          end)
        end
    end
  end

  defp get_user(opts) do
    cond do
      email = Map.get(opts, :user_email) ->
        # Use case-insensitive email lookup
        alias Ysc.Accounts.User

        user =
          Repo.one(from(u in User, where: ilike(u.email, ^email), limit: 1))

        if is_nil(user) do
          # Try exact match as fallback
          Accounts.get_user_by_email(email)
        else
          user
        end

      user_id = Map.get(opts, :user_id) ->
        Accounts.get_user(user_id)

      true ->
        nil
    end
  end

  defp format_date(nil), do: "N/A"

  defp format_date(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp verify_stripe_config do
    api_key = Application.get_env(:stripity_stripe, :api_key)

    if is_nil(api_key) or api_key == "" do
      IO.puts("❌ Stripe API key is not configured")
      IO.puts("")
      IO.puts("Please set the STRIPE_SECRET environment variable:")
      IO.puts("  export STRIPE_SECRET=sk_test_...")
      IO.puts("")
      IO.puts("Or ensure your .env file contains:")
      IO.puts("  STRIPE_SECRET=sk_test_...")
      IO.puts("  STRIPE_PUBLIC_KEY=pk_test_...")
      IO.puts("  STRIPE_WEBHOOK_SECRET=whsec_...")
      IO.puts("")
      System.halt(1)
    end
  end

  defp show_help do
    IO.puts(@moduledoc)
  end
end
