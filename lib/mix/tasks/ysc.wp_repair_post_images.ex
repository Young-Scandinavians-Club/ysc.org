defmodule Mix.Tasks.Ysc.WpRepairPostImages do
  @moduledoc """
  Repairs image links in WordPress-migrated news posts.

  Reads `posts.json` from the export directory, rebuilds attachment URLs from
  migration images in the media library, and updates post bodies to use the new
  system URLs.

  Usage:
    mix ysc.wp_repair_post_images --export-dir wp_migration_export
    mix ysc.wp_repair_post_images --export-dir wp_migration_export --dry-run
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Repair WP-migrated news post image links"

  @switches [
    export_dir: :string,
    dry_run: :boolean
  ]

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, strict: @switches, aliases: [e: :export_dir])

    export_dir = opts[:export_dir]
    dry_run = opts[:dry_run] || false

    if is_nil(export_dir) or export_dir == "" do
      Mix.raise("""
      Missing --export-dir. Provide the path to the export directory from Phase 1.

      Example:
        mix ysc.wp_repair_post_images --export-dir wp_migration_export
        mix ysc.wp_repair_post_images --export-dir wp_migration_export --dry-run
      """)
    end

    Ysc.Logging.info("Starting WP post image repair",
      export_dir: export_dir,
      dry_run: dry_run
    )

    case Ysc.WpMigration.Load.repair_post_images(export_dir, dry_run: dry_run) do
      {:ok, stats} ->
        IO.puts(
          "Post image repair complete. updated=#{stats.updated} unchanged=#{stats.unchanged} skipped=#{stats.skipped} failed=#{stats.failed}"
        )

      {:error, message} ->
        Mix.raise("Post image repair failed: #{message}")
    end
  end
end
