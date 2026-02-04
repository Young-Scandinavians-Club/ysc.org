defmodule Ysc.Repo.Migrations.CreateExpenseReports do
  use Ecto.Migration

  def change do
    create table(:expense_reports, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :delete_all),
        null: false

      add :purpose, :text, null: false

      # Reimbursement method: "check" or "bank_transfer"
      add :reimbursement_method, :string, null: false

      # If reimbursement_method is "check", reference the address
      add :address_id,
          references(:addresses, column: :id, type: :binary_id, on_delete: :nilify_all),
          null: true

      # If reimbursement_method is "bank_transfer", reference the bank account
      add :bank_account_id,
          references(:bank_accounts, column: :id, type: :binary_id, on_delete: :nilify_all),
          null: true

      # Status: "draft", "submitted", "approved", "rejected", "paid"
      add :status, :string, null: false, default: "draft"

      timestamps()
    end

    create index(:expense_reports, [:user_id])
    create index(:expense_reports, [:status])
  end
end
