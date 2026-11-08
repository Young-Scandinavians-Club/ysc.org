defmodule QueryConsole.EctoUpgradeTest do
  @moduledoc """
  Guards the ecto 3.14.2 → 3.14.3 upgrade.

  3.14.3 patches EEF-CVE-2026-118391 (HIGH / CVE-2026-118391 /
  GHSA-cxjx-vmm2-qr8r). Interpolated JSON path elements and `splice/1`
  list lengths used to become part of the prepared-query cache key, so
  each distinct key or length added an ETS entry and a PostgreSQL
  prepared statement that was never evicted. Interpolated JSON paths
  are now stored as `:inline` parameters (the planner inlines them and
  does not send them to the adapter) and those queries, plus
  interpolated `splice/1` / `constant/1`, are marked uncacheable.

  Also: join prefixes and hints are part of the cache key, and a
  runtime `true` filter is kept when a later `or_where` depends on it.

  Query Console does not interpolate JSON paths or `splice/1` in app
  code. Analytics reads go through `AnalyticsRepo.query/3` (raw SQL).
  SchemaSnapshot.payload is a map used only as a stored catalog dump.
  """
  use QueryConsole.DataCase, async: true

  import Ecto.Query

  alias QueryConsole.Accounts.User
  alias QueryConsole.Catalog.SchemaSnapshot
  alias QueryConsole.Repo

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/ecto/CHANGELOG.md", __DIR__)
  @planner Path.expand("../../deps/ecto/lib/ecto/query/planner.ex", __DIR__)
  @builder Path.expand("../../deps/ecto/lib/ecto/query/builder.ex", __DIR__)
  @filter Path.expand("../../deps/ecto/lib/ecto/query/builder/filter.ex", __DIR__)
  @api Path.expand("../../deps/ecto/lib/ecto/query/api.ex", __DIR__)
  @lib_dir Path.expand("../../lib", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ecto)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:module, Ecto} = Code.ensure_loaded(Ecto)
    {:module, Ecto.Query} = Code.ensure_loaded(Ecto.Query)
    {:module, Ecto.Query.Planner} = Code.ensure_loaded(Ecto.Query.Planner)
    {:module, Ecto.Query.Builder} = Code.ensure_loaded(Ecto.Query.Builder)
    {:module, Ecto.Changeset} = Code.ensure_loaded(Ecto.Changeset)
    {:module, Ecto.Adapters.Postgres} = Code.ensure_loaded(Ecto.Adapters.Postgres)
    :ok
  end

  describe "3.14.3 Hex lock and public APIs" do
    test "locks the Hex package to 3.14.3" do
      {:module, _} = Code.ensure_loaded(Ecto)
      assert to_string(Application.spec(:ecto, :vsn)) == "3.14.3"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:ecto, "~> 3.14.3"})
      refute mix_exs =~ ~s({:ecto, "~> 3.13"})
    end

    test "companion locks stay put" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"ecto": {:hex, :ecto, "3.14.3"|
      refute lock =~ ~s|"ecto": {:hex, :ecto, "3.14.2"|
      assert lock =~ ~s|"ecto_sql": {:hex, :ecto_sql, "3.14.0"|
      assert lock =~ ~s|"phoenix_ecto": {:hex, :phoenix_ecto, "4.7.0"|
      assert lock =~ ~s|"lotus": {:hex, :lotus, "1.3.2"|
      assert lock =~ ~s|"lotus_web": {:hex, :lotus_web, "1.4.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.1.0"|
      assert lock =~ ~s|"decimal": {:hex, :decimal, "3.2.0"|
      assert lock =~ ~s|"finch": {:hex, :finch, "0.24.0"|
      assert lock =~ ~s|"jsv": {:hex, :jsv, "0.26.2"|
    end

    test "Repo and changeset APIs Query Console uses still exist" do
      {:module, Repo} = Code.ensure_loaded(Repo)
      {:module, Ecto.Changeset} = Code.ensure_loaded(Ecto.Changeset)
      {:module, Ecto.Query} = Code.ensure_loaded(Ecto.Query)
      {:module, Ecto.Query.API} = Code.ensure_loaded(Ecto.Query.API)

      assert function_exported?(Repo, :get, 2)
      assert function_exported?(Repo, :get_by, 2)
      assert function_exported?(Repo, :all, 1)
      assert function_exported?(Repo, :insert, 1)
      assert function_exported?(Repo, :insert!, 1)
      assert function_exported?(Repo, :update, 1)
      assert function_exported?(Repo, :update!, 1)
      assert function_exported?(Repo, :delete, 1)
      assert function_exported?(Repo, :delete_all, 1)
      assert function_exported?(Ecto.Changeset, :cast, 3)
      assert function_exported?(Ecto.Changeset, :change, 2)
      assert function_exported?(Ecto.Changeset, :validate_required, 2)
      assert function_exported?(Ecto.Query.Planner, :query, 6)
      assert function_exported?(Ecto.Query.Planner, :new_query_cache, 1)
      assert function_exported?(Ecto.Query.API, :json_extract_path, 2)
      assert function_exported?(Ecto.Query.API, :splice, 1)
    end

    test "app code does not interpolate JSON paths or splice/1" do
      sources =
        @lib_dir
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.map(&File.read!/1)
        |> Enum.join("\n")

      refute sources =~ "json_extract_path"
      refute sources =~ "splice("
      refute sources =~ ~s|field[^|

      assert File.read!(Path.join(@lib_dir, "query_console/runner/worker.ex")) =~
               "AnalyticsRepo.query(sql, [], timeout: timeout)"
    end
  end

  describe "3.14.3 changelog" do
    test "documents the query-cache CVE and related planner fixes" do
      changelog = File.read!(@changelog)

      v3143 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "v3.14.3"))

      assert v3143
      assert v3143 =~ "CVE-2026-118391"
      assert v3143 =~ "interpolated JSON paths"
      assert v3143 =~ "splice/1"
      assert v3143 =~ "constant/1"
      assert v3143 =~ "join"
      assert v3143 =~ "or_where"
      refute v3143 =~ "Breaking"
    end
  end

  describe "3.14.3 planner and builder source" do
    test "interpolated JSON paths are stored as :inline params" do
      builder = File.read!(@builder)
      planner = File.read!(@planner)

      assert builder =~ "Interpolated JSON paths are stored as parameters of type :inline"
      assert builder =~ "{[{path, :inline} | params], acc}"
      assert builder =~ "{[{element, :inline} | params], acc}"

      assert planner =~ "{_value, :inline}, {acc, _cacheable?} ->"
      assert planner =~ "{acc, false}"
      assert planner =~ "defp inline_json_path({:^, _, [ix]}, expr) do"
      assert planner =~ "{path, :inline} = Enum.fetch!(expr.params, ix)"
    end

    test "interpolated splice/1 is uncacheable like :in lists" do
      planner = File.read!(@planner)
      api = File.read!(@api)

      assert planner =~
               ~S|{cast_v, {:splice, dump_v}} -> {split_variadic_params(cast_v, dump_v, acc), false}|

      refute planner =~
               ~S|{cast_v, {:splice, dump_v}} -> {split_variadic_params(cast_v, dump_v, acc), cacheable?}|

      assert api =~ "queries with\n  interpolated splices are not cached"
    end

    test "join prefixes and hints are part of the cache key" do
      planner = File.read!(@planner)

      assert planner =~ "# Store the planned prefix in the join, as it is part of the cache key"
      assert planner =~ "{{qual, key, on.expr, hints},"
      assert planner =~ "defp source_cache(%{source: {bin, schema}, prefix: prefix}, params),"
      assert planner =~ "{{bin, schema, schema.__schema__(:hash), prefix}, params}"
    end

    test "runtime true filters stay when a later or_where depends on them" do
      filter = File.read!(@filter)

      assert filter =~ "later `or_where`/`or_having`"
      assert filter =~ "defp add_filter([_ | _] = exprs, %{expr: true, op: :and}),"
      assert filter =~ "do: exprs"
    end
  end

  describe "EEF-CVE-2026-118391 query cache" do
    test "plain equality queries are still cached" do
      query = from(u in User, where: u.email == ^"plain@example.com", select: u.id)
      assert {:cache, 1} = plan_kind(query)
    end

    test "literal JSON paths stay cacheable" do
      query =
        from(s in SchemaSnapshot,
          where: json_extract_path(s.payload, ["color"]) == ^"blue",
          select: s.id
        )

      assert {:cache, 1} = plan_kind(query)
    end

    test "interpolated JSON paths are not cached" do
      key = "color"

      query =
        from(s in SchemaSnapshot,
          where: json_extract_path(s.payload, ^[key]) == ^"blue",
          select: s.id
        )

      assert {:nocache, 0} = plan_kind(query)
    end

    test "interpolated JSON path elements via Access are not cached" do
      key = "color"

      query =
        from(s in SchemaSnapshot,
          where: s.payload[^key] == ^"blue",
          select: s.id
        )

      assert {:nocache, 0} = plan_kind(query)
    end

    test "distinct interpolated JSON keys do not grow the cache" do
      cache = new_plan_cache()

      for key <- ["a", "b", "c", "d", "e"] do
        query =
          from(s in SchemaSnapshot,
            where: json_extract_path(s.payload, ^[key]) == ^"x",
            select: s.id
          )

        assert {:nocache, _} = plan_kind(query, cache)
      end

      assert :ets.info(cache, :size) == 0
    end

    test "interpolated splice/1 is not cached" do
      emails = ["one@example.com", "two@example.com"]

      query =
        from(u in User,
          where: fragment("? IN (?)", u.email, splice(^emails)),
          select: u.id
        )

      assert {:nocache, 0} = plan_kind(query)
    end

    test "distinct splice lengths do not grow the cache" do
      cache = new_plan_cache()

      for n <- 1..8 do
        emails = Enum.map(1..n, &"user#{&1}@example.com")

        query =
          from(u in User,
            where: fragment("? IN (?)", u.email, splice(^emails)),
            select: u.id
          )

        assert {:nocache, _} = plan_kind(query, cache)
      end

      assert :ets.info(cache, :size) == 0
    end
  end

  describe "Query Console schemas still round-trip on 3.14.3" do
    test "json_extract_path on SchemaSnapshot.payload still filters" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      %SchemaSnapshot{}
      |> Ecto.Changeset.change(%{
        version: System.unique_integer([:positive]),
        payload: %{"color" => "blue", "size" => "large"},
        inserted_at: now
      })
      |> Repo.insert!()

      key = "color"

      assert Repo.one(
               from(s in SchemaSnapshot,
                 where: json_extract_path(s.payload, ^[key]) == ^"blue",
                 select: s.payload["size"]
               )
             ) == "large"
    end

    test "user timestamps, get, and list still work" do
      user = user_fixture(%{email: "ecto-upgrade@example.com"})

      assert %DateTime{} = user.inserted_at
      assert %DateTime{} = user.updated_at
      assert Repo.get(User, user.id).email == "ecto-upgrade@example.com"

      assert Enum.any?(Repo.all(from(u in User, order_by: [asc: u.email])), fn row ->
               row.id == user.id
             end)
    end

    test "query_cache: false still runs a cacheable query" do
      user = user_fixture()

      assert [%User{id: id}] =
               Repo.all(from(u in User, where: u.id == ^user.id), query_cache: false)

      assert id == user.id
    end
  end

  defp new_plan_cache do
    :ets.new(:ecto_upgrade_test_cache, [:set, :public])
  end

  defp plan_kind(query, cache \\ new_plan_cache()) do
    query =
      query
      |> Ecto.Queryable.to_query()
      |> Ecto.Query.Planner.ensure_select(true)

    {_meta, prepared, _cast_params, _dump_params} =
      Ecto.Query.Planner.query(query, :all, cache, Ecto.Adapters.Postgres, 0, true)

    kind =
      case prepared do
        {:nocache, _} -> :nocache
        {:cache, _, _} -> :cache
        {:cached, _, _, _} -> :cached
      end

    {kind, :ets.info(cache, :size)}
  end
end
