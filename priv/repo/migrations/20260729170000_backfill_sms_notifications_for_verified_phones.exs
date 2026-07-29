defmodule Ysc.Repo.Migrations.BackfillSmsNotificationsForVerifiedPhones do
  use Ecto.Migration

  def up do
    execute """
    UPDATE users
    SET account_notifications_sms = true,
        event_notifications_sms = true
    WHERE phone_verified_at IS NOT NULL
      AND (account_notifications_sms = false OR event_notifications_sms = false)
    """
  end

  def down do
    # Intentional no-op: we cannot restore prior opt-out choices after backfill.
  end
end
