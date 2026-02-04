defmodule Ysc.Repo.Migrations.AddQuickbooksFieldsToExpenseReports do
  use Ecto.Migration

  def change do
    alter table(:expense_reports) do
      add :quickbooks_bill_id, :text
      add :quickbooks_vendor_id, :text
      add :quickbooks_sync_status, :string, default: "pending"
      add :quickbooks_sync_error, :text
      add :quickbooks_synced_at, :utc_datetime
      add :quickbooks_last_sync_attempt_at, :utc_datetime
    end

    create index(:expense_reports, [:quickbooks_sync_status])
  end
end
