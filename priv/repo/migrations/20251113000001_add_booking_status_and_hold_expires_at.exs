defmodule Ysc.Repo.Migrations.AddBookingStatusAndHoldExpiresAt do
  use Ecto.Migration

  def up do
    # Create booking_status enum
    execute(
      "CREATE TYPE booking_status AS ENUM ('draft', 'hold', 'complete', 'refunded', 'canceled')",
      "DROP TYPE IF EXISTS booking_status"
    )

    # Add status and hold_expires_at to bookings
    alter table(:bookings) do
      add :status, :booking_status, default: "draft", null: false
      add :hold_expires_at, :utc_datetime, null: true
    end

    # Create index on status for filtering
    create index(:bookings, [:status, :hold_expires_at])
  end

  def down do
    drop index(:bookings, [:status, :hold_expires_at])

    alter table(:bookings) do
      remove :hold_expires_at
      remove :status
    end

    execute("DROP TYPE IF EXISTS booking_status", "")
  end
end
