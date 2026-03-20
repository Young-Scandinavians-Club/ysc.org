defmodule Mix.Tasks.Ysc.WpMigrationUnlock do
  @moduledoc """
  Clears the wp_migration_active site setting, re-enabling all webhook
  communications (emails, QuickBooks sync, etc.).

  Run this after the WP migration is complete and all Stripe webhooks
  have been processed.

  Usage:
    mix ysc.wp_migration_unlock
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Clear wp_migration_active flag to re-enable webhook comms"

  def run(_args) do
    Mix.Task.run("app.start")

    current = Ysc.Settings.get_setting_safe("wp_migration_active")

    if current == "true" do
      case Ysc.Settings.update_setting("wp_migration_active", "false") do
        {:ok, _} ->
          Ysc.Logging.info("[WP Migration] Comms suppression DISABLED via CLI")

          IO.puts(
            "wp_migration_active set to false — webhook comms re-enabled."
          )

        {:error, reason} ->
          Mix.raise("Failed to update setting: #{inspect(reason)}")
      end
    else
      IO.puts(
        "wp_migration_active is already #{inspect(current)} — nothing to do."
      )
    end
  end
end
