defmodule Ysc.Repo.Migrations.AddPostMigrationOnboardingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :post_migration_onboarding_completed_at, :utc_datetime, null: true
    end

    # Backfill all existing users so they are not shown the onboarding wizard.
    # Only new WP-migrated users (inserted after this migration with a nil value)
    # will be required to complete onboarding.
    execute(
      "UPDATE users SET post_migration_onboarding_completed_at = inserted_at",
      "UPDATE users SET post_migration_onboarding_completed_at = NULL"
    )
  end
end
