defmodule Ysc.Repo.Migrations.AddEventsPublicListingStartIndex do
  use Ecto.Migration

  def change do
    # Speeds up public upcoming-event listings (`start_date > now` + published/cancelled)
    # by narrowing the index to visible states only (CI EXPLAIN: bitmap scan on `state`
    # then filter on `start_date` → index range scan on `start_date` for this predicate).
    create index(:events, [:start_date, :start_time],
             name: :events_public_listing_by_start,
             where: "state IN ('published', 'cancelled')"
           )
  end
end
