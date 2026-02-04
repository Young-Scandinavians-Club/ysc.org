defmodule Ysc.Repo.Migrations.AddNormalBalanceToLedgerAccounts do
  use Ecto.Migration

  def change do
    alter table(:ledger_accounts) do
      add :normal_balance, :string
    end

    # Backfill normal_balance based on account_type
    # Assets and Expenses are debit-normal
    # Liabilities, Revenue, and Equity are credit-normal
    execute """
      UPDATE ledger_accounts
      SET normal_balance = CASE
        WHEN account_type IN ('asset', 'expense') THEN 'debit'
        WHEN account_type IN ('liability', 'revenue', 'equity') THEN 'credit'
        ELSE 'debit'
      END
      WHERE normal_balance IS NULL;
    """
  end
end
