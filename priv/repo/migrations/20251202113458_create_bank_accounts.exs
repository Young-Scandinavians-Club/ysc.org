defmodule Ysc.Repo.Migrations.CreateBankAccounts do
  use Ecto.Migration

  def change do
    create table(:bank_accounts, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :delete_all),
        null: false

      # Encrypted fields using Cloak.Ecto
      add :routing_number, :binary, null: false
      add :account_number, :binary, null: false

      # Last 4 digits for display (not encrypted)
      add :account_number_last_4, :string, null: false

      timestamps()
    end

    create index(:bank_accounts, [:user_id])
  end
end
