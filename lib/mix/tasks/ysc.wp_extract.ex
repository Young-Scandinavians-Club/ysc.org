defmodule Mix.Tasks.Ysc.WpExtract do
  @moduledoc """
  Phase 1: Extract WordPress backup data into a portable export directory.

  Reads the DuckDB file (from mix ysc.wp_to_duckdb) and wp_backup/files,
  writes users.json, applications.json, posts.json, stripe_customer_lookup.json,
  and an iterable media/ folder (one subfolder per image with file + meta.json).

  Usage:
    mix ysc.wp_extract --db wp_backup/wp.duckdb
    mix ysc.wp_extract --db wp_backup/wp.duckdb --export-dir wp_migration_export [--wp-files wp_backup/files] [--dry-run]
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Extract WP backup to export dir (JSON + media folder)"

  @switches [
    db: :string,
    export_dir: :string,
    wp_files: :string,
    dry_run: :boolean
  ]

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: @switches,
        aliases: [d: :db, e: :export_dir]
      )

    db = opts[:db]
    export_dir = opts[:export_dir] || "wp_migration_export"
    wp_files = opts[:wp_files] || "wp_backup/files"
    dry_run = opts[:dry_run] || false

    if is_nil(db) or db == "" do
      Mix.raise("""
      Missing --db. Provide the path to the DuckDB file (from mix ysc.wp_to_duckdb).

      Example:
        mix ysc.wp_extract --db wp_backup/wp.duckdb
        mix ysc.wp_extract --db wp_backup/wp.duckdb --export-dir wp_migration_export
      """)
    end

    Ysc.Logging.info("Starting WP extract",
      db: db,
      export_dir: export_dir,
      dry_run: dry_run
    )

    case Ysc.WpMigration.Extract.run(
           db: db,
           export_dir: export_dir,
           wp_files: wp_files,
           dry_run: dry_run
         ) do
      {:ok, out} ->
        if dry_run,
          do: IO.puts("Dry run complete. Would write to #{out}"),
          else: IO.puts("Extract complete. Export written to #{out}")

      {:error, reason} ->
        Mix.raise("Extract failed: #{inspect(reason)}")
    end
  end
end
