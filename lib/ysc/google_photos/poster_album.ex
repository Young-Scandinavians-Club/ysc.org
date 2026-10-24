defmodule Ysc.GooglePhotos.PosterAlbum do
  @moduledoc """
  An app-created Google Photos album that shows upcoming-event posters: one per
  cabin TV (`:tahoe`, `:clear_lake`) plus a generic `:upcoming` album for markets,
  conferences and other displays. The album id is persisted so each album is
  created only once.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @keys [:tahoe, :clear_lake, :upcoming]

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "google_photos_poster_albums" do
    field :key, Ecto.Enum, values: @keys
    field :google_album_id, :string

    timestamps()
  end

  @doc "Keys of the poster albums we maintain."
  def keys, do: @keys

  @doc false
  def changeset(album, attrs) do
    album
    |> cast(attrs, [:key, :google_album_id])
    |> validate_required([:key, :google_album_id])
    |> unique_constraint(:key)
  end
end
