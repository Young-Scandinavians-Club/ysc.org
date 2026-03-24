defmodule Ysc.Repo.Migrations.CreateScanTables do
  use Ecto.Migration

  def change do
    create table(:scan_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :event_id, references(:events, type: :binary_id, on_delete: :nilify_all)

      add :created_by_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      add :closed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:scan_sessions, [:created_by_id])
    create index(:scan_sessions, [:event_id])
    create index(:scan_sessions, [:type])

    create table(:scan_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scan_session_id,
          references(:scan_sessions, type: :binary_id, on_delete: :restrict),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :restrict)

      add :ticket_order_id,
          references(:ticket_orders, type: :binary_id, on_delete: :restrict)

      add :checkin_type, :string
      add :result, :string, null: false
      add :membership_status, :string
      add :membership_type, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:scan_records, [:scan_session_id])
    create index(:scan_records, [:user_id])
    create index(:scan_records, [:ticket_id])
  end
end
