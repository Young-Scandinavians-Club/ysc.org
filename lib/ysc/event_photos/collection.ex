defmodule Ysc.EventPhotos.Collection do
  @moduledoc """
  Per-event Google Photos upload collection: stable upload token and optional album id.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ysc.Events.Event

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "event_photo_collections" do
    belongs_to :event, Event

    field :upload_token, Ecto.UUID
    field :google_album_id, :string
    field :reminder_sent_at, :utc_datetime

    timestamps()
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [
      :event_id,
      :upload_token,
      :google_album_id,
      :reminder_sent_at
    ])
    |> validate_required([:event_id, :upload_token])
    |> unique_constraint(:event_id)
    |> unique_constraint(:upload_token)
    |> foreign_key_constraint(:event_id)
  end
end
