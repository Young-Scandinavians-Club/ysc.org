defmodule Ysc.Repo.Migrations.AddQuickbooksSyncFields do
  use Ecto.Migration

  def up do
    # Add QuickBooks sync fields to payments table
    alter table(:payments) do
      add :quickbooks_sales_receipt_id, :text
      add :quickbooks_sync_status, :text
      add :quickbooks_sync_error, :map
      add :quickbooks_response, :map
      add :quickbooks_synced_at, :utc_datetime
      add :quickbooks_last_sync_attempt_at, :utc_datetime
    end

    # Add indexes for sync status queries
    create index(:payments, [:quickbooks_sync_status])
    create index(:payments, [:quickbooks_sales_receipt_id])

    # Add QuickBooks sync fields to refunds table
    alter table(:refunds) do
      add :quickbooks_sales_receipt_id, :text
      add :quickbooks_sync_status, :text
      add :quickbooks_sync_error, :map
      add :quickbooks_response, :map
      add :quickbooks_synced_at, :utc_datetime
      add :quickbooks_last_sync_attempt_at, :utc_datetime
    end

    # Add indexes for sync status queries
    create index(:refunds, [:quickbooks_sync_status])
    create index(:refunds, [:quickbooks_sales_receipt_id])

    # Add QuickBooks sync fields to payouts table
    alter table(:payouts) do
      add :quickbooks_deposit_id, :text
      add :quickbooks_sync_status, :text
      add :quickbooks_sync_error, :map
      add :quickbooks_response, :map
      add :quickbooks_synced_at, :utc_datetime
      add :quickbooks_last_sync_attempt_at, :utc_datetime
    end

    # Add indexes for sync status queries
    create index(:payouts, [:quickbooks_sync_status])
    create index(:payouts, [:quickbooks_deposit_id])
  end

  def down do
    # Remove indexes
    drop index(:payouts, [:quickbooks_deposit_id])
    drop index(:payouts, [:quickbooks_sync_status])
    drop index(:refunds, [:quickbooks_sales_receipt_id])
    drop index(:refunds, [:quickbooks_sync_status])
    drop index(:payments, [:quickbooks_sales_receipt_id])
    drop index(:payments, [:quickbooks_sync_status])

    # Remove QuickBooks sync fields from payouts table
    alter table(:payouts) do
      remove :quickbooks_deposit_id
      remove :quickbooks_sync_status
      remove :quickbooks_sync_error
      remove :quickbooks_response
      remove :quickbooks_synced_at
      remove :quickbooks_last_sync_attempt_at
    end

    # Remove QuickBooks sync fields from refunds table
    alter table(:refunds) do
      remove :quickbooks_sales_receipt_id
      remove :quickbooks_sync_status
      remove :quickbooks_sync_error
      remove :quickbooks_response
      remove :quickbooks_synced_at
      remove :quickbooks_last_sync_attempt_at
    end

    # Remove QuickBooks sync fields from payments table
    alter table(:payments) do
      remove :quickbooks_sales_receipt_id
      remove :quickbooks_sync_status
      remove :quickbooks_sync_error
      remove :quickbooks_response
      remove :quickbooks_synced_at
      remove :quickbooks_last_sync_attempt_at
    end
  end
end
