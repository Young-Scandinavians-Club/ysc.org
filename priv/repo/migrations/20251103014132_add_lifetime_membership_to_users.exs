defmodule Ysc.Repo.Migrations.AddLifetimeMembershipToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :lifetime_membership_awarded_at, :utc_datetime
    end

    create index(:users, [:lifetime_membership_awarded_at])
  end
end
