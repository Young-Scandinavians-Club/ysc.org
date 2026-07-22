defmodule Ysc.Repo.Migrations.CreateVerificationCodes do
  use Ecto.Migration

  def change do
    create table(:verification_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :code_type, :string, null: false
      add :code, :binary, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:verification_codes, [:user_id, :code_type])
    create index(:verification_codes, [:expires_at])
  end
end
