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
    end

    alter table(:expense_report_income_items) do
      modify :date, :date, null: true
      modify :description, :text, null: true
      modify :amount, :money_with_currency, null: true
    end

    create index(:expense_reports, [:user_id, :updated_at],
             name: :expense_reports_user_draft_idx,
             where: "status = 'draft'"
           )
  end

  def down do
    drop index(:expense_reports, [:user_id, :updated_at], name: :expense_reports_user_draft_idx)

    alter table(:expense_report_income_items) do
      modify :date, :date, null: false
      modify :description, :text, null: false
      modify :amount, :money_with_currency, null: false
    end

    alter table(:expense_report_items) do
      modify :date, :date, null: false
      modify :vendor, :text, null: false
      modify :description, :text, null: false
      modify :amount, :money_with_currency, null: false
    end

    alter table(:expense_reports) do
      modify :purpose, :text, null: false
      modify :reimbursement_method, :string, null: false
    end
  end
end
