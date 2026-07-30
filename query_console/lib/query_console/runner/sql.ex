defmodule QueryConsole.Runner.SQL do
  @moduledoc """
  Parse multi-statement SQL with PgQuery and enforce read-only preflight.
  """

  @allowed_node_types MapSet.new([
                        :select_stmt,
                        :explain_stmt
                      ])

  @denied_node_types MapSet.new([
                       :insert_stmt,
                       :update_stmt,
                       :delete_stmt,
                       :merge_stmt,
                       :copy_stmt,
                       :create_stmt,
                       :create_table_as_stmt,
                       :create_schema_stmt,
                       :create_function_stmt,
                       :create_trig_stmt,
                       :create_role_stmt,
                       :create_seq_stmt,
                       :create_enum_stmt,
                       :create_domain_stmt,
                       :create_extension_stmt,
                       :create_view_stmt,
                       :create_am_stmt,
                       :create_cast_stmt,
                       :create_conversion_stmt,
                       :create_op_class_stmt,
                       :create_op_family_stmt,
                       :create_policy_stmt,
                       :create_publication_stmt,
                       :create_range_stmt,
                       :create_stats_stmt,
                       :create_subscription_stmt,
                       :create_table_space_stmt,
                       :create_transform_stmt,
                       :create_user_mapping_stmt,
                       :createdb_stmt,
                       :drop_stmt,
                       :dropdb_stmt,
                       :drop_role_stmt,
                       :drop_subscription_stmt,
                       :drop_table_space_stmt,
                       :drop_user_mapping_stmt,
                       :alter_table_stmt,
                       :alter_domain_stmt,
                       :alter_enum_stmt,
                       :alter_function_stmt,
                       :alter_object_schema_stmt,
                       :alter_owner_stmt,
                       :alter_role_stmt,
                       :alter_seq_stmt,
                       :alter_default_privileges_stmt,
                       :alter_policy_stmt,
                       :alter_publication_stmt,
                       :alter_subscription_stmt,
                       :alter_system_stmt,
                       :alter_ts_config_stmt,
                       :alter_ts_dictionary_stmt,
                       :alter_table_space_options_stmt,
                       :alter_user_mapping_stmt,
                       :truncate_stmt,
                       :vacuum_stmt,
                       :reindex_stmt,
                       :cluster_stmt,
                       :refresh_mat_view_stmt,
                       :grant_stmt,
                       :grant_role_stmt,
                       :lock_stmt,
                       :listen_stmt,
                       :notify_stmt,
                       :unlisten_stmt,
                       :do_stmt,
                       :call_stmt,
                       :prepare_stmt,
                       :execute_stmt,
                       :deallocate_stmt,
                       :transaction_stmt,
                       :variable_set_stmt,
                       :variable_show_stmt,
                       :declare_cursor_stmt,
                       :close_portal_stmt,
                       :fetch_stmt,
                       :index_stmt,
                       :rule_stmt,
                       :rename_stmt,
                       :comment_stmt,
                       :sec_label_stmt,
                       :load_stmt,
                       :check_point_stmt,
                       :discard_stmt,
                       :constraints_set_stmt,
                       :reassign_owned_stmt
                     ])

  defmodule Statement do
    @enforce_keys [:index, :sql, :node_type]
    defstruct [:index, :sql, :node_type, :location, :length]
  end

  @doc """
  Splits SQL into top-level statements using PgQuery stmt locations.
  """
  def split_statements(sql) when is_binary(sql) do
    trimmed = String.trim(sql)

    if trimmed == "" do
      {:ok, []}
    else
      case PgQuery.parse(sql) do
        {:ok, %PgQuery.ParseResult{stmts: raw_stmts}} ->
          statements =
            raw_stmts
            |> Enum.with_index()
            |> Enum.map(fn {raw, idx} ->
              {stmt_sql, location, length} = extract_sql(sql, raw)
              node_type = node_type(raw)

              %Statement{
                index: idx,
                sql: String.trim(stmt_sql),
                node_type: node_type,
                location: location,
                length: length
              }
            end)
            |> Enum.reject(fn %Statement{sql: s} -> s == "" end)

          {:ok, statements}

        {:error, %{message: message}} ->
          {:error, {:parse_error, message}}

        {:error, reason} ->
          {:error, {:parse_error, inspect(reason)}}
      end
    end
  end

  @doc """
  Rejects write/DDL/DML statements. Returns `:ok` or `{:error, reason}`.
  """
  def preflight(statements) when is_list(statements) do
    Enum.reduce_while(statements, :ok, fn stmt, :ok ->
      case validate_statement(stmt) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  def validate_statement(%Statement{sql: sql, node_type: node_type} = stmt) do
    cond do
      MapSet.member?(@denied_node_types, node_type) ->
        {:error, {:write_rejected, "Statement #{stmt.index + 1} is not read-only (#{node_type})"}}

      not MapSet.member?(@allowed_node_types, node_type) ->
        {:error,
         {:write_rejected, "Statement #{stmt.index + 1} type not allowed (#{inspect(node_type)})"}}

      node_type == :select_stmt and select_into?(stmt) ->
        {:error, {:write_rejected, "SELECT INTO is not allowed"}}

      node_type == :select_stmt and select_for_update?(stmt) ->
        {:error, {:write_rejected, "SELECT FOR UPDATE/SHARE is not allowed"}}

      modifying_cte?(sql) ->
        {:error,
         {:write_rejected, "Modifying CTEs (WITH ... INSERT/UPDATE/DELETE) are not allowed"}}

      true ->
        :ok
    end
  end

  defp extract_sql(sql, %PgQuery.RawStmt{stmt_location: loc, stmt_len: len}) do
    byte_size = byte_size(sql)

    location = max(loc || 0, 0)

    length =
      cond do
        is_integer(len) and len > 0 -> len
        true -> byte_size - location
      end

    length = min(length, byte_size - location)
    {binary_part(sql, location, length), location, length}
  end

  defp node_type(%PgQuery.RawStmt{stmt: %PgQuery.Node{node: {type, _}}}), do: type
  defp node_type(_), do: :unknown

  defp select_into?(%Statement{} = stmt) do
    case stmt_node(stmt) do
      {:select_stmt, %PgQuery.SelectStmt{into_clause: into}} when not is_nil(into) -> true
      _ -> false
    end
  end

  defp select_for_update?(%Statement{} = stmt) do
    case stmt_node(stmt) do
      {:select_stmt, %PgQuery.SelectStmt{locking_clause: locks}}
      when is_list(locks) and locks != [] ->
        true

      _ ->
        false
    end
  end

  defp stmt_node(%Statement{sql: sql}) do
    case PgQuery.parse(sql) do
      {:ok, %PgQuery.ParseResult{stmts: [%PgQuery.RawStmt{stmt: %PgQuery.Node{node: node}} | _]}} ->
        node

      _ ->
        nil
    end
  end

  defp modifying_cte?(sql) do
    Regex.match?(
      ~r/\bwith\b[\s\S]*\b(insert|update|delete|merge)\b[\s\S]*\bselect\b/i,
      sql
    )
  end
end
