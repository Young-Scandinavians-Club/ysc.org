defmodule Ysc.Repo.Migrations.UniqueTicketDetailsTicketId do
  use Ecto.Migration

  def up do
    # Keep the newest row when a ticket already has duplicate attendee details
    # (possible after a double payment-success insert before this unique index).
    execute("""
    DELETE FROM ticket_details
    WHERE id IN (
      SELECT id FROM (
        SELECT id,
               row_number() OVER (
                 PARTITION BY ticket_id
                 ORDER BY inserted_at DESC, id DESC
               ) AS rn
        FROM ticket_details
        WHERE ticket_id IS NOT NULL
      ) ranked
      WHERE rn > 1
    )
    """)

    drop_if_exists index(:ticket_details, [:ticket_id])
    create unique_index(:ticket_details, [:ticket_id])
  end

  def down do
    drop_if_exists unique_index(:ticket_details, [:ticket_id])
    create index(:ticket_details, [:ticket_id])
  end
end
