defmodule Ysc.Repo.Migrations.CreateBookingRoomsJoinTable do
  use Ecto.Migration

  def up do
    # Create the join table
    create table(:booking_rooms, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :booking_id,
          references(:bookings, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :room_id, references(:rooms, column: :id, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime)
    end

    # Create indexes
    create index(:booking_rooms, [:booking_id])
    create index(:booking_rooms, [:room_id])
    create unique_index(:booking_rooms, [:booking_id, :room_id], name: :booking_rooms_unique)

    # Migrate existing data: move room_id from bookings to booking_rooms
    # Note: Using gen_random_uuid() directly (returns uuid type) and casting booking/room ids
    execute("""
      INSERT INTO booking_rooms (id, booking_id, room_id, inserted_at, updated_at)
      SELECT
        gen_random_uuid(),
        id::uuid,
        room_id::uuid,
        inserted_at,
        updated_at
      FROM bookings
      WHERE room_id IS NOT NULL
    """)

    # Remove the room_id column from bookings (but keep it for now in case we need to rollback)
    # We'll remove it in a separate migration after verifying the data migration
  end

  def down do
    # Restore room_id from booking_rooms (take first room if multiple)
    execute("""
      UPDATE bookings
      SET room_id = (
        SELECT room_id
        FROM booking_rooms
        WHERE booking_rooms.booking_id = bookings.id
        ORDER BY booking_rooms.inserted_at
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM booking_rooms WHERE booking_rooms.booking_id = bookings.id
      )
    """)

    drop index(:booking_rooms, [:booking_id, :room_id], name: :booking_rooms_unique)
    drop index(:booking_rooms, [:room_id])
    drop index(:booking_rooms, [:booking_id])
    drop table(:booking_rooms)
  end
end
