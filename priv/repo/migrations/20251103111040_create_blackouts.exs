defmodule Ysc.Repo.Migrations.CreateBlackouts do
  use Ecto.Migration

  def change do
    # Create blackouts table for property hold dates
    create table(:blackouts, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :reason, :text, null: false
      add :property, :booking_property, null: false
      add :start_date, :date, null: false
      add :end_date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    # Index for efficient date range queries
    create index(:blackouts, [:property])
    create index(:blackouts, [:start_date, :end_date])

    # Check constraint to ensure end_date >= start_date
    create constraint(:blackouts, :blackout_date_range, check: "start_date <= end_date")
  end
end
