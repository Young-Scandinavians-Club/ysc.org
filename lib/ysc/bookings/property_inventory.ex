defmodule Ysc.Bookings.PropertyInventory do
  @moduledoc """
  Property inventory schema.

  Tracks capacity and buyout availability for each property on each day.
  This is the source of truth for property-level inventory locking.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "property_inventory" do
    field :property, Ysc.Bookings.BookingProperty, primary_key: true
    field :day, :date, primary_key: true

    field :capacity_total, :integer, default: 0
    field :capacity_held, :integer, default: 0
    field :capacity_booked, :integer, default: 0

    field :buyout_held, :boolean, default: false
    field :buyout_booked, :boolean, default: false

    field :lock_version, :integer, default: 1

    field :updated_at, :utc_datetime
  end

  @doc false
  def changeset(property_inventory, attrs) do
    property_inventory
    |> cast(attrs, [
      :property,
      :day,
      :capacity_total,
      :capacity_held,
      :capacity_booked,
      :buyout_held,
      :buyout_booked
    ])
    |> validate_required([:property, :day])
    |> validate_number(:capacity_total, greater_than_or_equal_to: 0)
    |> validate_number(:capacity_held, greater_than_or_equal_to: 0)
    |> validate_number(:capacity_booked, greater_than_or_equal_to: 0)
    |> optimistic_lock(:lock_version)
  end
end
