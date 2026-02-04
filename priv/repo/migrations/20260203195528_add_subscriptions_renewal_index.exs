defmodule Ysc.Repo.Migrations.AddSubscriptionsRenewalIndex do
  use Ecto.Migration

  @moduledoc """
  Adds a composite partial index to optimize the daily membership renewal payment
  method checker query.

  The index covers:
  - stripe_status (to filter for "active" subscriptions)
  - current_period_end (to efficiently find renewals in date range)
  - Partial WHERE clause for ends_at IS NULL (to exclude cancelled subscriptions)

  This makes the daily renewal check query very efficient, typically scanning only
  a few dozen rows instead of the entire subscriptions table.
  """

  def up do
    # Create a partial index for active subscriptions with upcoming renewals
    # This dramatically improves performance of the renewal checker query
    create index(:subscriptions, [:stripe_status, :current_period_end],
             where: "ends_at IS NULL",
             name: :subscriptions_active_renewal_lookup
           )
  end

  def down do
    drop index(:subscriptions, [:stripe_status, :current_period_end],
           name: :subscriptions_active_renewal_lookup
         )
  end
end
