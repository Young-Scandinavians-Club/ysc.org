defmodule Ysc.Repo.Migrations.BackfillSmsNotificationsForVerifiedPhones do
  use Ecto.Migration

  def up do
    # Preferences are NOT NULL with a DB default of true. Only backfill rows that
    # somehow still have NULL (older/partial states). Explicit false opt-outs are
    # preserved and must not be flipped to true.
    execute """
    UPDATE users
    SET account_notifications_sms = COALESCE(account_notifications_sms, true),
        event_notifications_sms = COALESCE(event_notifications_sms, true)
    WHERE phone_verified_at IS NOT NULL
      AND (account_notifications_sms IS NULL OR event_notifications_sms IS NULL)
    """
  end

  def down do
    # Intentional no-op: we cannot restore prior opt-out choices after backfill.
  end
end
