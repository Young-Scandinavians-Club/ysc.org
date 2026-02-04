defmodule Ysc.Repo.Migrations.MakeLedgerEntriesAppendOnly do
  use Ecto.Migration

  def up do
    # Create a function that prevents updates and deletes on ledger_entries
    execute """
    CREATE OR REPLACE FUNCTION prevent_ledger_entry_modification()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Deleting ledger entries is not allowed. Ledger entries must be append-only for audit compliance.'
          USING ERRCODE = 'restrict_violation',
                HINT = 'Create a reversing entry instead of deleting.';
      ELSIF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'Updating ledger entries is not allowed. Ledger entries must be append-only for audit compliance.'
          USING ERRCODE = 'restrict_violation',
                HINT = 'Create a new correcting entry instead of updating.';
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create trigger that fires before any UPDATE or DELETE
    execute """
    CREATE TRIGGER ledger_entries_append_only_trigger
    BEFORE UPDATE OR DELETE ON ledger_entries
    FOR EACH ROW
    EXECUTE FUNCTION prevent_ledger_entry_modification();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS ledger_entries_append_only_trigger ON ledger_entries;"
    execute "DROP FUNCTION IF EXISTS prevent_ledger_entry_modification();"
  end
end
