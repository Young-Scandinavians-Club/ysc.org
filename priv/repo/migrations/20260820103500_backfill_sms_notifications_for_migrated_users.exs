defmodule Ysc.Repo.Migrations.BackfillSmsNotificationsForMigratedUsers do
  use Ecto.Migration

  def up do
    # WP-migrated users were imported without an SMS opt-in, forcing
    # account_notifications_sms/event_notifications_sms to false regardless of
    # their (untouched, default-true) email notification prefs. Verifying
    # their phone during the post-migration onboarding wizard never
    # re-synced those SMS prefs, so migrated users who already verified
    # their phone before this fix are stuck with SMS off even though they
    # have the matching email notification on.
    #
    # `post_migration_onboarding_completed_at IS NULL` is the wp_migrated?
    # marker (see Ysc.Accounts.wp_migrated?/1) - scoped to users who haven't
    # finished the onboarding wizard yet, so we never touch a native user's
    # deliberate SMS opt-out made via the phone-entry checkbox.
    execute """
    UPDATE users
    SET account_notifications_sms = true
    WHERE phone_verified_at IS NOT NULL
      AND post_migration_onboarding_completed_at IS NULL
      AND account_notifications = true
      AND account_notifications_sms = false
    """

    execute """
    UPDATE users
    SET event_notifications_sms = true
    WHERE phone_verified_at IS NOT NULL
      AND post_migration_onboarding_completed_at IS NULL
      AND event_notifications = true
      AND event_notifications_sms = false
    """
  end

  def down do
    # Intentional no-op: we cannot restore prior opt-out state after backfill.
  end
end
