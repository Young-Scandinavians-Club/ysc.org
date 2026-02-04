defmodule Ysc.Bookings.CheckInBooking do
  @moduledoc """
  Join table schema for the many-to-many relationship between CheckIns and Bookings.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "check_in_bookings" do
    belongs_to :check_in, Ysc.Bookings.CheckIn,
      foreign_key: :check_in_id,
      references: :id

    belongs_to :booking, Ysc.Bookings.Booking,
      foreign_key: :booking_id,
      references: :id

    timestamps(type: :utc_datetime)
  end
end
