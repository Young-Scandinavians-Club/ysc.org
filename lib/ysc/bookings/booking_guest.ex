defmodule Ysc.Bookings.BookingGuest do
  @moduledoc """
  BookingGuest schema and changesets.

  Represents a guest associated with a booking.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "booking_guests" do
    field :first_name, :string
    field :last_name, :string
    field :is_child, :boolean, default: false
    field :is_booking_user, :boolean, default: false
    field :order_index, :integer, default: 0

    belongs_to :booking, Ysc.Bookings.Booking,
      foreign_key: :booking_id,
      references: :id

    timestamps()
  end

  @doc """
  Creates a changeset for the BookingGuest schema.
  """
  def changeset(booking_guest, attrs \\ %{}) do
    booking_guest
    |> cast(attrs, [
      :first_name,
      :last_name,
      :is_child,
      :is_booking_user,
      :order_index,
      :booking_id
    ])
    |> validate_required([:first_name, :last_name, :booking_id])
    |> validate_length(:first_name, max: 150)
    |> validate_length(:last_name, max: 150)
    |> validate_number(:order_index, greater_than_or_equal_to: 0)
  end
end
