defmodule Ysc.Repo.Migrations.OptimizeSubscriptionsCancellationLookup do
  @moduledoc """
  Optimizes the Subscriptions.ExpirationWorker query performance by adding a
  second partial index for cancelled subscriptions.

  ## Problem
  The ExpirationWorker runs every 15 minutes (96x per day) with this query:
    WHERE stripe_status IN ('active', 'trialing')
      AND ((current_period_end < now AND ends_at IS NULL)
           OR (ends_at < now AND ends_at IS NOT NULL))

  Current indices:
  - [:stripe_status, :current_period_end] WHERE ends_at IS NULL (for renewals)
  - [:user_id, :stripe_status]

  The query uses an OR condition with two different date fields:
  1. Active renewals check current_period_end (covered by existing partial index)
  2. Cancelled subscriptions check ends_at (NOT covered by any index)

  ## Solution
  Add a complementary partial index for the cancelled subscription path:
  - [:stripe_status, :ends_at] WHERE ends_at IS NOT NULL
  - This complements the existing renewal index
  - PostgreSQL can efficiently query both paths of the OR condition

  ## Performance Impact
  - Faster query planning for the OR condition
  - Smaller index due to partial condition (only rows with ends_at)
  - Better performance as subscriptions table grows
  - Expected 2-4x improvement on the cancellation lookup path

  ## Alternative Approach
  Consider refactoring the worker to use two separate queries instead of OR:
  1. Query renewals: WHERE ends_at IS NULL AND current_period_end < now
  2. Query cancelled: WHERE ends_at IS NOT NULL AND ends_at < now
  This would give PostgreSQL clearer query plans.

  ## Testing
  After migration, verify with:
    mix run priv/repo/scripts/analyze_subscription_expiration_query.exs

  Expected EXPLAIN output should show index usage on both query paths.
  """
  use Ecto.Migration

  def up do
    # Create partial index for cancelled subscriptions checking ends_at
    create index(:subscriptions, [:stripe_status, :ends_at],
             where: "ends_at IS NOT NULL",
             name: :subscriptions_cancelled_expiration_lookup,
             comment:
               "Optimizes Subscriptions.ExpirationWorker for cancelled subscriptions (runs every 15min)"
           )
  end

  def down do
    drop index(:subscriptions, [:stripe_status, :ends_at],
           name: :subscriptions_cancelled_expiration_lookup
         )
  end
end
