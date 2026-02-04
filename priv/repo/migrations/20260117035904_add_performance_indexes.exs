defmodule Ysc.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def up do
    # Bookings table indexes
    # Status is frequently used in WHERE clauses
    create index(:bookings, [:status])

    # Inserted_at is used for sorting in many queries
    create index(:bookings, [:inserted_at])

    # Composite indexes for common query patterns
    # user_id + status (e.g., list_user_bookings_paginated, home_live)
    create index(:bookings, [:user_id, :status])

    # property + status (common in admin views)
    create index(:bookings, [:property, :status])

    # status + checkin_date (for active bookings queries)
    create index(:bookings, [:status, :checkin_date])

    # Tickets table indexes
    # inserted_at is used for sorting
    create index(:tickets, [:inserted_at])

    # Composite index for user_id + status + event_id (common pattern)
    create index(:tickets, [:user_id, :status, :event_id])

    # Ticket Orders table indexes
    # inserted_at is used for sorting (Flop default_order)
    create index(:ticket_orders, [:inserted_at])

    # Composite index for user_id + status (common in list_user_ticket_orders)
    create index(:ticket_orders, [:user_id, :status])

    # Composite index for event_id + status (common in event-related queries)
    create index(:ticket_orders, [:event_id, :status])
  end

  def down do
    # Drop indexes in reverse order
    drop index(:ticket_orders, [:event_id, :status])
    drop index(:ticket_orders, [:user_id, :status])
    drop index(:ticket_orders, [:inserted_at])

    drop index(:tickets, [:user_id, :status, :event_id])
    drop index(:tickets, [:inserted_at])

    drop index(:bookings, [:status, :checkin_date])
    drop index(:bookings, [:property, :status])
    drop index(:bookings, [:user_id, :status])
    drop index(:bookings, [:inserted_at])
    drop index(:bookings, [:status])
  end
end
