defmodule Ysc.Repo.Migrations.CreateUserNotes do
  use Ecto.Migration

  def change do
    create table(:user_notes, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :note, :text, null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nothing),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_notes, [:user_id])
    create index(:user_notes, [:created_by_user_id])
    create index(:user_notes, [:inserted_at])
  end
end
