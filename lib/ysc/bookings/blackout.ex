defmodule Ysc.Bookings.Blackout do
  @moduledoc """
  Blackout schema and changesets.

  Defines blackout periods (hold dates) for properties to block off dates
  for maintenance, events, or other reasons. Blackouts prevent bookings
  during the specified date range.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "blackouts" do
    field :reason, :string
    field :property, Ysc.Bookings.BookingProperty
    field :start_date, :date
    field :end_date, :date

    timestamps()
  end

  @doc """
  Creates a changeset for the Blackout schema.
  """
  def changeset(blackout, attrs \\ %{}) do
    blackout
    |> cast(attrs, [:reason, :property, :start_date, :end_date])
    |> validate_required([:reason, :property, :start_date, :end_date])
    |> validate_length(:reason, max: 500)
    |> validate_date_range()
  end

  # Validates that end_date is after or equal to start_date
  defp validate_date_range(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date do
      if Date.compare(end_date, start_date) == :lt do
        add_error(changeset, :end_date, "must be on or after start date")
      else
        changeset
      end
    else
      changeset
    end
  end
end
