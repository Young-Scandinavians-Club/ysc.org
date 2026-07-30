defmodule Ysc.Repo.Migrations.CreateOAuthAuthCodes do
  use Ecto.Migration

  def change do
    create table(:oauth_auth_codes, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :hashed_code, :binary, null: false

      add :user_id,
          references(:users, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :client_id, :string, null: false
      add :redirect_uri, :string, null: false
      add :code_challenge, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:oauth_auth_codes, [:hashed_code])
    create index(:oauth_auth_codes, [:user_id])
    create index(:oauth_auth_codes, [:client_id])
    create index(:oauth_auth_codes, [:expires_at])
  end
end
