defmodule Ysc.Repo.Migrations.CreateBookingModels do
  use Ecto.Migration

  def change do
    # Create enum types
    execute("CREATE EXTENSION IF NOT EXISTS btree_gist", "")
    execute("CREATE TYPE booking_property AS ENUM ('tahoe', 'clear_lake')", "")

    execute(
      "CREATE TYPE booking_mode AS ENUM ('room', 'day', 'buyout')",
      "DROP TYPE IF EXISTS booking_mode"
    )

    execute(
      "CREATE TYPE price_unit AS ENUM ('per_person_per_night', 'per_guest_per_day', 'buyout_fixed')",
      "DROP TYPE IF EXISTS price_unit"
    )

    # Create seasons table
    create table(:seasons, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :name, :text, null: false
      add :description, :text, null: true

      # Property this season applies to
      add :property, :booking_property, null: false

      # Season date range
      add :start_date, :date, null: false
      add :end_date, :date, null: false

      # Whether this is the default season for the property
      add :is_default, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:seasons, [:property])
    create index(:seasons, [:start_date, :end_date])

    # Create partial unique index to ensure only one default season per property
    # This is enforced at the database level
    execute(
      "CREATE UNIQUE INDEX seasons_property_default_unique ON seasons(property) WHERE is_default = true",
      "DROP INDEX IF EXISTS seasons_property_default_unique"
    )

    # Create room_categories table
    create table(:room_categories, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :name, :text, null: false
      add :notes, :text, null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:room_categories, [:name])

    # Create rooms table
    create table(:rooms, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :name, :text, null: false
      add :description, :text, null: true

      # Property location (tahoe or clear_lake)
      add :property, :booking_property, null: false

      # Capacity constraints
      # capacity_max: hard limit (e.g., single bed → 1, max 12)
      add :capacity_max, :integer, null: false

      # min_billable_occupancy: billing floor (e.g., family room → 2)
      # This is separate from capacity - determines minimum billing amount
      add :min_billable_occupancy, :integer, default: 1, null: false

      # Whether this is a single bed room (max 1 person)
      add :is_single_bed, :boolean, default: false, null: false

      # Active/inactive status
      add :is_active, :boolean, default: true, null: false

      # Optional reference to room category
      add :room_category_id,
          references(:room_categories, column: :id, type: :binary_id, on_delete: :nilify_all),
          null: true

      # Optional reference to default season
      add :default_season_id,
          references(:seasons, column: :id, type: :binary_id, on_delete: :nilify_all),
          null: true

      timestamps(type: :utc_datetime)
    end

    # Add check constraints for capacity
    create constraint(:rooms, :capacity_max_range, check: "capacity_max BETWEEN 1 AND 12")

    create constraint(:rooms, :min_billable_range, check: "min_billable_occupancy >= 1")

    create index(:rooms, [:property])
    create index(:rooms, [:is_active])
    create index(:rooms, [:room_category_id])
    create index(:rooms, [:default_season_id])

    # Create pricing_rules table for hierarchical pricing
    create table(:pricing_rules, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      # Price amount (stored as Money)
      add :amount, :money_with_currency, null: false

      # Booking mode (room, day, buyout)
      add :booking_mode, :booking_mode, null: false

      # Price unit (per_person_per_night, per_guest_per_day, buyout_fixed)
      add :price_unit, :price_unit, null: false

      # Hierarchical specificity (most specific first):
      # 1. room_id - applies to specific room (most specific)
      # 2. room_category_id - applies to category (medium)
      # 3. property + season - default fallback (least specific)
      add :room_id,
          references(:rooms, column: :id, type: :binary_id, on_delete: :delete_all),
          null: true

      add :room_category_id,
          references(:room_categories, column: :id, type: :binary_id, on_delete: :delete_all),
          null: true

      add :property, :booking_property, null: true

      add :season_id,
          references(:seasons, column: :id, type: :binary_id, on_delete: :delete_all),
          null: true

      timestamps(type: :utc_datetime)
    end

    # Create immutable helper functions for unique index with NULL handling
    # These functions are marked IMMUTABLE so they can be used in index expressions
    # Note: Cannot use STRICT here because we need COALESCE to handle NULLs
    execute(
      """
      CREATE OR REPLACE FUNCTION coalesce_uuid_text(uuid)
      RETURNS text AS $$
        SELECT COALESCE($1::text, '');
      $$ LANGUAGE sql IMMUTABLE;
      """,
      "DROP FUNCTION IF EXISTS coalesce_uuid_text(uuid)"
    )

    execute(
      """
      CREATE OR REPLACE FUNCTION coalesce_property_text(booking_property)
      RETURNS text AS $$
        SELECT COALESCE($1::text, '');
      $$ LANGUAGE sql IMMUTABLE;
      """,
      "DROP FUNCTION IF EXISTS coalesce_property_text(booking_property)"
    )

    execute(
      """
      CREATE OR REPLACE FUNCTION enum_mode_text(booking_mode)
      RETURNS text AS $$
        SELECT $1::text;
      $$ LANGUAGE sql IMMUTABLE;
      """,
      "DROP FUNCTION IF EXISTS enum_mode_text(booking_mode)"
    )

    execute(
      """
      CREATE OR REPLACE FUNCTION enum_unit_text(price_unit)
      RETURNS text AS $$
        SELECT $1::text;
      $$ LANGUAGE sql IMMUTABLE;
      """,
      "DROP FUNCTION IF EXISTS enum_unit_text(price_unit)"
    )

    # Create unique index to prevent duplicate rules with same specificity
    # Uses immutable helper functions to handle NULL values and enum casting
    # booking_mode and price_unit are NOT NULL so don't need COALESCE
    execute(
      """
      CREATE UNIQUE INDEX uq_pricing_rules_specificity ON pricing_rules (
        coalesce_uuid_text(room_id),
        coalesce_uuid_text(room_category_id),
        coalesce_property_text(property),
        coalesce_uuid_text(season_id),
        enum_mode_text(booking_mode),
        enum_unit_text(price_unit)
      )
      """,
      "DROP INDEX IF EXISTS uq_pricing_rules_specificity"
    )

    create index(:pricing_rules, [:room_id])
    create index(:pricing_rules, [:room_category_id])
    create index(:pricing_rules, [:property])
    create index(:pricing_rules, [:season_id])
    create index(:pricing_rules, [:booking_mode])
    create index(:pricing_rules, [:price_unit])
  end
end
