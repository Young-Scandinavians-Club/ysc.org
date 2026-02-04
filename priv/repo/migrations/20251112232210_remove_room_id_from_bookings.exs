defmodule Ysc.Repo.Migrations.RemoveRoomIdFromBookings do
  use Ecto.Migration

  def up do
    # Remove the room_id column and its index
    drop index(:bookings, [:room_id])

    alter table(:bookings) do
      remove :room_id
    end
  end

  def down do
    # Add room_id back (nullable since we may have bookings with multiple rooms)
    alter table(:bookings) do
      add :room_id, references(:rooms, column: :id, type: :binary_id, on_delete: :nilify_all),
        null: true
    end

    create index(:bookings, [:room_id])
  end
end
