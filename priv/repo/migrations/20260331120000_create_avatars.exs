defmodule Ysc.Repo.Migrations.CreateAvatars do
  use Ecto.Migration

  def change do
    create table(:avatars, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :original_path, :string, null: false, size: 2048
      add :thumb_path, :string, size: 2048
      add :profile_path, :string, size: 2048
      add :large_path, :string, size: 2048
      add :processing_state, :string, null: false, default: "pending"
      add :source_url, :string, size: 2048

      timestamps(type: :utc_datetime)
    end

    create index(:avatars, [:user_id])
    create index(:avatars, [:user_id, :inserted_at])

    alter table(:users) do
      add :current_avatar_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
