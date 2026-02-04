defmodule Ysc.Repo.Migrations.AddRefundIdToLedgerEntries do
  use Ecto.Migration

  def change do
    alter table(:ledger_entries) do
      add :refund_id, references(:refunds, on_delete: :restrict, type: :binary_id)
    end

    create index(:ledger_entries, [:refund_id])
  end
end
