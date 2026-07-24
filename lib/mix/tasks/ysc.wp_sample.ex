defmodule Mix.Tasks.Ysc.WpSample do
  @compile {:no_warn_undefined, Duckdbex}
  @moduledoc """
  Prints sample rows from each migration entity for visual validation.

  Usage:
    mix ysc.wp_sample --db wp_backup/wp.duckdb
    mix ysc.wp_sample --db wp_backup/wp.duckdb --limit 10

  Options:
    --db      Path to the DuckDB file (default: wp_backup/wp.duckdb)
    --limit   Rows to show per entity (default: 5)
  """

  use Mix.Task

  @shortdoc "Print sample data from all WP migration entities"

  @prefix "wp0h"
  @switches [db: :string, limit: :integer]

  def run(args) do
    {opts, _, _} = OptionParser.parse(List.wrap(args), strict: @switches)

    db_path = Path.expand(opts[:db] || "wp_backup/wp.duckdb")
    limit = opts[:limit] || 5

    if !File.exists?(db_path) do
      Mix.raise(
        "DuckDB file not found: #{db_path}\nRun: mix ysc.wp_to_duckdb --sql wp_backup/backup.sql"
      )
    end

    {:ok, db} = Duckdbex.open(db_path)
    {:ok, conn} = Duckdbex.connection(db)

    IO.puts("")
    IO.puts("DuckDB: #{db_path}")
    IO.puts(String.duplicate("═", 72))

    section(conn, "USERS", limit, """
      SELECT
        u.ID,
        u.user_login,
        u.user_email,
        LEFT(u.user_registered, 10) AS registered,
        u.display_name
      FROM #{@prefix}_users u
      ORDER BY CAST(u.ID AS BIGINT)
      LIMIT #{limit}
    """)

    section(conn, "MEMBERS (by membership_type)", limit, """
      SELECT
        u.user_email,
        CASE
          WHEN m.meta_value LIKE '%single%' THEN 'single'
          WHEN m.meta_value LIKE '%family%' THEN 'family'
          ELSE m.meta_value
        END AS membership_type,
        m.meta_value AS raw_value
      FROM #{@prefix}_users u
      JOIN #{@prefix}_usermeta m
        ON m.user_id = u.ID AND m.meta_key = 'membership_type'
      WHERE m.meta_value IS NOT NULL AND m.meta_value != ''
      ORDER BY CAST(u.ID AS BIGINT)
      LIMIT #{limit}
    """)

    section(conn, "APPLICATIONS (submitted)", limit, """
      SELECT
        u.user_email,
        LEFT(sub.meta_value, 40) AS submitted_value,
        mem.meta_value AS membership_type,
        addr.meta_value AS country
      FROM #{@prefix}_users u
      JOIN #{@prefix}_usermeta sub
        ON sub.user_id = u.ID AND sub.meta_key = 'submitted'
      LEFT JOIN #{@prefix}_usermeta mem
        ON mem.user_id = u.ID AND mem.meta_key = 'membership_type'
      LEFT JOIN #{@prefix}_usermeta addr
        ON addr.user_id = u.ID AND addr.meta_key = 'Country'
      ORDER BY CAST(u.ID AS BIGINT)
      LIMIT #{limit}
    """)

    section(conn, "STRIPE CUSTOMERS", limit, """
      SELECT
        u.user_email,
        cus.meta_value AS stripe_customer_id,
        src.meta_value AS stripe_source_id
      FROM #{@prefix}_users u
      JOIN #{@prefix}_usermeta cus
        ON cus.user_id = u.ID
       AND cus.meta_key LIKE '%_stripe_customer_id'
       AND cus.meta_value LIKE 'cus_%'
      LEFT JOIN #{@prefix}_usermeta src
        ON src.user_id = u.ID
       AND src.meta_key LIKE '%_stripe_source_id'
      ORDER BY CAST(u.ID AS BIGINT)
      LIMIT #{limit}
    """)

    section(conn, "PUBLISHED POSTS", limit, """
      SELECT
        p.ID,
        LEFT(p.post_date, 10) AS date,
        p.post_title,
        u.user_email AS author_email,
        (
          SELECT COUNT(*)
          FROM #{@prefix}_postmeta pm
          WHERE pm.post_id = p.ID AND pm.meta_key = '_thumbnail_id'
        ) AS has_thumbnail
      FROM #{@prefix}_posts p
      LEFT JOIN #{@prefix}_users u ON u.ID = p.post_author
      WHERE p.post_type = 'post' AND p.post_status = 'publish'
      ORDER BY p.post_date DESC
      LIMIT #{limit}
    """)

    section(conn, "ATTACHMENTS (media files)", limit, """
      SELECT
        p.ID,
        p.post_title,
        p.post_mime_type,
        m.meta_value AS file_path
      FROM #{@prefix}_posts p
      LEFT JOIN #{@prefix}_postmeta m
        ON m.post_id = p.ID AND m.meta_key = '_wp_attached_file'
      WHERE p.post_type = 'attachment'
      ORDER BY CAST(p.ID AS BIGINT) DESC
      LIMIT #{limit}
    """)

    if order_stats_present?(conn) do
      section(conn, "ORDERS (wc_order_stats)", limit, """
        SELECT
          s.order_id,
          LEFT(s.date_created, 10) AS date,
          s.status,
          s.total_sales AS total,
          s.customer_id
        FROM #{@prefix}_wc_order_stats s
        ORDER BY CAST(s.order_id AS BIGINT) DESC
        LIMIT #{limit}
      """)
    end

    IO.puts(String.duplicate("═", 72))

    IO.puts(
      "Done. Run `mix ysc.wp_validate --csv-dir #{db_path}` for full counts.\n"
    )

    Duckdbex.release(conn)
  end

  # ---------------------------------------------------------------------------

  defp section(conn, title, _limit, sql) do
    IO.puts("\n┌─ #{title}")

    case query(conn, sql) do
      {:ok, cols, rows} when rows != [] ->
        print_table(cols, rows)

      {:ok, _, []} ->
        IO.puts("│  (no rows)")

      {:error, reason} ->
        IO.puts("│  ERROR: #{inspect(reason)}")
    end
  end

  defp query(conn, sql) do
    case Duckdbex.query(conn, sql) do
      {:ok, r} ->
        cols = Duckdbex.columns(r)
        rows = Duckdbex.fetch_all(r)
        {:ok, cols, rows}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp print_table(cols, rows) do
    rows_str = Enum.map(rows, fn row -> Enum.map(row, &cell/1) end)
    widths = col_widths(cols, rows_str)

    header =
      cols
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {c, w} -> String.pad_trailing(c, w) end)

    divider =
      widths |> Enum.map_join("  ", fn w -> String.duplicate("─", w) end)

    IO.puts("│  " <> header)
    IO.puts("│  " <> divider)

    Enum.each(rows_str, fn row ->
      line =
        row
        |> Enum.zip(widths)
        |> Enum.map_join("  ", fn {v, w} -> String.pad_trailing(v, w) end)

      IO.puts("│  " <> line)
    end)
  end

  defp col_widths(cols, rows) do
    n = length(cols)

    Enum.map(0..(n - 1), fn i ->
      header_w = Enum.at(cols, i) |> String.length()

      max_data_w =
        Enum.reduce(rows, 0, fn row, acc ->
          max(acc, String.length(Enum.at(row, i) || ""))
        end)

      min(max(header_w, max_data_w), 48)
    end)
  end

  defp cell(nil), do: "NULL"
  defp cell(v) when is_binary(v), do: truncate(v, 48)
  defp cell(v), do: truncate(to_string(v), 48)

  defp truncate(s, max) do
    clean = s |> String.replace(["\n", "\r", "\t"], " ") |> String.trim()

    if String.length(clean) > max,
      do: String.slice(clean, 0, max - 1) <> "…",
      else: clean
  end

  defp order_stats_present?(conn) do
    case Duckdbex.query(conn, "SELECT COUNT(*) FROM #{@prefix}_wc_order_stats") do
      {:ok, r} ->
        case Duckdbex.fetch_all(r) do
          [[n]] -> parse_int(n) > 0
          _ -> false
        end

      _ ->
        false
    end
  end

  defp parse_int(n) when is_integer(n), do: n
  defp parse_int(n) when is_binary(n), do: String.to_integer(n)
  defp parse_int(_), do: 0
end
