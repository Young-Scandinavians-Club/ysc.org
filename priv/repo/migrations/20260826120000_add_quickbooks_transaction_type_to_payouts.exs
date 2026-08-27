defmodule Ysc.Repo.Migrations.AddQuickbooksTransactionTypeToPayouts do
  @moduledoc """
  Negative-amount payouts (Stripe debiting the bank account to cover a
  negative Stripe balance) now sync as a QuickBooks JournalEntry instead of
  being bailed out to manual entry, since a Deposit can't represent a
  withdrawal. `quickbooks_deposit_id` is reused to store either transaction's
  Id; this column records which kind it is so the Deposit-only drift
  reconciliation in `Ysc.Quickbooks.Sync` knows not to run against a
  JournalEntry. NULL/"deposit" means the existing Deposit behavior.
  """
  use Ecto.Migration

  def change do
    alter table(:payouts) do
      add :quickbooks_transaction_type, :string
    end
  end
end
