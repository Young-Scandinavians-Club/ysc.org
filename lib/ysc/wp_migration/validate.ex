defmodule Ysc.WpMigration.Validate do
  @compile {:no_warn_undefined, Duckdbex}
  @moduledoc """
  Validates migration data counts across two phases:

  1. Source counts — queried directly from DuckDB (the CSV files produced by
     `mix ysc.wp_sql_to_csv`).

  2. Export counts (optional) — counted from the intermediary export directory
     produced by `mix ysc.wp_extract`.

  Run standalone after Step 1, or after Step 2 to compare both.
  """

  alias Ysc.WpMigration.WpRepo

  @prefix "wp0h"

  @doc """
  Run validation. Options:
  - :db         - path to the DuckDB file (required)
  - :export_dir - path to intermediary export directory (optional; enables Phase 2 comparison)

  Prints a report and returns :ok if all counts match, {:warn, mismatches} if not.
  """
  def run(opts \\ []) do
    db = opts[:db]
    export_dir = opts[:export_dir]

    if is_nil(db) or db == "" do
      {:error, "Missing :db"}
    else
      case WpRepo.open(db) do
        {:ok, repo} ->
          source = gather_source_counts(repo)
          WpRepo.close(repo)

          export =
            if export_dir && File.dir?(Path.expand(export_dir)) do
              gather_export_counts(Path.expand(export_dir))
            else
              nil
            end

          print_report(source, export)

        {:error, reason} ->
          {:error, "Failed to open WpRepo: #{inspect(reason)}"}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Source counts from DuckDB
  # ---------------------------------------------------------------------------

  defp gather_source_counts(%WpRepo{
         conn: conn,
         hpos: hpos,
         wc_order_stats: has_order_stats
       }) do
    # Stripe WooCommerce plugin stores the customer ID on the user in usermeta.
    # The meta key is either `_stripe_customer_id` or `{prefix}__stripe_customer_id`
    # depending on the WooCommerce version and site prefix.
    stripe_in_usermeta =
      count(
        conn,
        "SELECT COUNT(DISTINCT user_id) FROM #{@prefix}_usermeta WHERE (meta_key = '_stripe_customer_id' OR meta_key LIKE '%_stripe_customer_id') AND meta_value IS NOT NULL AND meta_value != '' AND meta_value LIKE 'cus_%'"
      )

    orders_total =
      cond do
        hpos ->
          count(
            conn,
            "SELECT COUNT(*) FROM #{@prefix}_wc_orders WHERE type = 'shop_order'"
          )

        has_order_stats ->
          count(conn, "SELECT COUNT(*) FROM #{@prefix}_wc_order_stats")

        true ->
          count(
            conn,
            "SELECT COUNT(*) FROM #{@prefix}_posts WHERE post_type = 'shop_order'"
          )
      end

    %{
      hpos: hpos,
      users_total: count(conn, "SELECT COUNT(*) FROM #{@prefix}_users"),
      users_with_email:
        count(
          conn,
          "SELECT COUNT(*) FROM #{@prefix}_users WHERE user_email != ''"
        ),
      users_with_membership:
        count(
          conn,
          "SELECT COUNT(DISTINCT user_id) FROM #{@prefix}_usermeta WHERE meta_key = 'membership_type' AND meta_value != ''"
        ),
      users_with_address:
        count(
          conn,
          "SELECT COUNT(DISTINCT user_id) FROM #{@prefix}_usermeta WHERE meta_key = 'Country' AND meta_value != ''"
        ),
      users_with_application:
        count(
          conn,
          "SELECT COUNT(DISTINCT user_id) FROM #{@prefix}_usermeta WHERE meta_key = 'submitted' AND meta_value != ''"
        ),
      users_with_stripe: stripe_in_usermeta,
      orders_total: orders_total,
      published_posts:
        count(
          conn,
          """
          SELECT COUNT(*) FROM #{@prefix}_posts
          WHERE post_type = 'post'
            AND (
              post_status = 'publish'
              OR (post_status = 'future' AND post_date <= '#{migration_now()}')
            )
          """
        ),
      attachments:
        count(
          conn,
          "SELECT COUNT(*) FROM #{@prefix}_posts WHERE post_type = 'attachment'"
        ),
      future_mphb_bookings:
        count(
          conn,
          "SELECT COUNT(*) FROM #{@prefix}_posts p " <>
            "JOIN #{@prefix}_postmeta pm ON pm.post_id = p.ID AND pm.meta_key = 'mphb_check_in_date' " <>
            "WHERE p.post_type = 'mphb_booking' AND p.post_status = 'confirmed' " <>
            "AND pm.meta_value > '2025-03-08'"
        ),
      usermeta_rows: count(conn, "SELECT COUNT(*) FROM #{@prefix}_usermeta"),
      postmeta_rows: count(conn, "SELECT COUNT(*) FROM #{@prefix}_postmeta"),
      membership_types: membership_type_breakdown(conn)
    }
  end

  defp membership_type_breakdown(conn) do
    case run_query(conn, """
           SELECT meta_value AS type, COUNT(DISTINCT user_id) AS cnt
           FROM #{@prefix}_usermeta
           WHERE meta_key = 'membership_type' AND meta_value != ''
           GROUP BY meta_value
           ORDER BY cnt DESC
         """) do
      {:ok, rows} -> rows
      _ -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Export counts from JSON + media dir
  # ---------------------------------------------------------------------------

  defp gather_export_counts(dir) do
    users = count_json(Path.join(dir, "users.json"))
    applications = count_json(Path.join(dir, "applications.json"))
    posts = count_json(Path.join(dir, "posts.json"))
    bookings = count_json(Path.join(dir, "bookings.json"))

    stripe_lookup =
      count_json_with(Path.join(dir, "stripe_customer_lookup.json"), fn row ->
        row["stripe_customer_id"] not in [nil, ""]
      end)

    media_dir = Path.join(dir, "media")

    media_subdirs =
      if File.dir?(media_dir) do
        media_dir
        |> File.ls!()
        |> Enum.count(&File.dir?(Path.join(media_dir, &1)))
      else
        :missing
      end

    %{
      users: users,
      applications: applications,
      posts: posts,
      bookings: bookings,
      stripe_customers: stripe_lookup,
      media_subdirs: media_subdirs
    }
  end

  defp count_json(path) do
    if File.exists?(path) do
      path |> File.read!() |> Jason.decode!() |> length()
    else
      :missing
    end
  end

  defp count_json_with(path, filter_fn) do
    if File.exists?(path) do
      path |> File.read!() |> Jason.decode!() |> Enum.count(filter_fn)
    else
      :missing
    end
  end

  # ---------------------------------------------------------------------------
  # Report
  # ---------------------------------------------------------------------------

  defp print_report(source, export) do
    IO.puts("")
    IO.puts("╔════════════════════════════════════════════════════════╗")
    IO.puts("║         WordPress Migration – Validation Report        ║")
    IO.puts("╠════════════════════════════════════════════════════════╣")

    orders_label =
      if source.hpos,
        do: "  SOURCE (DuckDB / CSV — HPOS orders)",
        else: "  SOURCE (DuckDB / CSV)"

    IO.puts("║#{orders_label}")
    IO.puts("╠════════════════════════════════════════════════════════╣")

    print_row("Users total", source.users_total)
    print_row("Users with email", source.users_with_email)
    print_row("Users with membership type", source.users_with_membership)
    print_row("Users with address", source.users_with_address)

    print_row(
      "Users with application (submitted)",
      source.users_with_application
    )

    print_row("Users with Stripe customer", source.users_with_stripe)
    print_row("Orders total", source.orders_total)

    print_row(
      "Published posts (incl. past-due scheduled)",
      source.published_posts
    )

    print_row("Attachments (in wp_posts)", source.attachments)
    print_row("Future bookings (mphb confirmed)", source.future_mphb_bookings)
    print_row("Usermeta rows", source.usermeta_rows)
    print_row("Postmeta rows", source.postmeta_rows)

    if source.membership_types != [] do
      IO.puts("║")
      IO.puts("║  Membership type breakdown:")

      Enum.each(source.membership_types, fn [type, cnt] ->
        print_row("    #{type}", cnt)
      end)
    end

    mismatches =
      if export do
        IO.puts("╠════════════════════════════════════════════════════════╣")
        IO.puts("║  EXPORT vs SOURCE comparison")
        IO.puts("╠════════════════════════════════════════════════════════╣")

        mismatches =
          [
            compare_row("users.json", export.users, source.users_total),
            compare_row(
              "applications.json",
              export.applications,
              source.users_total
            ),
            compare_row("posts.json", export.posts, source.published_posts),
            compare_row(
              "bookings.json",
              export.bookings,
              source.future_mphb_bookings
            ),
            compare_row(
              "stripe_customer_lookup (with ID)",
              export.stripe_customers,
              source.users_with_stripe
            ),
            compare_row(
              "media/ subdirs",
              export.media_subdirs,
              source.attachments
            )
          ]
          |> Enum.reject(&is_nil/1)

        mismatches
      else
        IO.puts("╠════════════════════════════════════════════════════════╣")
        IO.puts("║  (no export dir provided — skipping Phase 2 comparison)")
        []
      end

    IO.puts("╚════════════════════════════════════════════════════════╝")

    if mismatches == [] do
      if export, do: IO.puts("\n✓ All export counts match source.")
      :ok
    else
      IO.puts("\n⚠  #{length(mismatches)} mismatch(es) found (see above).")
      {:warn, mismatches}
    end
  end

  defp print_row(label, :missing) do
    IO.puts("║  #{String.pad_trailing(label, 38)} MISSING")
  end

  defp print_row(label, value) do
    IO.puts("║  #{String.pad_trailing(label, 38)} #{format_count(value)}")
  end

  defp compare_row(label, export_count, source_count) do
    {status, mismatch} =
      cond do
        export_count == :missing ->
          {"  MISSING       ", {label, :missing, source_count}}

        export_count == source_count ->
          {"✓ #{format_count(export_count)}", nil}

        true ->
          diff = export_count - source_count
          sign = if diff > 0, do: "+", else: ""

          {"⚠ #{format_count(export_count)} (#{sign}#{diff} vs src #{format_count(source_count)})",
           {label, export_count, source_count}}
      end

    IO.puts("║  #{String.pad_trailing(label, 38)} #{status}")
    mismatch
  end

  defp format_count(n) when is_integer(n),
    do: Integer.to_string(n) |> String.pad_leading(6)

  defp format_count(v), do: inspect(v)

  # ---------------------------------------------------------------------------
  # DuckDB helpers
  # ---------------------------------------------------------------------------

  defp count(conn, sql) do
    case run_query(conn, sql) do
      {:ok, [[n | _] | _]} -> parse_int(n)
      _ -> 0
    end
  end

  defp run_query(conn, sql) do
    case Duckdbex.query(conn, sql) do
      {:ok, r} -> {:ok, Duckdbex.fetch_all(r)}
      err -> err
    end
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
  defp parse_int(_), do: 0

  defp migration_now do
    DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end
end
