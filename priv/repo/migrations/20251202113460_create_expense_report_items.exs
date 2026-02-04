defmodule Ysc.Repo.Migrations.CreateExpenseReportItems do
  use Ecto.Migration

  def change do
    create table(:expense_report_items, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :expense_report_id,
          references(:expense_reports, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :date, :date, null: false
      add :vendor, :text, null: false
      add :description, :text, null: false
      add :amount, :money_with_currency, null: false

      # Receipt stored as S3 path
      add :receipt_s3_path, :text, null: true

      timestamps()
    end

    create index(:expense_report_items, [:expense_report_id])
    create index(:expense_report_items, [:date])
  end
end
