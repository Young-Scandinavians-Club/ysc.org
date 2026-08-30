defmodule Ysc.Repo.Migrations.AddTicketsActiveTierIdIndex do
  @moduledoc """
  Speeds up per-tier sold counts used during checkout capacity checks.

  `BookingLocker` batches `COUNT(*) ... GROUP BY ticket_tier_id` for
  confirmed and pending tickets. The existing `tickets_ticket_tier_id_index`
  includes cancelled/expired rows that accumulate over an event's life;
  this partial index matches the inventory query.
  """
  use Ecto.Migration

  def change do
    create_if_not_exists index(:tickets, [:ticket_tier_id],
                           where: "status IN ('confirmed', 'pending')",
                           name: :tickets_active_tier_id_index
                         )
  end
end
