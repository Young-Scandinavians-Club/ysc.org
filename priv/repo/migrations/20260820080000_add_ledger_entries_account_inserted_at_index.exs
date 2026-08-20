defmodule Ysc.Repo.Migrations.AddLedgerEntriesAccountInsertedAtIndex do
  use Ecto.Migration

  def change do
    create index(:ledger_entries, [:account_id, :inserted_at])
  end
end
