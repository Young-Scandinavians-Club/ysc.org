defmodule Ysc.Repo.Migrations.AllowNullExpenseItemFieldsForDrafts do
  use Ecto.Migration

  # Draft expense reports keep partially-filled line items, so the item fields a
  # member has not typed yet must be allowed to be NULL. Submission integrity is
  # still enforced in the changesets (`submission_changeset/3` and
  # `create_expense_report/2` validate these as required on real submit).

  def up do
    alter table(:expense_reports) do
      modify :purpose, :text, null: true
      modify :reimbursement_method, :string, null: true
    end

    alter table(:expense_report_items) do
      modify :date, :date, null: true
      modify :vendor, :text, null: true
      modify :description, :text, null: true
      modify :amount, :money_with_currency, null: true
      # Explicit row order for a draft's line items. `save_draft/3` deletes and
      # recreates all child rows on every autosave, and `:utc_datetime` /
      # non-monotonic ULIDs can't preserve insertion order, so persist it.
      add :position, :integer
    end

    alter table(:expense_report_income_items) do
      modify :date, :date, null: true
      modify :description, :text, null: true
      modify :amount, :money_with_currency, null: true
      add :position, :integer
    end

    # Speeds up the "does this user have a draft?" lookup. Not unique:
    # `create_expense_report/2` and other callers may legitimately hold more
    # than one draft row for a user; the single-active-draft guarantee for the
    # expense form lives in `save_draft/3` (per-user advisory lock + reuse).
    create index(:expense_reports, [:user_id],
             name: :expense_reports_user_draft_idx,
             where: "status = 'draft'"
           )
  end

  def down do
    drop index(:expense_reports, [:user_id], name: :expense_reports_user_draft_idx)

    # Any report (draft or otherwise - the admin status modal can flip a
    # NULL-field draft to another status) with a field that's about to become
    # NOT NULL again has to go first. Child rows cascade via their FKs.
    execute("""
    DELETE FROM expense_reports
    WHERE purpose IS NULL OR reimbursement_method IS NULL
    """)

    execute("""
    DELETE FROM expense_reports
    WHERE id IN (
      SELECT expense_report_id FROM expense_report_items
      WHERE date IS NULL OR vendor IS NULL OR description IS NULL OR amount IS NULL
      UNION
      SELECT expense_report_id FROM expense_report_income_items
      WHERE date IS NULL OR description IS NULL OR amount IS NULL
    )
    """)

    alter table(:expense_report_income_items) do
      modify :date, :date, null: false
      modify :description, :text, null: false
      modify :amount, :money_with_currency, null: false
      remove :position
    end

    alter table(:expense_report_items) do
      modify :date, :date, null: false
      modify :vendor, :text, null: false
      modify :description, :text, null: false
      modify :amount, :money_with_currency, null: false
      remove :position
    end

    alter table(:expense_reports) do
      modify :purpose, :text, null: false
      modify :reimbursement_method, :string, null: false
    end
  end
end
