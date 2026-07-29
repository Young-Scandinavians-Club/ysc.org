defmodule Mix.Tasks.Ysc.WpMigrationUnlock do
  @moduledoc """
  Clears the wp_migration_active site setting, re-enabling all webhook
  communications (emails, QuickBooks sync, etc.).

  Run this after the WP migration is complete and all Stripe webhooks
  have been processed. The app also clears this flag on boot.

  Usage:
    mix ysc.wp_migration_unlock
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Clear wp_migration_active flag to re-enable webhook comms"

  def run(_args) do
    Mix.Task.run("app.start")

    case Ysc.Settings.ensure_wp_migration_inactive() do
      :ok ->
        Ysc.Logging.info("[WP Migration] Comms suppression DISABLED via CLI")

        IO.puts("wp_migration_active is false — webhook comms are enabled.")

      {:error, reason} ->
        Mix.raise("Failed to update setting: #{inspect(reason)}")
    end
  end
end
