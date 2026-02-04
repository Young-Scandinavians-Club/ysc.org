defmodule Ysc.Repo.Migrations.AddRefundsTable do
  use Ecto.Migration

  def change do
    # Create refunds table (similar to payments table)
    create table(:refunds, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :reference_id, :string

      add :external_provider, :text
      add :external_refund_id, :text
      add :amount, :money_with_currency
      add :reason, :text
      add :status, :string

      # Reference to the original payment being refunded
      add :payment_id, references(:payments, column: :id, type: :binary_id), null: false

      add :user_id, references(:users, column: :id, type: :binary_id), null: true

      timestamps()
    end

    # Indexes for refunds table
    create unique_index(:refunds, [:external_refund_id])
    create unique_index(:refunds, [:reference_id])
    create index(:refunds, [:payment_id])
    create index(:refunds, [:user_id])

    # Add refund_id to ledger_transactions table
    alter table(:ledger_transactions) do
      add :refund_id, references(:refunds, column: :id, type: :binary_id), null: true
    end

    # Index for refund_id lookups
    create index(:ledger_transactions, [:refund_id])
  end
end
