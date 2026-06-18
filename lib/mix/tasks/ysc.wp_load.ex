defmodule Mix.Tasks.Ysc.WpLoad do
  @moduledoc """
  Phase 2: Load the WordPress migration export into the app database.

  Reads the export directory produced by `mix ysc.wp_extract` (users.json,
  applications.json, posts.json, media/, stripe_customer_lookup.json) and
  inserts users, applications, media (upload to S3 + Image records), posts,
  and Stripe customer IDs.

  Usage:
    mix ysc.wp_load --export-dir wp_migration_export [--dry-run] [--no-upload-media] [--create-stripe-subscriptions]

  Options:
    --create-stripe-subscriptions  Creates real Stripe customers and subscriptions in the
                                   connected Stripe account (sandbox/dev). Each subscription
                                   is created with trial_end set to the WP renewal date so
                                   no immediate charge fires. Useful for local testing.
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Load WP migration export into database"

  @switches [
    export_dir: :string,
    dry_run: :boolean,
    no_upload_media: :boolean,
    create_stripe_subscriptions: :boolean
  ]

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, strict: @switches, aliases: [e: :export_dir])

    export_dir = opts[:export_dir]
    dry_run = opts[:dry_run] || false
    upload_media = not (opts[:no_upload_media] || false)
    create_stripe_subscriptions = opts[:create_stripe_subscriptions] || false

    if is_nil(export_dir) or export_dir == "" do
      Mix.raise("""
      Missing --export-dir. Provide the path to the export directory from Phase 1 (mix ysc.wp_extract).

      Example:
        mix ysc.wp_load --export-dir wp_migration_export
        mix ysc.wp_load --export-dir wp_migration_export --dry-run
        mix ysc.wp_load --export-dir wp_migration_export --no-upload-media
        mix ysc.wp_load --export-dir wp_migration_export --create-stripe-subscriptions
      """)
    end

    Ysc.Logging.info("Starting WP load",
      export_dir: export_dir,
      dry_run: dry_run,
      upload_media: upload_media,
      create_stripe_subscriptions: create_stripe_subscriptions
    )

    case Ysc.WpMigration.Load.run(
           export_dir: export_dir,
           dry_run: dry_run,
           upload_media: upload_media,
           create_stripe_subscriptions: create_stripe_subscriptions
         ) do
      {:ok, result} ->
        if dry_run do
          IO.puts("Dry run complete. No changes written.")
        else
          IO.puts("Load complete.")

          if map_size(result) > 0 do
            IO.puts("  user_map: #{map_size(result[:user_map] || %{})} users")

            IO.puts(
              "  image_map: #{map_size(result[:image_map] || %{})} images"
            )

            case result[:stripe_import_report] do
              %{failures: failures} when is_list(failures) ->
                count = length(failures)

                if count > 0 do
                  IO.puts("  stripe_import_failures: #{count}")

                  IO.puts(
                    "  stripe_import_failures_path: #{result[:stripe_import_failures_path]}"
                  )
                end

              _ ->
                :ok
            end
          end
        end

      {:error, message} ->
        Mix.raise("Load failed: #{message}")
    end
  end
end
