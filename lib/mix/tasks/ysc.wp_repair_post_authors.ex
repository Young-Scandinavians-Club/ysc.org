defmodule Mix.Tasks.Ysc.WpRepairPostAuthors do
  @moduledoc """
  Repairs author assignments on WordPress-migrated news posts.

  Reads `posts.json` and `users.json` from the export directory, resolves each
  post's `wp_author_id` to an app user (by email, with optional overrides), and
  updates `posts.user_id`.

  Usage:
    mix ysc.wp_repair_post_authors --export-dir wp_migration_export
    mix ysc.wp_repair_post_authors --export-dir wp_migration_export --dry-run
    mix ysc.wp_repair_post_authors --export-dir wp_migration_export --author-override 187:01KXKFZCXKW85KGK2TB9KZQKN1
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Repair WP-migrated news post authors"

  @switches [
    export_dir: :string,
    dry_run: :boolean,
    author_override: :keep
  ]

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, strict: @switches, aliases: [e: :export_dir])

    export_dir = opts[:export_dir]
    dry_run = opts[:dry_run] || false
    author_overrides = parse_author_overrides(opts[:author_override] || [])

    if is_nil(export_dir) or export_dir == "" do
      Mix.raise("""
      Missing --export-dir. Provide the path to the export directory from Phase 1.

      Example:
        mix ysc.wp_repair_post_authors --export-dir wp_migration_export
        mix ysc.wp_repair_post_authors --export-dir wp_migration_export --dry-run
      """)
    end

    Ysc.Logging.info("Starting WP post author repair",
      export_dir: export_dir,
      dry_run: dry_run,
      author_overrides: map_size(author_overrides)
    )

    case Ysc.WpMigration.Load.repair_post_authors(export_dir,
           dry_run: dry_run,
           author_overrides: author_overrides
         ) do
      {:ok, stats} ->
        IO.puts(
          "Post author repair complete. updated=#{stats.updated} unchanged=#{stats.unchanged} skipped=#{stats.skipped} failed=#{stats.failed}"
        )

      {:error, message} ->
        Mix.raise("Post author repair failed: #{message}")
    end
  end

  defp parse_author_overrides([]), do: %{}

  defp parse_author_overrides(pair) when is_binary(pair) do
    parse_author_overrides([pair])
  end

  defp parse_author_overrides(pairs) when is_list(pairs) do
    Map.new(pairs, fn pair ->
      case String.split(pair, ":", parts: 2) do
        [wp_author_id, user_id] ->
          {wp_author_id, user_id}

        _ ->
          Mix.raise(
            "Invalid --author-override #{inspect(pair)}; expected wp_author_id:user_id"
          )
      end
    end)
  end
end
