defmodule Ysc.Repo.Migrations.CreateGooglePhotosPosterAlbums do
  use Ecto.Migration

  def change do
    # App-created Google Photos albums of upcoming-event posters (one per cabin TV, plus a generic one).
    create table(:google_photos_poster_albums, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :key, :string, null: false
      add :google_album_id, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:google_photos_poster_albums, [:key])

    # The poster media item we added to an album for an event, so it
    # can be replaced when the event changes and removed when the event is over.
    # `poster_hash` fingerprints the rendered poster to skip no-op re-uploads.
    create table(:google_photos_poster_items, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :google_album_id, :string, null: false
      add :media_item_id, :string, null: false
      add :poster_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:google_photos_poster_items, [:event_id, :key])
  end
end
