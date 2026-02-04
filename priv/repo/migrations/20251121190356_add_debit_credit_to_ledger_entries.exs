defmodule Ysc.Repo.Migrations.AddDebitCreditToLedgerEntries do
  use Ecto.Migration

  def up do
    # Add debit_credit column (nullable initially for migration)
    alter table(:ledger_entries) do
      add :debit_credit, :string
    end

    # Migrate existing data:
    # - If amount is negative, set debit_credit to "credit" and make amount positive
    # - If amount is positive, set debit_credit to "debit" and keep amount positive
    execute """
      UPDATE ledger_entries
      SET debit_credit = CASE
        WHEN (amount).amount < 0 THEN 'credit'
        ELSE 'debit'
      END,
      amount = CASE
        WHEN (amount).amount < 0 THEN ROW((amount).currency_code, -(amount).amount)::money_with_currency
        ELSE amount
      END;
    """

    # Make the column required
    alter table(:ledger_entries) do
      modify :debit_credit, :string, null: false
    end

    # Create index for better query performance
    create index(:ledger_entries, [:debit_credit])
  end

  def down do
    # Convert back to signed amounts
    execute """
      UPDATE ledger_entries
      SET amount = CASE
        WHEN debit_credit = 'credit' THEN ROW((amount).currency_code, -(amount).amount)::money_with_currency
        ELSE amount
      END;
    """

    # Remove the column
    drop index(:ledger_entries, [:debit_credit])

    alter table(:ledger_entries) do
      remove :debit_credit
    end
  end
end
