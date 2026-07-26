defmodule Mix.Tasks.Ysc.WpImportNewsletterCsv do
  @moduledoc """
  Import Mailchimp/Emailable newsletter subscribers from a CSV export.

  Usage:
    mix ysc.wp_import_newsletter_csv --csv wp_export_csvs/newsletter_emails.csv
    mix ysc.wp_import_newsletter_csv --csv wp_export_csvs/newsletter_emails.csv --dry-run
  """

  use Mix.Task

  @shortdoc "Import newsletter subscribers from WP/Mailchimp CSV"

  @switches [
    csv: :string,
    dry_run: :boolean
  ]

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: @switches,
        aliases: [c: :csv]
      )

    csv = opts[:csv]

    if is_nil(csv) or csv == "" do
      Mix.raise("""
      Missing --csv.

      Example:
        mix ysc.wp_import_newsletter_csv --csv wp_export_csvs/newsletter_emails.csv
      """)
    end

    case Ysc.WpMigration.NewsletterCsvImport.run(csv,
           dry_run: Keyword.get(opts, :dry_run, false)
         ) do
      {:ok, stats} ->
        Mix.shell().info("""
        Newsletter CSV import finished:
          created=#{stats.created}
          updated=#{stats.updated}
          unchanged=#{stats.unchanged}
          skipped=#{stats.skipped}
          failed=#{stats.failed}
        """)

        :ok

      {:error, reason} ->
        Mix.raise("Newsletter CSV import failed: #{reason}")
    end
  end
end
