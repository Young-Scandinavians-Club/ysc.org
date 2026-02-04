defmodule Ysc.Bookings.RoomCategory do
  @moduledoc """
  RoomCategory schema and changesets.

  Defines room categories (e.g., "single", "standard", "family") that can be used
  to group rooms with shared rules and pricing.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "room_categories" do
    field :name, :string
    field :notes, :string

    # Relationships
    has_many :rooms, Ysc.Bookings.Room, foreign_key: :room_category_id

    has_many :pricing_rules, Ysc.Bookings.PricingRule,
      foreign_key: :room_category_id

    timestamps()
  end

  @doc """
  Creates a changeset for the RoomCategory schema.
  """
  def changeset(room_category, attrs \\ %{}) do
    room_category
    |> cast(attrs, [:name, :notes])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_length(:notes, max: 1000)
    |> unique_constraint(:name)
  end
end
