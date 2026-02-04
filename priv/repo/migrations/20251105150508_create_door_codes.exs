defmodule Ysc.Repo.Migrations.CreateDoorCodes do
  use Ecto.Migration

  def up do
    # Create door_codes table
    create table(:door_codes, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :code, :string, size: 5, null: false
      add :property, :booking_property, null: false
      add :active_from, :utc_datetime, null: false
      add :active_to, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:door_codes, [:property], name: :door_codes_property_index)

    create index(:door_codes, [:property, :active_from],
             name: :door_codes_property_active_from_index
           )

    # Index to help find the active code (where active_to is NULL)
    create index(:door_codes, [:property],
             where: "active_to IS NULL",
             name: :door_codes_property_active_index
           )
  end

  def down do
    drop index(:door_codes, [:property], name: :door_codes_property_index)

    drop index(:door_codes, [:property, :active_from],
           name: :door_codes_property_active_from_index
         )

    drop index(:door_codes, [:property],
           where: "active_to IS NULL",
           name: :door_codes_property_active_index
         )

    drop table(:door_codes)
  end
end
