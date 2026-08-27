defmodule Ysc.Repo.Migrations.AddMembershipYtdSubscriptionIndexes do
  @moduledoc """
  Speeds up admin-dashboard membership YTD comparison queries.

  `Accounts.get_membership_joins_ytd_comparison/0` counts:

  - first converted subscription per primary (`MIN(inserted_at)` grouped
    by `user_id`, excluding incomplete checkout rows)
  - lapses by `current_period_end` for canceled/cancelled/unpaid rows
  - renewals by `current_period_start` for active/trialing rows

  Existing indexes cover `(user_id, stripe_status)` and
  `(stripe_status, current_period_end) WHERE ends_at IS NULL` (upcoming
  renewals). They do not serve the YTD lapse window, the YTD renewal
  window (`current_period_start`), or the first-subscription aggregate.
  """
  use Ecto.Migration

  def change do
    # create_if_not_exists so a retry after a dropped Fly Postgres connection
    # does not fail if the previous attempt created an index but did not
    # record the migration version.
    create_if_not_exists index(:subscriptions, [:user_id, :inserted_at],
                           where: "stripe_status NOT IN ('incomplete', 'incomplete_expired')",
                           name: :subscriptions_converted_user_inserted_at_index
                         )

    create_if_not_exists index(:subscriptions, [:stripe_status, :current_period_end],
                           where: "stripe_status IN ('canceled', 'cancelled', 'unpaid')",
                           name: :subscriptions_lapsed_period_end_index
                         )

    create_if_not_exists index(:subscriptions, [:stripe_status, :current_period_start],
                           where:
                             "stripe_status IN ('active', 'trialing') AND current_period_start IS NOT NULL",
                           name: :subscriptions_active_period_start_index
                         )
  end
end
