defmodule Ysc.Bookings.DoorCode do
  @moduledoc """
  Door code schema and changesets.

  Represents a door code for a property with active_from and active_to dates.
  Only one door code can be active at a time for each property (active_to is NULL).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "door_codes" do
    field :code, :string
    field :property, Ysc.Bookings.BookingProperty
    field :active_from, :utc_datetime
    field :active_to, :utc_datetime

    timestamps()
  end

  @doc """
  Creates a changeset for the DoorCode schema.
  """
  def changeset(door_code, attrs \\ %{}) do
    door_code
    |> cast(attrs, [:code, :property, :active_from, :active_to])
    |> validate_required([:code, :property, :active_from])
    |> validate_code_format()
    |> validate_length(:code, min: 4, max: 5)
  end

  defp validate_code_format(changeset) do
    code = get_field(changeset, :code)

    if code do
      # Code should be 4-5 alphanumeric characters
      if String.match?(code, ~r/^[A-Za-z0-9]{4,5}$/) do
        changeset
      else
        add_error(changeset, :code, "must be 4 or 5 alphanumeric characters")
      end
    else
      changeset
    end
  end

  @doc """
  Checks if a door code is currently active (active_to is nil).
  """
  def active?(%__MODULE__{active_to: nil}), do: true
  def active?(_), do: false
end
