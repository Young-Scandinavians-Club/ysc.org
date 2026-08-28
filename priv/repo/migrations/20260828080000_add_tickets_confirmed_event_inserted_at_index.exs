defmodule Ysc.Repo.Migrations.AddTicketsConfirmedEventInsertedAtIndex do
  @moduledoc """
  Speeds up confirmed-ticket lookups by event.

  Admin ticket lists, check-in desks, and sold-count aggregations filter
  `tickets` with `event_id` + `status = confirmed` (often ordered by
  `inserted_at`). Existing indexes are `event_id`, `status`, and
  `event_id + checked_in` — none cover that confirmed-by-event shape, so
  Postgres still filters the full per-event ticket set (including pending
  checkout rows).
  """
  use Ecto.Migration

  def change do
    create_if_not_exists index(:tickets, [:event_id, :inserted_at],
                           where: "status = 'confirmed'",
                           name: :tickets_confirmed_event_inserted_at_index
                         )
  end
end
