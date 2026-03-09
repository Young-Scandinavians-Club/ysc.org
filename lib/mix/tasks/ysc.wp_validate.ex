defmodule Mix.Tasks.Ysc.WpValidate do
  @moduledoc """
  Validates migration data counts against the WordPress backup and optionally the
  intermediary export directory.

  Phase 1 only (source counts from DuckDB):
    mix ysc.wp_validate --db wp_backup/wp.duckdb

  Phase 1 + 2 comparison (source vs export):
    mix ysc.wp_validate --db wp_backup/wp.duckdb --export-dir wp_migration_export
  """

  use Mix.Task

  @shortdoc "Validate WP migration data counts"

  @switches [
    db: :string,
    export_dir: :string
  ]

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(List.wrap(args),
        strict: @switches,
        aliases: [d: :db, e: :export_dir]
      )

    db = opts[:db]
    export_dir = opts[:export_dir]

    if is_nil(db) or db == "" do
      Mix.raise("""
      Missing --db. Provide the path to the DuckDB file (from mix ysc.wp_to_duckdb).

      Example:
        mix ysc.wp_validate --db wp_backup/wp.duckdb
        mix ysc.wp_validate --db wp_backup/wp.duckdb --export-dir wp_migration_export
      """)
    end

    validate_opts =
      [db: db] ++ if(export_dir, do: [export_dir: export_dir], else: [])

    case Ysc.WpMigration.Validate.run(validate_opts) do
      :ok -> :ok
      {:warn, _} -> System.at_exit(fn _ -> exit({:shutdown, 1}) end)
      {:error, reason} -> Mix.raise("Validation error: #{reason}")
    end
  end
end
