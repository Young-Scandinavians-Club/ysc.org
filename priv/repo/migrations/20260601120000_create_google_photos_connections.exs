defmodule Ysc.Repo.Migrations.CreateGooglePhotosConnections do
  use Ecto.Migration

  def change do
    create table(:google_photos_connections, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :key, :string, null: false, default: "default"
      add :refresh_token, :binary, null: false
      add :account_email, :string
      add :scopes, :text
      add :connected_at, :utc_datetime, null: false

      add :connected_by_id,
          references(:users, column: :id, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:google_photos_connections, [:key])

    create constraint(:google_photos_connections, :only_default_key, check: "key = 'default'")
  end
end
