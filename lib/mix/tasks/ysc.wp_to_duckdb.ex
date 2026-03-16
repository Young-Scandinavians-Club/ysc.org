defmodule Mix.Tasks.Ysc.WpToDuckdb do
  @moduledoc """
  Converts a WordPress MySQL dump directly into a persistent DuckDB database
  file. No intermediate CSV files are created.

  Usage:
    mix ysc.wp_to_duckdb --sql wp_backup/backup.sql --db wp_backup/wp.duckdb

  Options:
    --sql            Path to the MySQL dump file (required)
    --db             Path to write the DuckDB file (default: wp_backup/wp.duckdb)
    --table-prefix   Table prefix in the dump (default: wp0h)
    --force          Overwrite existing DuckDB file if present
  """

  use Mix.Task

  @shortdoc "Load WP MySQL dump directly into a DuckDB file"

  @switches [
    sql: :string,
    db: :string,
    table_prefix: :string,
    force: :boolean
  ]

  @dialyzer {:nowarn_function, run: 1}
  def run(args) do
    {opts, _, _} = OptionParser.parse(List.wrap(args), strict: @switches)

    sql_path = opts[:sql]
    db_path = opts[:db] || "wp_backup/wp.duckdb"
    table_prefix = opts[:table_prefix] || "wp0h"
    force = opts[:force] || false

    if is_nil(sql_path) or sql_path == "" do
      Mix.raise("""
      Missing --sql. Provide the path to the MySQL dump.

      Example:
        mix ysc.wp_to_duckdb --sql wp_backup/backup.sql --db wp_backup/wp.duckdb
      """)
    end

    sql_path = Path.expand(sql_path)
    db_path = Path.expand(db_path)

    Mix.shell().info(
      "Loading #{sql_path} → #{db_path} (prefix: #{table_prefix})"
    )

    Mix.shell().info("This may take a minute for large dumps…")

    start = System.monotonic_time(:millisecond)

    case Ysc.WpMigration.SqlToDuckdb.run(sql_path, db_path,
           table_prefix: table_prefix,
           force: force
         ) do
      {:ok, counts} ->
        elapsed = System.monotonic_time(:millisecond) - start
        summary = Enum.map_join(counts, ", ", fn {t, n} -> "#{t}=#{n}" end)
        Mix.shell().info("Done in #{elapsed}ms — #{summary}")
        Mix.shell().info("DuckDB file: #{db_path}")

      {:error, reason} ->
        Mix.raise("Failed: #{inspect(reason)}")
    end
  end
end
