defmodule Ysc.Events.AgendaItem do
  @moduledoc """
  Agenda item schema and changesets.

  Defines the AgendaItem database schema, validations, and changeset functions
  for agenda item data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "agenda_items" do
    belongs_to :agenda, Ysc.Events.Agenda,
      foreign_key: :agenda_id,
      references: :id

    field :position, :integer

    field :title, :string
    field :description, :string

    field :start_time, Ysc.Ecto.DateKind, kind: :pacific_time
    field :end_time, Ysc.Ecto.DateKind, kind: :pacific_time

    timestamps()
  end

  @doc """
  Creates a changeset for an agenda item.

  Does not cast `:agenda_id` — association ownership is set by the Agendas
  context (`create_agenda_item/3`, `move_agenda_item_to_agenda/4`). Casting
  `agenda_id` from LiveView params allowed planting or moving items onto
  another event's agenda (Finding 75, sibling of Finding 64).
  """
  def changeset(agenda_item, attrs) do
    agenda_item
    |> cast(attrs, [:title, :description, :start_time, :end_time])
    |> validate_required([:title, :agenda_id])
    |> validate_length(:title, max: 256)
    |> validate_length(:description, max: 1024)
  end
end
