defmodule Ysc.Repo.Migrations.UpdatePayoutRefundsToUseRefunds do
  use Ecto.Migration

  def up do
    # First, migrate existing data from refund_transaction_id to refund_id
    # by looking up the refund_id from the ledger_transactions table
    execute """
      UPDATE payout_refunds
      SET refund_transaction_id = (
        SELECT refund_id
        FROM ledger_transactions
        WHERE ledger_transactions.id = payout_refunds.refund_transaction_id
          AND ledger_transactions.type = 'refund'
          AND ledger_transactions.refund_id IS NOT NULL
      )
      WHERE EXISTS (
        SELECT 1
        FROM ledger_transactions
        WHERE ledger_transactions.id = payout_refunds.refund_transaction_id
          AND ledger_transactions.type = 'refund'
          AND ledger_transactions.refund_id IS NOT NULL
      );
    """

    # Delete any rows that couldn't be migrated (shouldn't happen in practice)
    execute """
      DELETE FROM payout_refunds
      WHERE refund_transaction_id NOT IN (
        SELECT id
        FROM ledger_transactions
        WHERE type = 'refund' AND refund_id IS NOT NULL
      );
    """

    # Drop the old foreign key constraint
    # Find and drop the constraint dynamically since PostgreSQL auto-generates names
    execute """
      DO $$
      DECLARE
        constraint_name text;
      BEGIN
        SELECT conname INTO constraint_name
        FROM pg_constraint
        WHERE conrelid = 'payout_refunds'::regclass
          AND confrelid = 'ledger_transactions'::regclass
          AND contype = 'f';

        IF constraint_name IS NOT NULL THEN
          EXECUTE 'ALTER TABLE payout_refunds DROP CONSTRAINT ' || quote_ident(constraint_name);
        END IF;
      END $$;
    """

    # Drop the old indexes
    # Drop by column pattern - Ecto will find the correct index names
    execute """
      DO $$
      DECLARE
        idx_record record;
      BEGIN
        FOR idx_record IN
          SELECT indexname
          FROM pg_indexes
          WHERE tablename = 'payout_refunds'
            AND (
              indexname LIKE '%refund_transaction_id%'
              OR (indexdef LIKE '%refund_transaction_id%' AND indexdef LIKE '%payout_id%')
            )
        LOOP
          EXECUTE 'DROP INDEX IF EXISTS ' || quote_ident(idx_record.indexname);
        END LOOP;
      END $$;
    """

    # Rename the column from refund_transaction_id to refund_id
    rename table(:payout_refunds), :refund_transaction_id, to: :refund_id

    # Add the new foreign key constraint referencing refunds table
    alter table(:payout_refunds) do
      modify :refund_id, :binary_id, null: false
    end

    # Add foreign key constraint
    execute """
      ALTER TABLE payout_refunds
      ADD CONSTRAINT payout_refunds_refund_id_fkey
      FOREIGN KEY (refund_id)
      REFERENCES refunds(id)
      ON DELETE CASCADE;
    """

    # Create new indexes
    create index(:payout_refunds, [:refund_id])
    create unique_index(:payout_refunds, [:payout_id, :refund_id])
  end

  def down do
    # First, migrate existing data from refund_id back to refund_transaction_id
    # by finding the ledger_transaction that references the refund
    execute """
      UPDATE payout_refunds
      SET refund_id = (
        SELECT id
        FROM ledger_transactions
        WHERE ledger_transactions.refund_id = payout_refunds.refund_id
          AND ledger_transactions.type = 'refund'
        ORDER BY ledger_transactions.inserted_at DESC
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1
        FROM ledger_transactions
        WHERE ledger_transactions.refund_id = payout_refunds.refund_id
          AND ledger_transactions.type = 'refund'
      );
    """

    # Delete any rows that couldn't be migrated
    execute """
      DELETE FROM payout_refunds
      WHERE refund_id NOT IN (
        SELECT refund_id
        FROM ledger_transactions
        WHERE type = 'refund' AND refund_id IS NOT NULL
      );
    """

    # Drop the new foreign key constraint
    drop constraint(:payout_refunds, "payout_refunds_refund_id_fkey")

    # Drop the new indexes
    execute """
      DO $$
      DECLARE
        idx_record record;
      BEGIN
        FOR idx_record IN
          SELECT indexname
          FROM pg_indexes
          WHERE tablename = 'payout_refunds'
            AND (
              indexname LIKE '%refund_id%'
              OR (indexdef LIKE '%refund_id%' AND indexdef LIKE '%payout_id%')
            )
        LOOP
          EXECUTE 'DROP INDEX IF EXISTS ' || quote_ident(idx_record.indexname);
        END LOOP;
      END $$;
    """

    # Rename the column back from refund_id to refund_transaction_id
    rename table(:payout_refunds), :refund_id, to: :refund_transaction_id

    # Ensure the column type is correct
    alter table(:payout_refunds) do
      modify :refund_transaction_id, :binary_id, null: false
    end

    # Add the old foreign key constraint referencing ledger_transactions table
    execute """
      ALTER TABLE payout_refunds
      ADD CONSTRAINT payout_refunds_refund_transaction_id_fkey
      FOREIGN KEY (refund_transaction_id)
      REFERENCES ledger_transactions(id)
      ON DELETE CASCADE;
    """

    # Recreate old indexes
    create index(:payout_refunds, [:refund_transaction_id])
    create unique_index(:payout_refunds, [:payout_id, :refund_transaction_id])
  end
end
