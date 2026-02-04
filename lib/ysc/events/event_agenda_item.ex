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

    field :start_time, :time
    field :end_time, :time

    timestamps()
  end

  @doc """
  Creates a changeset for an agenda item.
  """
  def changeset(agenda_item, attrs) do
    agenda_item
    |> cast(attrs, [:title, :description, :start_time, :end_time, :agenda_id])
    |> validate_required([:title, :agenda_id])
    |> validate_length(:title, max: 256)
    |> validate_length(:description, max: 1024)
  end
end
