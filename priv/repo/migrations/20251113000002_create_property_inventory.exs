defmodule Ysc.Repo.Migrations.CreatePropertyInventory do
  use Ecto.Migration

  def change do
    create table(:property_inventory, primary_key: false) do
      add :property, :booking_property, null: false, primary_key: true
      add :day, :date, null: false, primary_key: true

      add :capacity_total, :integer, default: 0, null: false
      add :capacity_held, :integer, default: 0, null: false
      add :capacity_booked, :integer, default: 0, null: false

      add :buyout_held, :boolean, default: false, null: false
      add :buyout_booked, :boolean, default: false, null: false

      add :updated_at, :utc_datetime, default: fragment("now()"), null: false
    end

    # Add check constraints
    execute(
      "ALTER TABLE property_inventory ADD CONSTRAINT capacity_total_check CHECK (capacity_total >= 0)",
      "ALTER TABLE property_inventory DROP CONSTRAINT IF EXISTS capacity_total_check"
    )

    execute(
      "ALTER TABLE property_inventory ADD CONSTRAINT capacity_held_check CHECK (capacity_held >= 0)",
      "ALTER TABLE property_inventory DROP CONSTRAINT IF EXISTS capacity_held_check"
    )

    execute(
      "ALTER TABLE property_inventory ADD CONSTRAINT capacity_booked_check CHECK (capacity_booked >= 0)",
      "ALTER TABLE property_inventory DROP CONSTRAINT IF EXISTS capacity_booked_check"
    )

    # Create index on day for date range queries
    create index(:property_inventory, [:day], name: :prop_inv_day_idx)
  end
end
