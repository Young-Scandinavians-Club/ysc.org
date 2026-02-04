defmodule Ysc.Repo.Migrations.CreateRoomInventory do
  use Ecto.Migration

  def change do
    create table(:room_inventory, primary_key: false) do
      add :room_id, references(:rooms, column: :id, type: :binary_id, on_delete: :restrict),
        null: false,
        primary_key: true

      add :day, :date, null: false, primary_key: true

      add :held, :boolean, default: false, null: false
      add :booked, :boolean, default: false, null: false

      add :updated_at, :utc_datetime, default: fragment("now()"), null: false
    end

    # Create index on day for date range queries
    create index(:room_inventory, [:day], name: :room_inv_day_idx)
  end
end
