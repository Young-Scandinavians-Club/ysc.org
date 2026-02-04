defmodule Ysc.Repo.Migrations.CreatePropertyOutages do
  use Ecto.Migration

  def change do
    # Create enum type for incident types
    execute(
      "CREATE TYPE property_outage_incident_type AS ENUM ('power_outage', 'water_outage', 'internet_outage')",
      "DROP TYPE IF EXISTS property_outage_incident_type"
    )

    # Create property_outages table
    create table(:property_outages, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :description, :text
      add :incident_type, :property_outage_incident_type
      add :company_name, :text
      add :incident_id, :text, null: false
      add :incident_date, :date
      add :property, :booking_property

      timestamps(type: :utc_datetime)
    end

    # Create unique index on incident_id for upserts
    create unique_index(:property_outages, [:incident_id])
    create index(:property_outages, [:property])
  end
end
