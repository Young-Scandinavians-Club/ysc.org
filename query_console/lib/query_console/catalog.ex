defmodule QueryConsole.Catalog do
  @moduledoc """
  Analytics schema introspection with ETS cache and persisted snapshots.
  """

  use GenServer

  import Ecto.Query

  alias QueryConsole.Catalog.SchemaSnapshot
  alias QueryConsole.Repo

  @table :query_console_schema_catalog
  @refresh_interval_ms :timer.minutes(15)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    # Avoid checking out the analytics sandbox connection during test boot —
    # tests own the sandbox and the Catalog GenServer would race them.
    if Application.get_env(:query_console, :catalog_auto_refresh, true) do
      send(self(), :refresh)
    end

    {:ok, %{version: 0}}
  end

  @doc """
  Returns the cached schema map, refreshing if empty.
  """
  def get_schema do
    case :ets.lookup(@table, :schema) do
      [{:schema, schema}] ->
        schema

      [] ->
        case safe_refresh() do
          schema when is_map(schema) -> schema
          _ -> %{"tables" => []}
        end
    end
  end

  defp safe_refresh do
    refresh()
  catch
    :exit, _ -> %{"tables" => []}
  end

  @doc """
  Forces a schema refresh from the analytics database via Lotus.
  """
  def refresh do
    GenServer.call(__MODULE__, :refresh, 60_000)
  end

  @doc """
  Compact schema map suitable for CodeMirror `@codemirror/lang-sql` schema option.
  Shape: `%{"table" => ["col1", "col2"], ...}` (and optionally `"schema.table"` keys).
  """
  def to_codemirror_schema do
    schema = get_schema()

    schema
    |> Map.get("tables", [])
    |> Enum.reduce(%{}, fn table, acc ->
      name = table["name"]
      schema_name = table["schema"]
      columns = Enum.map(table["columns"] || [], & &1["name"])

      acc
      |> Map.put(name, columns)
      |> then(fn map ->
        if schema_name && schema_name != "public" do
          Map.put(map, "#{schema_name}.#{name}", columns)
        else
          map
        end
      end)
    end)
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    case do_refresh(state.version) do
      {:ok, schema, version} ->
        {:reply, schema, %{state | version: version}}

      {:error, reason} ->
        {:reply, %{"tables" => [], "error" => inspect(reason)}, state}
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    {version, _schema} =
      case do_refresh(state.version) do
        {:ok, schema, version} -> {version, schema}
        {:error, _} -> {state.version, get_cached_or_empty()}
      end

    Process.send_after(self(), :refresh, @refresh_interval_ms)
    {:noreply, %{state | version: version}}
  end

  defp do_refresh(prev_version) do
    with {:ok, tables} <- Lotus.list_tables("analytics", include_views: true) do
      table_payloads =
        Enum.map(tables, fn
          {schema, table} -> build_table(schema, table)
          table when is_binary(table) -> build_table("public", table)
        end)

      schema = %{
        "tables" => table_payloads,
        "refreshed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      version = prev_version + 1
      :ets.insert(@table, {:schema, schema})
      _ = maybe_persist_snapshot(version, schema)
      {:ok, schema, version}
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  defp maybe_persist_snapshot(version, payload) do
    persist_snapshot!(version, payload)
  rescue
    _ -> :ok
  end

  defp build_table(schema, table) do
    columns =
      case Lotus.get_table_schema("analytics", table, schema: schema) do
        {:ok, cols} when is_list(cols) ->
          Enum.map(cols, fn col ->
            name = col[:name] || col["name"] || ""
            type = col[:type] || col["type"] || ""
            nullable = col[:nullable] || col["nullable"]

            %{
              "name" => to_string(name),
              "type" => to_string(type),
              "nullable" => nullable
            }
          end)

        _ ->
          []
      end

    %{
      "schema" => schema,
      "name" => table,
      "columns" => columns
    }
  end

  defp persist_snapshot!(version, payload) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %SchemaSnapshot{}
    |> Ecto.Changeset.change(%{version: version, payload: payload, inserted_at: now})
    |> Repo.insert!()

    # Keep last 10 snapshots
    keep =
      from(s in SchemaSnapshot, order_by: [desc: s.version], limit: 10, select: s.id)
      |> Repo.all()

    from(s in SchemaSnapshot, where: s.id not in ^keep)
    |> Repo.delete_all()
  end

  defp get_cached_or_empty do
    case :ets.lookup(@table, :schema) do
      [{:schema, schema}] -> schema
      [] -> %{"tables" => []}
    end
  end
end
