defmodule Ysc.Bookings.BookingRoom do
  @moduledoc """
  Join table schema for the many-to-many relationship between Bookings and Rooms.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "booking_rooms" do
    belongs_to :booking, Ysc.Bookings.Booking,
      foreign_key: :booking_id,
      references: :id

    belongs_to :room, Ysc.Bookings.Room, foreign_key: :room_id, references: :id

    timestamps(type: :utc_datetime)
  end
end
