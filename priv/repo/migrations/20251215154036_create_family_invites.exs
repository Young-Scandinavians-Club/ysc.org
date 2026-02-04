defmodule Ysc.Repo.Migrations.CreateFamilyInvites do
  use Ecto.Migration

  def change do
    create table(:family_invites, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :email, :text, null: false
      add :token, :text, null: false
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime

      add :primary_user_id, references(:users, type: :binary_id), null: false
      add :created_by_user_id, references(:users, type: :binary_id), null: false

      timestamps()
    end

    create unique_index(:family_invites, [:token])
    create index(:family_invites, [:email])
    create index(:family_invites, [:primary_user_id])
    create index(:family_invites, [:created_by_user_id])
  end
end
