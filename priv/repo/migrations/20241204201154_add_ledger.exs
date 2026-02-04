defmodule Ysc.Repo.Migrations.AddLedger do
  use Ecto.Migration

  def change do
    create table(:ledger_accounts, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :account_type, :text
      add :name, :text
      add :description, :text

      timestamps()
    end

    create unique_index(:ledger_accounts, [:account_type, :name])
    create index(:ledger_accounts, [:name])

    create table(:payments, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :reference_id, :string

      add :external_provider, :string
      add :external_payment_id, :text
      add :amount, :money_with_currency
      add :status, :string
      add :payment_date, :utc_datetime

      add :user_id, references(:users, column: :id, type: :binary_id), null: true

      timestamps()
    end

    create unique_index(:payments, [:external_payment_id])
    create unique_index(:payments, [:reference_id])
    create index(:payments, [:user_id])

    create table(:ledger_transactions, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :type, :string
      add :payment_id, references(:payments, column: :id, type: :binary_id), null: true
      add :total_amount, :money_with_currency
      add :status, :string, default: "pending"

      timestamps()
    end

    create index(:ledger_transactions, [:payment_id])

    create table(:ledger_entries, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :account_id, references(:ledger_accounts, column: :id, type: :binary_id)

      add :related_entity_type, :text
      add :related_entity_id, :binary_id
      add :payment_id, references(:payments, column: :id, type: :binary_id)
      add :description, :text
      add :amount, :money_with_currency

      timestamps()
    end

    create index(:ledger_entries, [:account_id])
    create index(:ledger_entries, [:payment_id])
    create index(:ledger_entries, [:related_entity_id])
  end
end
