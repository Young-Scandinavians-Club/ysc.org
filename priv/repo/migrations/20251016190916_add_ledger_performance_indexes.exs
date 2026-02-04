defmodule Ysc.Repo.Migrations.AddLedgerPerformanceIndexes do
  use Ecto.Migration

  def up do
    # Index for payments table - date range filtering
    # This is critical for get_recent_payments queries
    create index(:payments, [:payment_date])

    # Composite index for payments table - date range + user filtering
    # This optimizes queries that filter by both date and user
    create index(:payments, [:payment_date, :user_id])

    # Composite index for payments table - date range + status filtering
    # This optimizes queries that filter by date and status
    create index(:payments, [:payment_date, :status])

    # Composite index for ledger_entries table - account_id + payment_id
    # This optimizes the join between ledger_entries and payments
    # for get_account_balance queries with date filtering
    create index(:ledger_entries, [:account_id, :payment_id])

    # Index for ledger_entries table - related_entity_type + related_entity_id
    # This optimizes queries that filter by entity type and ID
    create index(:ledger_entries, [:related_entity_type, :related_entity_id])

    # Index for ledger_transactions table - type + status
    # This optimizes queries that filter by transaction type and status
    create index(:ledger_transactions, [:type, :status])
  end

  def down do
    # Drop the indexes in reverse order
    drop index(:ledger_transactions, [:type, :status])
    drop index(:ledger_entries, [:related_entity_type, :related_entity_id])
    drop index(:ledger_entries, [:account_id, :payment_id])
    drop index(:payments, [:payment_date, :status])
    drop index(:payments, [:payment_date, :user_id])
    drop index(:payments, [:payment_date])
  end
end
