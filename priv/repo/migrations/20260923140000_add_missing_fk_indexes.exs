defmodule Ysc.Repo.Migrations.AddMissingFkIndexes do
  @moduledoc """
  Adds indexes for FK columns flagged by the `missing_fk_indexes` admin
  dashboard report.

  `booking_entitlements.room_id` and `expense_reports.address_id` use
  `on_delete: :nilify_all`; deleting a room or address without these
  indexes forces a full scan of the referencing table. `scan_records.
  ticket_order_id` uses `on_delete: :restrict`, so deleting a ticket
  order forces the same kind of scan to check for references, and
  scan_records is one of the largest, highest-write tables in the app.
  """
  use Ecto.Migration

  def change do
    create index(:booking_entitlements, [:room_id])
    create index(:expense_reports, [:address_id])
    create index(:scan_records, [:ticket_order_id])
  end
end
