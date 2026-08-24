defmodule QueryConsole.Runner.UlidRewrite do
  @moduledoc """
  Rewrites ULID string literals into their equivalent Postgres `uuid` text
  form, so a ULID copied from the app UI (Crockford Base32, 26 chars) can be
  pasted straight into a query without the user converting it by hand first.

  Only rewrites a literal when it's unambiguous that it's meant as a uuid:

    * explicitly cast — `'...'::uuid` or `CAST('...' AS uuid)`
    * compared with `=`, `<>`/`!=`, or `IN (...)` against a column that the
      schema catalog reports as type `uuid`

  A ULID-shaped literal anywhere else (e.g. compared against a text/varchar
  column, or just selected as a value) is left untouched, since converting it
  there could silently change query semantics instead of just fixing a type
  error.
  """

  alias QueryConsole.Catalog

  @comparison_ops ["=", "<>", "!="]

  @doc """
  Returns `sql` with eligible ULID literals rewritten to uuid text form.
  Falls back to returning `sql` unchanged if it fails to parse or nothing
  matches.

  `uuid_cols` defaults to the live schema catalog's set of `uuid`-typed
  column names; pass an explicit `MapSet` (e.g. in tests) to avoid touching
  the catalog.
  """
  def rewrite(sql, uuid_cols \\ nil)

  def rewrite(sql, uuid_cols) when is_binary(sql) do
    case PgQuery.parse(sql) do
      {:ok, %PgQuery.ParseResult{stmts: raw_stmts}} ->
        uuid_cols = uuid_cols || uuid_columns()

        candidates =
          raw_stmts
          |> Enum.flat_map(fn %PgQuery.RawStmt{stmt: stmt} -> walk(stmt, uuid_cols, []) end)
          |> Enum.uniq_by(& &1.location)
          |> Enum.sort_by(& &1.location, :desc)

        Enum.reduce(candidates, sql, &apply_candidate/2)

      _ ->
        sql
    end
  end

  defp uuid_columns do
    Catalog.get_schema()
    |> Map.get("tables", [])
    |> Enum.flat_map(fn table -> table["columns"] || [] end)
    |> Enum.filter(fn col -> String.downcase(to_string(col["type"] || "")) == "uuid" end)
    |> Enum.map(fn col -> String.downcase(to_string(col["name"] || "")) end)
    |> MapSet.new()
  end

  # --- tree walk -------------------------------------------------------

  defp walk(%PgQuery.Node{node: {:type_cast, %PgQuery.TypeCast{} = tc}}, uuid_cols, acc) do
    walk_struct(tc, uuid_cols, candidates_from_cast(tc) ++ acc)
  end

  defp walk(%PgQuery.Node{node: {:a_expr, %PgQuery.A_Expr{} = expr}}, uuid_cols, acc) do
    walk_struct(expr, uuid_cols, candidates_from_expr(expr, uuid_cols) ++ acc)
  end

  defp walk(%PgQuery.Node{node: {_type, inner}}, uuid_cols, acc), do: walk(inner, uuid_cols, acc)
  defp walk(%PgQuery.Node{node: nil}, _uuid_cols, acc), do: acc
  defp walk(%_struct{} = s, uuid_cols, acc), do: walk_struct(s, uuid_cols, acc)

  defp walk(list, uuid_cols, acc) when is_list(list) do
    Enum.reduce(list, acc, &walk(&1, uuid_cols, &2))
  end

  defp walk(_scalar, _uuid_cols, acc), do: acc

  defp walk_struct(s, uuid_cols, acc) do
    s
    |> Map.from_struct()
    |> Map.drop([:__uf__])
    |> Map.values()
    |> Enum.reduce(acc, &walk(&1, uuid_cols, &2))
  end

  # --- context detection -------------------------------------------------

  defp candidates_from_cast(%PgQuery.TypeCast{
         arg: %PgQuery.Node{node: {:a_const, %PgQuery.A_Const{} = ac}},
         type_name: type_name
       }) do
    if uuid_type_name?(type_name), do: literal_candidate(ac), else: []
  end

  defp candidates_from_cast(_), do: []

  defp uuid_type_name?(%PgQuery.TypeName{names: names}) do
    case names |> Enum.map(&node_string_value/1) |> List.last() do
      nil -> false
      name -> String.downcase(name) == "uuid"
    end
  end

  defp uuid_type_name?(_), do: false

  defp candidates_from_expr(
         %PgQuery.A_Expr{kind: :AEXPR_OP, name: name, lexpr: lexpr, rexpr: rexpr},
         uuid_cols
       ) do
    if comparison_op?(name) do
      cond do
        column_ref?(lexpr, uuid_cols) and a_const?(rexpr) -> literal_candidate(a_const_of(rexpr))
        column_ref?(rexpr, uuid_cols) and a_const?(lexpr) -> literal_candidate(a_const_of(lexpr))
        true -> []
      end
    else
      []
    end
  end

  defp candidates_from_expr(
         %PgQuery.A_Expr{kind: :AEXPR_IN, lexpr: lexpr, rexpr: rexpr},
         uuid_cols
       ) do
    if column_ref?(lexpr, uuid_cols) do
      case rexpr do
        %PgQuery.Node{node: {:list, %PgQuery.List{items: items}}} ->
          items
          |> Enum.filter(&a_const?/1)
          |> Enum.flat_map(&literal_candidate(a_const_of(&1)))

        _ ->
          []
      end
    else
      []
    end
  end

  defp candidates_from_expr(_, _), do: []

  defp comparison_op?(name) do
    name
    |> Enum.map(&node_string_value/1)
    |> Enum.any?(&(&1 in @comparison_ops))
  end

  defp column_ref?(
         %PgQuery.Node{node: {:column_ref, %PgQuery.ColumnRef{fields: fields}}},
         uuid_cols
       ) do
    case fields |> Enum.map(&node_string_value/1) |> List.last() do
      nil -> false
      name -> MapSet.member?(uuid_cols, String.downcase(name))
    end
  end

  defp column_ref?(_, _), do: false

  defp a_const?(%PgQuery.Node{node: {:a_const, _}}), do: true
  defp a_const?(_), do: false

  defp a_const_of(%PgQuery.Node{node: {:a_const, ac}}), do: ac

  defp node_string_value(%PgQuery.Node{node: {:string, %PgQuery.String{sval: sval}}}), do: sval
  defp node_string_value(_), do: nil

  # --- literal -> candidate ----------------------------------------------

  defp literal_candidate(%PgQuery.A_Const{
         location: location,
         val: {:sval, %PgQuery.String{sval: sval}}
       }) do
    case ulid_to_uuid(sval) do
      {:ok, uuid} -> [%{location: location, ulid: sval, uuid: uuid}]
      :error -> []
    end
  end

  defp literal_candidate(_), do: []

  defp ulid_to_uuid(text) when byte_size(text) == 26 do
    with {:ok, bin} <- Ecto.ULID.dump(text),
         {:ok, uuid} <- Ecto.UUID.load(bin) do
      {:ok, uuid}
    else
      _ -> :error
    end
  end

  defp ulid_to_uuid(_), do: :error

  # --- text-level replacement ---------------------------------------------

  defp apply_candidate(%{location: location, ulid: ulid, uuid: uuid}, sql) do
    expected = "'" <> ulid <> "'"

    if exact_match?(sql, location, expected) do
      len = byte_size(expected)
      before = :binary.part(sql, 0, location)
      rest = :binary.part(sql, location + len, byte_size(sql) - location - len)
      before <> "'" <> uuid <> "'" <> rest
    else
      sql
    end
  end

  defp exact_match?(sql, location, expected) do
    len = byte_size(expected)

    location >= 0 and location + len <= byte_size(sql) and
      :binary.part(sql, location, len) == expected
  end
end
