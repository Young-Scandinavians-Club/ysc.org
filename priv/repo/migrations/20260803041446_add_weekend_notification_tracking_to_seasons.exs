defmodule Ysc.Repo.Migrations.AddWeekendNotificationTrackingToSeasons do
  use Ecto.Migration

  def change do
    alter table(:seasons) do
      # Tracks the "first bookable weekend" blast email (season-relative, not
      # admin editable — see Ysc.Bookings.SeasonWeekendAvailabilityWorker).
      # Cycle year is the resolved occurrence's start year (e.g. 2026 for the
      # Nov 2026 - Apr 2027 Winter occurrence), so the same season row can be
      # notified again next year without a migration/reset.
      add :weekend_notification_sent_cycle_year, :integer, null: true
      add :weekend_notification_sent_at, :utc_datetime, null: true
      add :weekend_notification_recipient_count, :integer, null: true
    end
  end
end
