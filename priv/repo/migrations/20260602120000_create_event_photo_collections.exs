defmodule Ysc.Repo.Migrations.CreateEventPhotoCollections do
  use Ecto.Migration

  def change do
    create table(:event_photo_collections, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :upload_token, :binary_id, null: false
      add :google_album_id, :string
      add :reminder_sent_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:event_photo_collections, [:event_id])
    create unique_index(:event_photo_collections, [:upload_token])
  end
end
