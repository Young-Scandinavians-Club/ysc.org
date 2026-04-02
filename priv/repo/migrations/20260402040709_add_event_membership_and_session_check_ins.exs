defmodule Ysc.Repo.Migrations.AddEventMembershipAndSessionCheckIns do
  use Ecto.Migration

  def up do
    # The scan_sessions.type column is stored as a plain :string (no Postgres
    # enum type), so no ALTER TYPE is needed — the new value is handled purely
    # at the Ecto / application layer via EctoEnum.

    create table(:session_check_ins, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scan_session_id,
          references(:scan_sessions, type: :binary_id, on_delete: :restrict),
          null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      add :checked_in_by_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      add :membership_status, :string
      add :membership_type, :string

      timestamps(type: :utc_datetime)
    end

    create index(:session_check_ins, [:scan_session_id])
    create index(:session_check_ins, [:user_id])
    create index(:session_check_ins, [:checked_in_by_id])
    create unique_index(:session_check_ins, [:scan_session_id, :user_id])
  end

  def down do
    drop table(:session_check_ins)
  end
end
