defmodule Ysc.Bookings.Room do
  @moduledoc """
  Room schema and changesets.

  Defines the Room database schema for booking rooms at properties.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "rooms" do
    field :name, :string
    field :description, :string

    # Property location (tahoe or clear_lake)
    field :property, Ysc.Bookings.BookingProperty

    # Capacity constraints
    field :capacity_max, :integer
    field :min_billable_occupancy, :integer, default: 1

    # Whether this is a single bed room (max 1 person)
    field :is_single_bed, :boolean, default: false

    # Active/inactive status
    field :is_active, :boolean, default: true

    # Bed counts
    field :single_beds, :integer, default: 0
    field :queen_beds, :integer, default: 0
    field :king_beds, :integer, default: 0

    # Relationships
    belongs_to :room_category, Ysc.Bookings.RoomCategory,
      foreign_key: :room_category_id

    belongs_to :default_season, Ysc.Bookings.Season,
      foreign_key: :default_season_id

    belongs_to :image, Ysc.Media.Image, foreign_key: :image_id

    many_to_many :bookings, Ysc.Bookings.Booking,
      join_through: Ysc.Bookings.BookingRoom

    has_many :pricing_rules, Ysc.Bookings.PricingRule, foreign_key: :room_id

    timestamps()
  end

  @doc """
  Creates a changeset for the Room schema.
  """
  def changeset(room, attrs \\ %{}) do
    room
    |> cast(attrs, [
      :name,
      :description,
      :property,
      :capacity_max,
      :min_billable_occupancy,
      :is_single_bed,
      :is_active,
      :room_category_id,
      :default_season_id,
      :single_beds,
      :queen_beds,
      :king_beds,
      :image_id
    ])
    |> validate_required([:name, :property, :capacity_max])
    |> validate_length(:name, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_number(:capacity_max,
      greater_than: 0,
      less_than_or_equal_to: 12
    )
    |> validate_number(:min_billable_occupancy, greater_than_or_equal_to: 1)
    |> validate_number(:single_beds, greater_than_or_equal_to: 0)
    |> validate_number(:queen_beds, greater_than_or_equal_to: 0)
    |> validate_number(:king_beds, greater_than_or_equal_to: 0)
  end

  @doc """
  Calculates the billable number of people for a room given a guest count.

  This respects the room's `min_billable_occupancy` setting, which ensures
  that rooms with minimum occupancy requirements (e.g., family rooms requiring
  at least 2 guests) are billed correctly.

  ## Examples

      iex> room = %Room{min_billable_occupancy: 2, capacity_max: 5}
      iex> Room.billable_people(room, 1)
      2

      iex> room = %Room{min_billable_occupancy: 1, capacity_max: 2}
      iex> Room.billable_people(room, 1)
      1

      iex> room = %Room{min_billable_occupancy: 2, capacity_max: 5}
      iex> Room.billable_people(room, 3)
      3
  """
  def billable_people(%__MODULE__{} = room, guests_count)
      when is_integer(guests_count) do
    min_occupancy = room.min_billable_occupancy || 1
    max(guests_count, min_occupancy)
  end

  def billable_people(_room, _guests_count), do: nil
end
