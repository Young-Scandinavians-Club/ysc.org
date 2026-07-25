defmodule Mix.Tasks.Ysc.WpReconcileCsvs do
  @moduledoc """
  Cross-check a WordPress migration export against manual admin CSV exports.

  Usage:
    mix ysc.wp_reconcile_csvs --export-dir wp_migration_export --csv-dir wp_export_csvs
  """

  use Mix.Task

  @shortdoc "Reconcile WP export JSON against wp_export_csvs"

  @switches [
    export_dir: :string,
    csv_dir: :string
  ]

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: @switches,
        aliases: [e: :export_dir, c: :csv_dir]
      )

    export_dir = opts[:export_dir]
    csv_dir = opts[:csv_dir] || "wp_export_csvs"

    if is_nil(export_dir) or export_dir == "" do
      Mix.raise("""
      Missing --export-dir.

      Example:
        mix ysc.wp_reconcile_csvs --export-dir wp_migration_export --csv-dir wp_export_csvs
      """)
    end

    case Ysc.WpMigration.ReconcileCsvs.run(
           export_dir: export_dir,
           csv_dir: csv_dir
         ) do
      {:ok, _report} ->
        :ok

      {:error, reason} ->
        Mix.raise("Reconcile failed: #{reason}")
    end
  end
end
