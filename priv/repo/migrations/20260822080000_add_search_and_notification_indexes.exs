defmodule Ysc.Repo.Migrations.AddSearchAndNotificationIndexes do
  @moduledoc """
  Speeds up admin/check-in user search and bulk event-notification lookups.

  ## Problem

  `Accounts.search_users/2` (admin autocomplete, check-in) and `Ysc.Search`
  use `ILIKE '%term%'` / `SIMILARITY(...)`. pg_trgm is enabled but there were
  no GIN indexes, so those queries Seq Scanned `users` (and event/post titles).

  Event and season-weekend blasts loaded every column of every opted-in active
  member (`hashed_password` included). CI EXPLAIN on `AuthEvent` suspicious
  events was a Seq Scan + Sort of the full `auth_events` table.

  ## Solution

  - GIN trigram indexes for name/email/phone and event/post titles
  - Partial index of opted-in active members for blast recipient queries
  - Partial `(inserted_at DESC)` index of suspicious auth events
  """
  use Ecto.Migration

  def change do
    execute """
            CREATE INDEX users_first_name_trgm_index
            ON users USING gin (first_name gin_trgm_ops)
            """,
            "DROP INDEX users_first_name_trgm_index"

    execute """
            CREATE INDEX users_last_name_trgm_index
            ON users USING gin (last_name gin_trgm_ops)
            """,
            "DROP INDEX users_last_name_trgm_index"

    execute """
            CREATE INDEX users_email_trgm_index
            ON users USING gin ((email::text) gin_trgm_ops)
            """,
            "DROP INDEX users_email_trgm_index"

    execute """
            CREATE INDEX users_full_name_trgm_index
            ON users USING gin ((first_name || ' ' || last_name) gin_trgm_ops)
            """,
            "DROP INDEX users_full_name_trgm_index"

    execute """
            CREATE INDEX users_phone_number_trgm_index
            ON users USING gin (phone_number gin_trgm_ops)
            """,
            "DROP INDEX users_phone_number_trgm_index"

    execute """
            CREATE INDEX events_title_trgm_index
            ON events USING gin (title gin_trgm_ops)
            """,
            "DROP INDEX events_title_trgm_index"

    execute """
            CREATE INDEX posts_title_trgm_index
            ON posts USING gin (title gin_trgm_ops)
            """,
            "DROP INDEX posts_title_trgm_index"

    create index(:users, [:id],
             name: :users_event_notification_recipients_index,
             where: "event_notifications = TRUE AND state = 'active'"
           )

    execute """
            CREATE INDEX auth_events_suspicious_inserted_at_index
            ON auth_events (inserted_at DESC)
            WHERE is_suspicious = TRUE
            """,
            "DROP INDEX auth_events_suspicious_inserted_at_index"
  end
end
