defmodule Ysc.Bookings.RoomInventory do
  @moduledoc """
  Room inventory schema.

  Tracks held and booked status for each room on each day.
  This is the source of truth for room-level inventory locking.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Bookings.Room

  @primary_key false
  schema "room_inventory" do
    belongs_to :room, Room, primary_key: true, type: Ecto.ULID
    field :day, :date, primary_key: true

    field :held, :boolean, default: false
    field :booked, :boolean, default: false

    field :lock_version, :integer, default: 1

    field :updated_at, :utc_datetime
  end

  @doc false
  def changeset(room_inventory, attrs) do
    room_inventory
    |> cast(attrs, [:room_id, :day, :held, :booked])
    |> validate_required([:room_id, :day])
    |> optimistic_lock(:lock_version)
  end
end
