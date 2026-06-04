defmodule Ysc.WpMigration.SqlToDuckdb do
  @compile {:no_warn_undefined, Duckdbex}
  @moduledoc """
  Streams a WordPress MySQL dump file and loads it directly into a persistent
  DuckDB database file — no intermediate CSV step.

  Tables extracted (all using the configured `table_prefix`, default `wp0h`):
    users, usermeta, posts, postmeta  (required)
    wc_orders, wc_orders_meta, wc_order_stats,
    woocommerce_payment_tokens, woocommerce_payment_tokenmeta  (optional — skipped if absent)

  The output is a `.duckdb` file that `WpRepo.open/1` can open instantly for
  full SQL queries with DuckDB's own paging and memory management.

  ## Approach

  The dump is read line-by-line via `File.stream!/1`. When a line begins an
  INSERT INTO block we accumulate lines until we hit the closing semicolon,
  then parse the VALUES clause with the same zero-regex character scanner used
  previously, and bulk-insert each row via `Duckdbex.Appender`.

  This keeps the memory footprint proportional to a single INSERT statement
  (typically a few MB at most) rather than the whole dump.
  """

  @required_tables ~w(users usermeta posts postmeta)
  @optional_tables ~w(wc_orders wc_orders_meta wc_order_stats woocommerce_payment_tokens woocommerce_payment_tokenmeta)

  @table_schemas %{
    "users" =>
      ~w(ID user_login user_pass user_nicename user_email user_url user_registered user_activation_key user_status display_name),
    "usermeta" => ~w(umeta_id user_id meta_key meta_value),
    "posts" =>
      ~w(ID post_author post_date post_date_gmt post_content post_title post_excerpt post_status comment_status ping_status post_password post_name to_ping pinged post_modified post_modified_gmt post_content_filtered post_parent guid menu_order post_type post_mime_type comment_count),
    "postmeta" => ~w(meta_id post_id meta_key meta_value),
    "wc_orders" =>
      ~w(id status currency type tax_amount total_amount customer_id billing_email date_created_gmt date_updated_gmt parent_order_id payment_method payment_method_title transaction_id ip_address user_agent customer_note),
    "wc_orders_meta" => ~w(id order_id meta_key meta_value),
    "wc_order_stats" =>
      ~w(order_id parent_id date_created date_created_gmt num_items_sold total_sales tax_total shipping_total net_total returning_customer status customer_id date_paid date_completed),
    # Saved payment tokens — gateway, token value, user_id, type, is_default
    "woocommerce_payment_tokens" =>
      ~w(token_id gateway_id token user_id type is_default),
    # Token metadata — last4, expiry_year, expiry_month, card_type, etc.
    "woocommerce_payment_tokenmeta" =>
      ~w(meta_id payment_token_id meta_key meta_value)
  }

  @doc """
  Parse `sql_path` and write a DuckDB database to `db_path`.

  Options:
    - `:table_prefix` — prefix used in the dump (default: `"wp0h"`)
    - `:force`        — overwrite existing db_path (default: `false`)
  """
  def run(sql_path, db_path, opts \\ []) do
    prefix = opts[:table_prefix] || "wp0h"
    force = opts[:force] || false

    cond do
      not File.exists?(sql_path) ->
        {:error, "SQL dump not found: #{sql_path}"}

      File.exists?(db_path) and not force ->
        {:error,
         "DuckDB file already exists: #{db_path}. Pass force: true or delete it first."}

      true ->
        if File.exists?(db_path), do: File.rm!(db_path)
        do_run(sql_path, db_path, prefix)
    end
  end

  # ---------------------------------------------------------------------------

  defp do_run(sql_path, db_path, prefix) do
    with {:ok, db} <- Duckdbex.open(db_path),
         {:ok, conn} <- Duckdbex.connection(db) do
      tables = @required_tables ++ @optional_tables

      # Create all tables upfront (all columns are VARCHAR for simplicity)
      Enum.each(tables, fn table ->
        cols = @table_schemas[table]
        col_defs = Enum.map_join(cols, ", ", fn c -> ~s("#{c}" VARCHAR) end)
        sql = "CREATE TABLE IF NOT EXISTS \"#{prefix}_#{table}\" (#{col_defs})"
        Duckdbex.query(conn, sql)
      end)

      counts = stream_and_load(sql_path, conn, prefix, tables)

      Duckdbex.release(conn)
      {:ok, counts}
    end
  end

  # ---------------------------------------------------------------------------
  # Streaming parser
  # ---------------------------------------------------------------------------

  # State machine per line. We watch for INSERT INTO `<prefix>_<table>` lines,
  # then accumulate until we see the closing unquoted semicolon, then flush.

  @dialyzer {:nowarn_function, stream_and_load: 4}
  defp stream_and_load(sql_path, conn, prefix, tables) do
    target_tables = MapSet.new(tables)

    initial = %{
      mode: :scan,
      current_table: nil,
      current_cols: nil,
      appender: nil,
      buf: [],
      counts: Map.new(tables, &{&1, 0}),
      conn: conn,
      prefix: prefix,
      target_tables: target_tables
    }

    state =
      sql_path
      |> File.stream!([], :line)
      |> Enum.reduce(initial, &process_line/2)

    # Flush any open appender at EOF
    state = flush_appender(state)

    state.counts
  end

  defp process_line(line, %{mode: :scan} = state) do
    trimmed = String.trim_leading(line)

    case parse_insert_header(trimmed, state.prefix, state.target_tables) do
      {:ok, table, cols} ->
        state = flush_appender(state)

        {:ok, appender} =
          Duckdbex.appender(state.conn, "#{state.prefix}_#{table}")

        rest = after_values_keyword(trimmed)

        new_state = %{
          state
          | mode: :collect,
            current_table: table,
            current_cols: cols,
            appender: appender,
            buf: if(rest != "", do: [rest], else: [])
        }

        # Single-line INSERT: VALUES were on the same line as the header.
        # Flush immediately rather than waiting for a subsequent line.
        if rest != "" do
          maybe_flush_block(new_state)
        else
          new_state
        end

      :skip ->
        state
    end
  end

  defp process_line(line, %{mode: :collect} = state) do
    %{state | buf: [line | state.buf]}
    |> maybe_flush_block()
  end

  # Check if the accumulated buffer now contains a complete INSERT (ends with ;)
  defp maybe_flush_block(%{buf: buf} = state) do
    combined = buf |> Enum.reverse() |> IO.iodata_to_binary()

    if block_complete?(combined) do
      # Strip trailing whitespace/semicolons then parse all rows
      values_str =
        combined |> String.trim_trailing() |> String.trim_trailing(";")

      rows = parse_all_rows(values_str)
      cols = state.current_cols

      count =
        Enum.reduce(rows, 0, fn row_fields, acc ->
          padded =
            row_fields
            |> sanitize_row_utf8()
            |> pad_or_trim(length(cols))

          case Duckdbex.appender_add_row(state.appender, padded) do
            :ok -> acc + 1
            _ -> acc
          end
        end)

      Duckdbex.appender_flush(state.appender)

      table = state.current_table
      new_counts = Map.update(state.counts, table, count, &(&1 + count))

      %{state | mode: :scan, buf: [], counts: new_counts}
    else
      state
    end
  end

  # A block is complete when the last non-whitespace character is a semicolon
  # (outside of a quoted string). We use a simple heuristic: the last byte.
  defp block_complete?(str) do
    str |> String.trim_trailing() |> String.last() == ";"
  end

  defp flush_appender(%{appender: nil} = state), do: state

  defp flush_appender(state) do
    # If we were mid-block, try to flush whatever we have
    state =
      if state.buf != [] do
        maybe_flush_block(state)
      else
        state
      end

    if state.appender do
      Duckdbex.appender_flush(state.appender)
      Duckdbex.appender_close(state.appender)
    end

    %{
      state
      | appender: nil,
        mode: :scan,
        buf: [],
        current_table: nil,
        current_cols: nil
    }
  end

  # ---------------------------------------------------------------------------
  # Header parsing
  # ---------------------------------------------------------------------------

  # Matches: INSERT INTO `prefix_table` (col, ...) VALUES
  #      or: INSERT INTO `prefix_table` VALUES
  defp parse_insert_header(line, prefix, target_tables) do
    marker = "INSERT INTO `#{prefix}_"

    if String.starts_with?(line, marker) do
      rest =
        binary_part(
          line,
          byte_size(marker),
          byte_size(line) - byte_size(marker)
        )

      case :binary.match(rest, "`") do
        :nomatch ->
          :skip

        {pos, _} ->
          table = binary_part(rest, 0, pos)

          if MapSet.member?(target_tables, table) do
            after_table = binary_part(rest, pos + 1, byte_size(rest) - pos - 1)
            cols = parse_column_list(after_table) || @table_schemas[table] || []
            {:ok, table, cols}
          else
            :skip
          end
      end
    else
      :skip
    end
  end

  # Extract optional (col1, col2, ...) from ` (col1, col2) VALUES ...`
  defp parse_column_list(str) do
    trimmed = String.trim_leading(str)

    if String.starts_with?(trimmed, "(") do
      case :binary.match(trimmed, ")") do
        :nomatch ->
          nil

        {end_pos, _} ->
          inner = binary_part(trimmed, 1, end_pos - 1)

          inner
          |> String.split(",")
          |> Enum.map(&(String.trim(&1) |> String.trim("`")))
      end
    else
      nil
    end
  end

  # Return everything after the VALUES keyword on the same line (if any)
  defp after_values_keyword(line) do
    uline = String.upcase(line)

    case :binary.match(uline, "VALUES") do
      :nomatch ->
        ""

      {pos, len} ->
        binary_part(line, pos + len, byte_size(line) - pos - len)
        |> String.trim_leading()
    end
  end

  # ---------------------------------------------------------------------------
  # Row parser — reused from SqlToCsv, zero regex
  # ---------------------------------------------------------------------------

  defp parse_all_rows(str) do
    str = String.trim(str)
    do_parse_rows(str, [])
  end

  defp do_parse_rows("", acc), do: Enum.reverse(acc)

  defp do_parse_rows(str, acc) do
    str = skip_whitespace_and_commas(str)

    if String.starts_with?(str, "(") do
      {inner, rest} =
        extract_paren_content(binary_part(str, 1, byte_size(str) - 1))

      fields = parse_row_fields(inner)
      do_parse_rows(rest, [fields | acc])
    else
      Enum.reverse(acc)
    end
  end

  defp skip_whitespace_and_commas(<<c, rest::binary>>)
       when c in [?\s, ?\n, ?\r, ?\t, ?,],
       do: skip_whitespace_and_commas(rest)

  defp skip_whitespace_and_commas(str), do: str

  defp extract_paren_content(str), do: do_extract_paren(str, 0, [])

  # acc is built right-growing as [prev_acc, new_item] iodata —
  # IO.iodata_to_binary processes it left-to-right (correct order).
  # Do NOT Enum.reverse here; that would swap the last appended item to the front.
  defp do_extract_paren(<<>>, _depth, acc),
    do: {IO.iodata_to_binary(acc), ""}

  defp do_extract_paren(<<?), rest::binary>>, 0, acc),
    do: {IO.iodata_to_binary(acc), rest}

  defp do_extract_paren(<<?), rest::binary>>, depth, acc),
    do: do_extract_paren(rest, depth - 1, [acc, ")"])

  defp do_extract_paren(<<?(, rest::binary>>, depth, acc),
    do: do_extract_paren(rest, depth + 1, [acc, "("])

  defp do_extract_paren(<<?', rest::binary>>, depth, acc) do
    {raw, rest2} = scan_raw_quoted(rest, ?')
    do_extract_paren(rest2, depth, [acc, ?', raw, ?'])
  end

  defp do_extract_paren(<<?", rest::binary>>, depth, acc) do
    {raw, rest2} = scan_raw_quoted(rest, ?")
    do_extract_paren(rest2, depth, [acc, ?", raw, ?"])
  end

  defp do_extract_paren(<<c, rest::binary>>, depth, acc),
    do: do_extract_paren(rest, depth, [acc, c])

  defp parse_row_fields(str), do: do_parse_fields(str, [])

  defp do_parse_fields("", acc), do: Enum.reverse(acc)

  defp do_parse_fields(str, acc) do
    str = skip_sep(str)

    cond do
      str == "" ->
        Enum.reverse(acc)

      String.starts_with?(str, "NULL") ->
        rest = binary_part(str, 4, byte_size(str) - 4)
        do_parse_fields(rest, [nil | acc])

      String.starts_with?(str, "'") ->
        {val, rest} = scan_quoted(binary_part(str, 1, byte_size(str) - 1), ?')
        do_parse_fields(rest, [IO.iodata_to_binary(val) | acc])

      String.starts_with?(str, "\"") ->
        {val, rest} = scan_quoted(binary_part(str, 1, byte_size(str) - 1), ?")
        do_parse_fields(rest, [IO.iodata_to_binary(val) | acc])

      true ->
        {val, rest} = scan_unquoted(str)
        do_parse_fields(rest, [IO.iodata_to_binary(val) | acc])
    end
  end

  defp skip_sep(<<?,, rest::binary>>), do: String.trim_leading(rest)
  defp skip_sep(str), do: String.trim_leading(str)

  # Replace invalid UTF-8 byte sequences in string fields so DuckDB does not
  # reject the row with "Invalid unicode" errors.
  defp sanitize_row_utf8(fields) when is_list(fields),
    do: Enum.map(fields, &sanitize_field_utf8/1)

  defp sanitize_field_utf8(s) when is_binary(s), do: fix_utf8(s, <<>>)
  defp sanitize_field_utf8(v), do: v

  defp fix_utf8(<<>>, acc), do: acc

  defp fix_utf8(str, acc) do
    case :unicode.characters_to_binary(str, :utf8) do
      binary when is_binary(binary) ->
        acc <> binary

      {:error, good, <<_, rest::binary>>} ->
        fix_utf8(rest, acc <> good)

      {:incomplete, good, _} ->
        acc <> good
    end
  end

  # Passes raw bytes through a quoted string WITHOUT resolving escape sequences.
  # Used by do_extract_paren so that the inner row binary retains original SQL
  # escaping; do_parse_fields → scan_quoted then resolves escapes exactly once.
  defp scan_raw_quoted(str, q), do: do_scan_raw_quoted(str, q, [])

  defp do_scan_raw_quoted(<<>>, _q, acc), do: {Enum.reverse(acc), ""}

  defp do_scan_raw_quoted(<<q, rest::binary>>, q, acc),
    do: {Enum.reverse(acc), rest}

  # Keep the backslash + quote so the closing-quote detector above is never
  # triggered by an escaped quote inside the field value.
  # NOTE: acc is built in reverse (Enum.reverse at the end), so the element
  # that should appear FIRST in the output must be prepended LAST.
  # For `\'` we want output bytes [.., '\', '\''], so we prepend quote then backslash.
  defp do_scan_raw_quoted(<<?\\, q, rest::binary>>, q, acc),
    do: do_scan_raw_quoted(rest, q, [q, ?\\ | acc])

  defp do_scan_raw_quoted(<<?\\, c, rest::binary>>, q, acc),
    do: do_scan_raw_quoted(rest, q, [c, ?\\ | acc])

  defp do_scan_raw_quoted(<<c, rest::binary>>, q, acc),
    do: do_scan_raw_quoted(rest, q, [c | acc])

  defp scan_quoted(str, quote), do: do_scan_quoted(str, quote, [])

  defp do_scan_quoted(<<>>, _q, acc), do: {Enum.reverse(acc), ""}

  defp do_scan_quoted(<<q, rest::binary>>, q, acc),
    do: {Enum.reverse(acc), rest}

  defp do_scan_quoted(<<?\\, q, rest::binary>>, q, acc),
    do: do_scan_quoted(rest, q, [q | acc])

  defp do_scan_quoted(<<?\\, ?\\, rest::binary>>, q, acc),
    do: do_scan_quoted(rest, q, [?\\ | acc])

  defp do_scan_quoted(<<?\\, ?n, rest::binary>>, q, acc),
    do: do_scan_quoted(rest, q, [?\n | acc])

  defp do_scan_quoted(<<?\\, ?r, rest::binary>>, q, acc),
    do: do_scan_quoted(rest, q, [?\r | acc])

  defp do_scan_quoted(<<?\\, ?t, rest::binary>>, q, acc),
    do: do_scan_quoted(rest, q, [?\t | acc])

  defp do_scan_quoted(<<?\\, _, rest::binary>>, q, acc),
    do: do_scan_quoted(rest, q, acc)

  defp do_scan_quoted(<<c, rest::binary>>, q, acc),
    do: do_scan_quoted(rest, q, [c | acc])

  defp scan_unquoted(str), do: do_scan_unquoted(str, [])

  defp do_scan_unquoted("", acc), do: {Enum.reverse(acc), ""}

  defp do_scan_unquoted(<<?,, _::binary>> = rest, acc),
    do: {Enum.reverse(acc), rest}

  defp do_scan_unquoted(<<c, rest::binary>>, acc),
    do: do_scan_unquoted(rest, [c | acc])

  defp pad_or_trim(fields, expected) do
    len = length(fields)

    cond do
      len == expected -> fields
      len < expected -> fields ++ List.duplicate(nil, expected - len)
      true -> Enum.take(fields, expected)
    end
  end
end
