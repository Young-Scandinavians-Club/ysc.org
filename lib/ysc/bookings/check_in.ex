defmodule Ysc.Bookings.CheckIn do
  @moduledoc """
  CheckIn schema and changesets.

  Represents a property check-in that can reference multiple bookings.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "check_ins" do
    field :rules_agreed, :boolean, default: false
    field :checked_in_at, :utc_datetime

    many_to_many :bookings, Ysc.Bookings.Booking,
      join_through: Ysc.Bookings.CheckInBooking

    has_many :check_in_vehicles, Ysc.Bookings.CheckInVehicle,
      foreign_key: :check_in_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for the CheckIn schema.
  """
  def changeset(check_in, attrs \\ %{}) do
    check_in
    |> cast(attrs, [:rules_agreed, :checked_in_at])
    |> validate_required([:rules_agreed, :checked_in_at])
    |> put_checked_in_at()
  end

  defp put_checked_in_at(changeset) do
    case get_change(changeset, :checked_in_at) do
      nil ->
        put_change(changeset, :checked_in_at, DateTime.utc_now())

      _ ->
        changeset
    end
  end
end
