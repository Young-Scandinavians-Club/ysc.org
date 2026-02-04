defmodule Ysc.Repo.Migrations.AddUserPasskeys do
  use Ecto.Migration

  def change do
    create table(:user_passkeys, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id, references(:users, on_delete: :delete_all, column: :id, type: :binary_id),
        null: false

      add :external_id, :binary, null: false
      add :public_key, :binary, null: false
      add :nickname, :text, null: true
      add :sign_count, :integer, default: 0, null: false
      add :last_used_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_passkeys, [:external_id])
    create index(:user_passkeys, [:user_id])
  end
end
