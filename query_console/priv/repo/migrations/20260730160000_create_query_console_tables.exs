defmodule QueryConsole.Repo.Migrations.CreateQueryConsoleTables do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ysc_user_id, :string, null: false
      add :email, :string, null: false
      add :display_name, :string
      add :role, :string, null: false, default: "admin"
      add :last_login_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:ysc_user_id])
    create index(:users, [:email])

    create table(:workbooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false, default: "Untitled"
      add :sql, :text, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create index(:workbooks, [:user_id])

    create table(:workbook_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workbook_id, references(:workbooks, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sql, :text, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:workbook_revisions, [:workbook_id, :inserted_at])

    create table(:query_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :workbook_id, references(:workbooks, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "queued"
      add :mode, :string, null: false, default: "all"
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :error_summary, :string
      add :statement_count, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:query_runs, [:user_id])
    create index(:query_runs, [:workbook_id])
    create index(:query_runs, [:status])

    create table(:statement_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :query_run_id, references(:query_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :index, :integer, null: false
      add :status, :string, null: false, default: "pending"
      add :elapsed_ms, :integer
      add :row_count, :integer
      add :error_summary, :string

      timestamps(type: :utc_datetime)
    end

    create index(:statement_runs, [:query_run_id])
    create unique_index(:statement_runs, [:query_run_id, :index])

    create table(:schema_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :version, :integer, null: false
      add :payload, :map, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:schema_snapshots, [:version])

    create table(:query_leases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :holder, :string, null: false
      add :query_run_id, references(:query_runs, type: :binary_id, on_delete: :nilify_all)
      add :acquired_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: false
    end

    create unique_index(:query_leases, [:holder])
    create index(:query_leases, [:expires_at])
  end
end
