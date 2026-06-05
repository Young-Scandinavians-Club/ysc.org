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
    field :reminder_recipient_count, :integer

    timestamps()
  end

  @doc false
  def insert_changeset(%__MODULE__{} = collection) do
    collection
    |> change()
    |> validate_required([:event_id, :upload_token])
    |> unique_constraint(:event_id)
    |> unique_constraint(:upload_token)
    |> foreign_key_constraint(:event_id)
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [
      :google_album_id,
      :reminder_sent_at,
      :reminder_recipient_count
    ])
    |> unique_constraint(:event_id)
    |> unique_constraint(:upload_token)
    |> foreign_key_constraint(:event_id)
  end
end
