defmodule Ysc.Bookings.CheckInVehicle do
  @moduledoc """
  CheckInVehicle schema and changesets.

  Represents a vehicle associated with a check-in.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "check_in_vehicles" do
    field :type, :string
    field :color, :string
    field :make, :string

    belongs_to :check_in, Ysc.Bookings.CheckIn,
      foreign_key: :check_in_id,
      references: :id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for the CheckInVehicle schema.
  """
  def changeset(check_in_vehicle, attrs \\ %{}) do
    check_in_vehicle
    |> cast(attrs, [:type, :color, :make, :check_in_id])
    |> validate_required([:type, :color, :make, :check_in_id])
    |> validate_length(:type, max: 100)
    |> validate_length(:color, max: 100)
    |> validate_length(:make, max: 100)
    |> foreign_key_constraint(:check_in_id)
  end
end
