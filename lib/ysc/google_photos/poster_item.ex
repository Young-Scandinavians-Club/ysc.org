defmodule Ysc.GooglePhotos.PosterItem do
  @moduledoc """
  A TV poster media item we added to one of the poster Google Photos albums for an event.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ysc.Events.Event
  alias Ysc.GooglePhotos.PosterAlbum

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "google_photos_poster_items" do
    belongs_to :event, Event

    field :key, Ecto.Enum, values: PosterAlbum.keys()
    field :google_album_id, :string
    field :media_item_id, :string
    field :poster_hash, :string

    timestamps()
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :event_id,
      :key,
      :google_album_id,
      :media_item_id,
      :poster_hash
    ])
    |> validate_required([
      :event_id,
      :key,
      :google_album_id,
      :media_item_id,
      :poster_hash
    ])
    |> unique_constraint([:event_id, :key])
    |> foreign_key_constraint(:event_id)
  end
end
