defmodule Ysc.Repo.Migrations.AddPostMigrationOnboardingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :post_migration_onboarding_completed_at, :utc_datetime, null: true
    end
  end
end
