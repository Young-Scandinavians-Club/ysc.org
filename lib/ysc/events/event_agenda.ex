defmodule Ysc.Events.Agenda do
  @moduledoc """
  Agenda schema and changesets.

  Defines the Agenda database schema, validations, and changeset functions
  for agenda data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "agendas" do
    belongs_to :event, Ysc.Events.Event, foreign_key: :event_id, references: :id

    field :position, :integer
    field :title, :string

    has_many :agenda_items, Ysc.Events.AgendaItem,
      foreign_key: :agenda_id,
      preload_order: [asc: :position]

    timestamps()
  end

  def changeset(agenda, attrs) do
    agenda
    |> cast(attrs, [:title, :event_id])
    |> validate_required([:title, :event_id])
    |> validate_length(:title, max: 256)
    |> foreign_key_constraint(:event_id)
  end
end
