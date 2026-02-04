defmodule Ysc.PropertyOutages.OutageTracker do
  @moduledoc """
  Outage tracker schema and changesets.

  Tracks property outages and incidents.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "property_outages" do
    field :description, :string

    field :incident_type, Ysc.PropertyOutages.PropertyOutageIncidentType

    field :company_name, :string

    field :incident_id, :string
    field :incident_date, :date

    field :property, Ysc.Bookings.BookingProperty

    field :raw_response, :map

    timestamps()
  end

  @doc """
  Creates a changeset for the OutageTracker schema.
  """
  def changeset(outage_tracker, attrs \\ %{}) do
    outage_tracker
    |> cast(attrs, [
      :description,
      :incident_type,
      :company_name,
      :incident_id,
      :incident_date,
      :property,
      :raw_response
    ])
    |> validate_required([:incident_id, :incident_type])
    |> unique_constraint(:incident_id)
  end
end
