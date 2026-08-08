defmodule Ysc.Repo.Migrations.AddCancelAtPeriodEndToSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add :cancel_at_period_end, :boolean, null: false, default: false
    end

    # Existing "auto-renew off" memberships already have ends_at while still active.
    execute(
      """
      UPDATE subscriptions
      SET cancel_at_period_end = true
      WHERE ends_at IS NOT NULL
        AND stripe_status IN ('active', 'trialing')
      """,
      """
      UPDATE subscriptions
      SET cancel_at_period_end = false
      WHERE cancel_at_period_end = true
      """
    )
  end
end
