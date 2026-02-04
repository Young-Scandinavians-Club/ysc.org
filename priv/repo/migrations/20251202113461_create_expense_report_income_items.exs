defmodule Ysc.Repo.Migrations.CreateExpenseReportIncomeItems do
  use Ecto.Migration

  def change do
    create table(:expense_report_income_items, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :expense_report_id,
          references(:expense_reports, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :date, :date, null: false
      add :description, :text, null: false
      add :amount, :money_with_currency, null: false

      # Proof document stored as S3 path
      add :proof_s3_path, :text, null: true

      timestamps()
    end

    create index(:expense_report_income_items, [:expense_report_id])
    create index(:expense_report_income_items, [:date])
  end
end
