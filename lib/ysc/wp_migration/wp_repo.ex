defmodule Ysc.WpMigration.WpRepo do
  @compile {:no_warn_undefined, Duckdbex}
  @moduledoc """
  Read-only access to WordPress backup data via DuckDB.

  ## Fast path — persistent DuckDB file (recommended)

  After running `mix ysc.wp_to_duckdb --sql backup.sql --db wp_backup/wp.duckdb`,
  open it directly:

      WpRepo.open("wp_backup/wp.duckdb")

  The file is opened instantly; DuckDB handles its own paging so the memory
  footprint stays low regardless of database size.

  ## Legacy path — in-memory load from CSV directory

  If you have CSV files from `mix ysc.wp_sql_to_csv`, pass the directory:

      WpRepo.open("wp_backup/csv")

  The CSVs are loaded into an ephemeral in-memory DuckDB instance on each call.
  """

  @table_prefix "wp0h"
  @required_tables ["users", "usermeta", "posts", "postmeta"]
  @optional_tables ["wc_orders", "wc_orders_meta", "wc_order_stats"]

  defstruct [:conn, hpos: false, wc_order_stats: false]

  @doc """
  Opens a WpRepo from either a `.duckdb` file or a CSV directory.
  Returns `{:ok, %WpRepo{}}` or `{:error, reason}`.
  """
  def open(path) when is_binary(path) do
    expanded = Path.expand(path)

    if String.ends_with?(expanded, ".duckdb") or File.regular?(expanded) do
      open_duckdb_file(expanded)
    else
      open_csv_dir(expanded)
    end
  end

  # Open a pre-built persistent DuckDB file — zero parsing, instant.
  defp open_duckdb_file(db_path) do
    if File.exists?(db_path) do
      with {:ok, db} <- Duckdbex.open(db_path),
           {:ok, conn} <- Duckdbex.connection(db) do
        hpos = table_exists?(conn, "#{@table_prefix}_wc_orders")
        has_order_stats = table_exists?(conn, "#{@table_prefix}_wc_order_stats")

        {:ok,
         %__MODULE__{conn: conn, hpos: hpos, wc_order_stats: has_order_stats}}
      end
    else
      {:error, "DuckDB file not found: #{db_path}"}
    end
  end

  # Legacy: load CSVs into an ephemeral in-memory DuckDB instance.
  defp open_csv_dir(dir) do
    missing =
      Enum.reject(@required_tables, fn table ->
        File.exists?(Path.join(dir, "#{@table_prefix}_#{table}.csv"))
      end)

    if missing != [] do
      {:error,
       {:missing_csv, Path.join(dir, "#{@table_prefix}_#{hd(missing)}.csv")}}
    else
      with {:ok, db} <- Duckdbex.open(),
           {:ok, conn} <- Duckdbex.connection(db) do
        present_optional =
          Enum.filter(@optional_tables, fn table ->
            File.exists?(Path.join(dir, "#{@table_prefix}_#{table}.csv"))
          end)

        errors =
          Enum.flat_map(@required_tables ++ present_optional, fn table ->
            csv_path = Path.join(dir, "#{@table_prefix}_#{table}.csv")
            escaped = String.replace(csv_path, "'", "''")

            sql =
              "CREATE TABLE #{@table_prefix}_#{table} AS SELECT * FROM read_csv_auto('#{escaped}', header=true, all_varchar=true)"

            case Duckdbex.query(conn, sql) do
              {:ok, _} -> []
              {:error, reason} -> [{table, reason}]
            end
          end)

        if errors != [] do
          {:error, {:load_failed, errors}}
        else
          hpos = "wc_orders" in present_optional
          has_order_stats = "wc_order_stats" in present_optional

          {:ok,
           %__MODULE__{conn: conn, hpos: hpos, wc_order_stats: has_order_stats}}
        end
      end
    end
  end

  defp table_exists?(conn, table_name) do
    case Duckdbex.query(conn, "SELECT COUNT(*) FROM #{table_name}") do
      {:ok, r} ->
        case Duckdbex.fetch_all(r) do
          [[n]] -> parse_count(n) > 0
          _ -> false
        end

      _ ->
        false
    end
  end

  defp parse_count(n) when is_integer(n), do: n
  defp parse_count(n) when is_binary(n), do: String.to_integer(n)
  defp parse_count(_), do: 0

  @doc "Releases the DuckDB connection."
  def close(%__MODULE__{conn: conn}) do
    Duckdbex.release(conn)
    :ok
  end

  @doc "Returns all user rows as a list of string-keyed maps."
  def list_users(%__MODULE__{conn: conn}) do
    {:ok, rows} = query_maps(conn, "SELECT * FROM #{@table_prefix}_users")
    rows
  end

  @doc "Returns usermeta for user_id as %{meta_key => meta_value}."
  def get_usermeta(%__MODULE__{conn: conn}, user_id) do
    {:ok, rows} =
      query_maps(
        conn,
        "SELECT meta_key, meta_value FROM #{@table_prefix}_usermeta WHERE user_id = $1",
        [
          to_string(user_id)
        ]
      )

    Map.new(rows, fn row -> {row["meta_key"], row["meta_value"]} end)
  end

  @doc """
  Returns published posts sorted descending by post_date.

  Includes both `publish` posts and any `future` (scheduled) posts whose
  `post_date` has already passed. The latter occurs when a WP backup is taken
  while posts are still in the scheduler queue — by migration time those posts
  should be live, and excluding them would silently drop content.
  """
  def list_published_posts(%__MODULE__{conn: conn}) do
    {:ok, rows} =
      query_maps(
        conn,
        """
        SELECT * FROM #{@table_prefix}_posts
        WHERE post_type = 'post'
          AND (
            post_status = 'publish'
            OR (post_status = 'future' AND CAST(post_date AS TIMESTAMP) <= CURRENT_TIMESTAMP)
          )
        ORDER BY post_date DESC
        """
      )

    rows
  end

  @doc "Returns all attachment post rows."
  def list_attachments(%__MODULE__{conn: conn}) do
    {:ok, rows} =
      query_maps(
        conn,
        "SELECT ID, post_title, post_mime_type FROM #{@table_prefix}_posts WHERE post_type = 'attachment' ORDER BY CAST(ID AS BIGINT)"
      )

    rows
  end

  @doc """
  Returns future confirmed MotoPress (mphb_booking) reservations.

  Each item is a map with booking meta keys (mphb_check_in_date, mphb_check_out_date,
  mphb_customer_id, mphb_first_name, mphb_last_name, mphb_email, mphb_total_price, etc.)
  and a "reserved_rooms" list of %{"wp_room_id" => _, "room_name" => _, "adults" => _, "children" => _}.
  Check-in date cutoff is 2025-03-08; only post_status = 'confirmed' is included.
  """
  def list_future_mphb_bookings(%__MODULE__{conn: conn}) do
    cutoff = "2025-03-08"

    ids_sql = """
    SELECT p.ID
    FROM #{@table_prefix}_posts p
    JOIN #{@table_prefix}_postmeta pm ON pm.post_id = p.ID AND pm.meta_key = 'mphb_check_in_date'
    WHERE p.post_type = 'mphb_booking' AND p.post_status = 'confirmed'
      AND pm.meta_value > $1
    ORDER BY pm.meta_value
    """

    case query_maps(conn, ids_sql, [cutoff]) do
      {:ok, id_rows} ->
        ids = Enum.map(id_rows, fn r -> r["ID"] end)

        if ids == [] do
          []
        else
          meta_by_id = fetch_mphb_booking_meta(conn, ids)
          rooms_by_id = fetch_mphb_reserved_rooms(conn, ids)
          build_mphb_booking_list(id_rows, meta_by_id, rooms_by_id)
        end

      _ ->
        []
    end
  end

  defp fetch_mphb_booking_meta(conn, booking_ids) do
    # DuckDB IN with a list: build placeholders
    placeholders =
      booking_ids
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {_id, i} -> "$#{i}" end)

    sql = """
    SELECT post_id, meta_key, meta_value
    FROM #{@table_prefix}_postmeta
    WHERE post_id IN (#{placeholders})
    """

    case query_maps(conn, sql, Enum.map(booking_ids, &to_string/1)) do
      {:ok, rows} ->
        rows
        |> Enum.group_by(fn r -> r["post_id"] end, fn r ->
          {r["meta_key"], r["meta_value"]}
        end)
        |> Map.new(fn {post_id, kvs} -> {post_id, Map.new(kvs)} end)

      _ ->
        %{}
    end
  end

  defp fetch_mphb_reserved_rooms(conn, booking_ids) do
    placeholders =
      booking_ids
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {_id, i} -> "$#{i}" end)

    sql = """
    SELECT
      rr.post_parent AS booking_id,
      pm_room.meta_value AS wp_room_id,
      r.post_title AS room_name,
      pm_adults.meta_value AS adults,
      pm_children.meta_value AS children
    FROM #{@table_prefix}_posts rr
    JOIN #{@table_prefix}_postmeta pm_room ON pm_room.post_id = rr.ID AND pm_room.meta_key = '_mphb_room_id'
    LEFT JOIN #{@table_prefix}_posts r ON r.ID = pm_room.meta_value
    LEFT JOIN #{@table_prefix}_postmeta pm_adults ON pm_adults.post_id = rr.ID AND pm_adults.meta_key = '_mphb_adults'
    LEFT JOIN #{@table_prefix}_postmeta pm_children ON pm_children.post_id = rr.ID AND pm_children.meta_key = '_mphb_children'
    WHERE rr.post_type = 'mphb_reserved_room'
      AND rr.post_parent IN (#{placeholders})
    ORDER BY rr.post_parent, rr.ID
    """

    case query_maps(conn, sql, Enum.map(booking_ids, &to_string/1)) do
      {:ok, rows} ->
        rows
        |> Enum.group_by(fn r -> r["booking_id"] end, fn r ->
          %{
            "wp_room_id" => r["wp_room_id"],
            "room_name" => r["room_name"],
            "adults" => r["adults"],
            "children" => r["children"]
          }
        end)
        |> Map.new(fn {bid, list} -> {bid, list} end)

      _ ->
        %{}
    end
  end

  defp build_mphb_booking_list(id_rows, meta_by_id, rooms_by_id) do
    Enum.map(id_rows, fn row ->
      id = row["ID"]
      meta = Map.get(meta_by_id, id, %{})
      rooms = Map.get(rooms_by_id, id, [])
      Map.merge(meta, %{"ID" => id, "reserved_rooms" => rooms})
    end)
  end

  @doc "Returns postmeta for post_id as %{meta_key => meta_value}."
  def get_postmeta(%__MODULE__{conn: conn}, post_id) do
    {:ok, rows} =
      query_maps(
        conn,
        "SELECT meta_key, meta_value FROM #{@table_prefix}_postmeta WHERE post_id = $1",
        [
          to_string(post_id)
        ]
      )

    Map.new(rows, fn row -> {row["meta_key"], row["meta_value"]} end)
  end

  @doc """
  Returns Stripe customer info for the given WP user_id, or nil.

  Resolution order:
  1. `usermeta` — WooCommerce Stripe plugin writes `_stripe_customer_id` here.
  2. `woocommerce_payment_tokens` — stores the saved `pm_...` payment method IDs.
  3. HPOS `wc_orders`/`wc_orders_meta` or legacy `shop_order` postmeta as a
     last-resort fallback for sites that never saved tokens directly.

  Returns a map with `"stripe_customer_id"` and `"stripe_payment_method_id"`.
  """
  def get_stripe_customer_for_user(
        %__MODULE__{conn: conn, hpos: hpos} = _repo,
        user_id
      ) do
    uid_str = to_string(user_id)

    # Step 1 — customer ID from usermeta
    usermeta_sql = """
    SELECT
      MAX(CASE WHEN meta_key LIKE '%_stripe_customer_id' AND meta_value LIKE 'cus_%' THEN meta_value END) AS stripe_customer_id
    FROM #{@table_prefix}_usermeta
    WHERE user_id = $1
      AND meta_key LIKE '%_stripe_customer_id'
    """

    customer_id =
      case query_maps(conn, usermeta_sql, [uid_str]) do
        {:ok, [%{"stripe_customer_id" => cid} | _]}
        when is_binary(cid) and cid != "" ->
          cid

        _ ->
          nil
      end

    # Step 2 — default saved payment method from woocommerce_payment_tokens
    payment_method_id =
      case query_maps(
             conn,
             """
             SELECT token
             FROM #{@table_prefix}_woocommerce_payment_tokens
             WHERE user_id = $1
               AND gateway_id IN ('stripe', 'stripe_us_bank_account')
             ORDER BY CAST(is_default AS INTEGER) DESC, CAST(token_id AS BIGINT) DESC
             LIMIT 1
             """,
             [uid_str]
           ) do
        {:ok, [%{"token" => pm} | _]} when is_binary(pm) and pm != "" -> pm
        _ -> nil
      end

    cond do
      is_binary(customer_id) and customer_id != "" ->
        {:ok,
         %{
           "stripe_customer_id" => customer_id,
           "stripe_payment_method_id" => payment_method_id
         }}

      true ->
        # Step 3 — fall back to order history for the customer ID
        order_sql =
          if hpos do
            """
            SELECT m_cus.meta_value AS stripe_customer_id
            FROM #{@table_prefix}_wc_orders o
            JOIN #{@table_prefix}_wc_orders_meta m_cus
              ON m_cus.order_id = o.id AND m_cus.meta_key = '_stripe_customer_id'
            WHERE o.customer_id = $1
              AND o.payment_method = 'stripe'
              AND m_cus.meta_value IS NOT NULL
              AND m_cus.meta_value != ''
            ORDER BY o.date_created_gmt DESC
            LIMIT 1
            """
          else
            """
            SELECT pm_cus.meta_value AS stripe_customer_id
            FROM #{@table_prefix}_posts p
            JOIN #{@table_prefix}_postmeta pm_method
              ON pm_method.post_id = p.ID
             AND pm_method.meta_key = '_payment_method'
             AND pm_method.meta_value = 'stripe'
            JOIN #{@table_prefix}_postmeta pm_user
              ON pm_user.post_id = p.ID
             AND pm_user.meta_key = '_customer_user'
             AND pm_user.meta_value = $1
            LEFT JOIN #{@table_prefix}_postmeta pm_cus
              ON pm_cus.post_id = p.ID AND pm_cus.meta_key = '_stripe_customer_id'
            WHERE p.post_type = 'shop_order'
            ORDER BY p.post_date DESC
            LIMIT 1
            """
          end

        case query_maps(conn, order_sql, [uid_str]) do
          {:ok, [row | _]} ->
            {:ok,
             %{
               "stripe_customer_id" => row["stripe_customer_id"],
               "stripe_payment_method_id" => payment_method_id
             }}

          {:ok, []} ->
            {:ok, nil}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Returns membership and subscription info for the given WP user_id.

  Queries two sources and merges them:
  - `wc_user_membership`  — WooCommerce Memberships plugin (post_author = user_id)
  - `shop_subscription`   — WooCommerce Subscriptions billing records (_customer_user meta)

  Returns a map with:
    - `"wcm_status"`           — wcm-active | wcm-expired | wcm-cancelled | nil
    - `"wcm_start_date"`       — membership start datetime
    - `"wcm_end_date"`         — membership end datetime
    - `"sub_status"`           — wc-active | wc-expired | wc-on-hold | wc-cancelled | nil
    - `"sub_start_date"`       — subscription start datetime
    - `"sub_next_payment_date"` — next renewal datetime (nil if expired/cancelled)
    - `"sub_amount"`           — subscription amount (USD string)
    - `"sub_period"`           — billing period (e.g. "year")
  """
  def get_membership_for_user(%__MODULE__{conn: conn}, user_id) do
    uid_str = to_string(user_id)

    # wc_user_membership — most recent record for this user, prefer active
    wcm_sql = """
    SELECT
      p.post_status AS wcm_status,
      pm_start.meta_value AS wcm_start_date,
      pm_end.meta_value AS wcm_end_date
    FROM #{@table_prefix}_posts p
    LEFT JOIN #{@table_prefix}_postmeta pm_start
      ON pm_start.post_id = p.ID AND pm_start.meta_key = '_start_date'
    LEFT JOIN #{@table_prefix}_postmeta pm_end
      ON pm_end.post_id = p.ID AND pm_end.meta_key = '_end_date'
    WHERE p.post_type = 'wc_user_membership'
      AND p.post_author = $1
    ORDER BY
      CASE p.post_status
        WHEN 'wcm-active' THEN 0
        WHEN 'wcm-cancelled' THEN 1
        WHEN 'wcm-expired' THEN 2
        ELSE 3
      END,
      CAST(p.ID AS BIGINT) DESC
    LIMIT 1
    """

    # shop_subscription — most recent, prefer active then on-hold
    sub_sql = """
    SELECT
      p.post_status AS sub_status,
      pm_start.meta_value AS sub_start_date,
      pm_next.meta_value AS sub_next_payment_date,
      pm_total.meta_value AS sub_amount,
      pm_period.meta_value AS sub_period
    FROM #{@table_prefix}_posts p
    JOIN #{@table_prefix}_postmeta pm_user
      ON pm_user.post_id = p.ID AND pm_user.meta_key = '_customer_user' AND pm_user.meta_value = $1
    LEFT JOIN #{@table_prefix}_postmeta pm_start
      ON pm_start.post_id = p.ID AND pm_start.meta_key = '_schedule_start'
    LEFT JOIN #{@table_prefix}_postmeta pm_next
      ON pm_next.post_id = p.ID AND pm_next.meta_key = '_schedule_next_payment'
    LEFT JOIN #{@table_prefix}_postmeta pm_total
      ON pm_total.post_id = p.ID AND pm_total.meta_key = '_order_total'
    LEFT JOIN #{@table_prefix}_postmeta pm_period
      ON pm_period.post_id = p.ID AND pm_period.meta_key = '_billing_period'
    WHERE p.post_type = 'shop_subscription'
    ORDER BY
      CASE p.post_status
        WHEN 'wc-active' THEN 0
        WHEN 'wc-on-hold' THEN 1
        WHEN 'wc-cancelled' THEN 2
        WHEN 'wc-expired' THEN 3
        ELSE 4
      END,
      CAST(p.ID AS BIGINT) DESC
    LIMIT 1
    """

    # Earliest _schedule_start across ALL subscriptions — "member since"
    sub_original_sql = """
    SELECT MIN(pm_start.meta_value) AS sub_original_start_date
    FROM #{@table_prefix}_posts p
    JOIN #{@table_prefix}_postmeta pm_user
      ON pm_user.post_id = p.ID AND pm_user.meta_key = '_customer_user' AND pm_user.meta_value = $1
    JOIN #{@table_prefix}_postmeta pm_start
      ON pm_start.post_id = p.ID AND pm_start.meta_key = '_schedule_start'
    WHERE p.post_type = 'shop_subscription'
      AND pm_start.meta_value IS NOT NULL
      AND pm_start.meta_value != ''
      AND pm_start.meta_value != '0000-00-00 00:00:00'
    """

    wcm =
      case query_maps(conn, wcm_sql, [uid_str]) do
        {:ok, [row | _]} -> row
        _ -> %{}
      end

    sub =
      case query_maps(conn, sub_sql, [uid_str]) do
        {:ok, [row | _]} -> row
        _ -> %{}
      end

    sub_original =
      case query_maps(conn, sub_original_sql, [uid_str]) do
        {:ok, [row | _]} -> row
        _ -> %{}
      end

    {:ok, wcm |> Map.merge(sub) |> Map.merge(sub_original)}
  end

  @doc "Returns attachment post row for the given attachment_id, or nil."
  def get_attachment(%__MODULE__{conn: conn}, attachment_id) do
    case query_maps(
           conn,
           "SELECT * FROM #{@table_prefix}_posts WHERE ID = $1 AND post_type = 'attachment'",
           [to_string(attachment_id)]
         ) do
      {:ok, [row | _]} -> row
      _ -> nil
    end
  end

  @doc """
  Returns the full filesystem path for an attachment, or nil if not found.
  wp_uploads_root is the path to wp_backup/files/wp-content/uploads (or equivalent).
  """
  def get_attachment_path(repo, attachment_id, wp_uploads_root)
      when is_binary(wp_uploads_root) do
    case get_attachment(repo, attachment_id) do
      nil ->
        nil

      _att ->
        meta = get_postmeta(repo, attachment_id)
        rel = meta["_wp_attached_file"]
        if rel && rel != "", do: Path.join([wp_uploads_root, rel]), else: nil
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp query_maps(conn, sql, params \\ []) do
    result =
      if params == [] do
        Duckdbex.query(conn, sql)
      else
        with {:ok, stmt} <- Duckdbex.prepare_statement(conn, sql) do
          Duckdbex.execute_statement(stmt, params)
        end
      end

    case result do
      {:ok, r} ->
        cols = Duckdbex.columns(r)
        rows = Duckdbex.fetch_all(r)

        maps =
          Enum.map(rows, fn row ->
            Enum.zip(cols, row)
            |> Map.new(fn {k, v} -> {k, normalize(v)} end)
          end)

        {:ok, maps}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Normalize DuckDB values to strings so downstream code can use
  # string comparisons (row["ID"] == "123" etc.) consistently.
  defp normalize(nil), do: nil
  defp normalize(v) when is_binary(v), do: v
  defp normalize(v), do: to_string(v)
end
