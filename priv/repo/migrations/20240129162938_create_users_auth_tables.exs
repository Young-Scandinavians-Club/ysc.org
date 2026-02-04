defmodule Ysc.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime

      add :state, :string, null: false, default: "pending_approval"
      add :role, :string, null: false, default: "member"

      add :first_name, :text, null: true
      add :last_name, :text, null: true
      add :phone_number, :string, null: true

      add :most_connected_country, :string
      add :board_position, :string

      timestamps()
    end

    create unique_index(:users, [:email])
    create index(:users, [:role])
    create index(:users, [:state])
    create index(:users, [:board_position])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id, references(:users, on_delete: :delete_all, column: :id, type: :binary_id),
        null: false

      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    create table(:user_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id, references(:users, on_delete: :nothing, column: :id, type: :binary_id),
        null: false

      add :updated_by_user_id,
          references(:users, on_delete: :nothing, column: :id, type: :binary_id),
          null: true

      add :type, :string
      add :from, :string
      add :to, :string

      timestamps()
    end

    create index(:user_events, [:user_id])
  end
end
