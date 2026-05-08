defmodule Mix.Tasks.Ci.QueryExplain do
  @moduledoc """
  Runs `Ecto.Adapters.SQL.to_sql/3` and `Repo.explain/3` for CI query targets.

  Explicit targets live in `priv/ci/query_explain_targets.exs`. With
  `--changed-files`, only explicit targets whose `source_paths` intersect that
  file list are run. The task also auto-discovers public zero-arity functions
  ending in `_query` from changed modules and runs any that return `%Ecto.Query{}`.

  ## Examples

      mix ci.query_explain --all-targets --output-json /tmp/out.json --output-markdown /tmp/out.md

      mix ci.query_explain --changed-files /tmp/changed.txt --heuristic-matched \\
        --output-json /tmp/out.json --output-markdown /tmp/out.md

  Before starting the app, this task runs `ecto.create` and `ecto.migrate` (quiet) so
  the database matches the current code (e.g. Oban migration version). Use `MIX_ENV=test`
  when pointing at your test database.
  """

  use Mix.Task

  @shortdoc "Dump SQL + EXPLAIN for CI query explain targets"

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          changed_files: :string,
          output_json: :string,
          output_markdown: :string,
          heuristic_matched: :boolean,
          all_targets: :boolean
        ],
        aliases: [o: :output_json]
      )

    changed_files_path = opts[:changed_files]
    output_json = opts[:output_json]
    output_markdown = opts[:output_markdown]
    heuristic_matched? = opts[:heuristic_matched] == true
    all_targets? = opts[:all_targets] == true

    unless output_json && output_markdown do
      Mix.raise("--output-json and --output-markdown are required")
    end

    Mix.Task.run("app.config")
    Mix.Task.run("ecto.create", ["--quiet"])
    Mix.Task.run("ecto.migrate", ["--quiet"])
    Mix.Task.run("app.start")

    changed =
      cond do
        all_targets? ->
          :all

        is_binary(changed_files_path) ->
          changed_files_path
          |> File.read!()
          |> String.split("\n", trim: true)
          |> MapSet.new()

        true ->
          Mix.raise("Pass --changed-files PATH or --all-targets")
      end

    registry_path =
      Path.join(File.cwd!(), "priv/ci/query_explain_targets.exs")

    targets =
      try do
        case Code.eval_file(registry_path) do
          {result, _} ->
            if is_list(result) do
              result
            else
              Mix.raise(
                "expected list from #{registry_path}, got: #{inspect(result)}"
              )
            end
        end
      rescue
        e in Mix.Error ->
          reraise(e, __STACKTRACE__)

        e ->
          Mix.raise(
            "failed to evaluate query explain registry at #{registry_path}: " <>
              Exception.message(e) <>
              "\n" <>
              Exception.format_stacktrace(__STACKTRACE__)
          )
      end

    explicit_selected =
      if changed == :all do
        targets
      else
        Enum.filter(targets, fn t ->
          paths = Map.fetch!(t, :source_paths)
          Enum.any?(paths, &MapSet.member?(changed, &1))
        end)
      end

    selected =
      (explicit_selected ++ auto_discovered_targets(changed))
      |> Enum.uniq_by(&target_key/1)

    suggest? = heuristic_matched? and selected == [] and not all_targets?

    results =
      Enum.map(selected, fn t ->
        id = Map.fetch!(t, :id)
        {m, f, a} = Map.fetch!(t, :mfa)

        try do
          query = apply(m, f, a)

          unless match?(%Ecto.Query{}, query) do
            raise "expected %Ecto.Query{}, got #{inspect(query)}"
          end

          {sql, _params} = Ecto.Adapters.SQL.to_sql(:all, Ysc.Repo, query)

          plan =
            Ysc.Repo.explain(:all, query,
              analyze: false,
              timeout: 60_000
            )

          %{
            "id" => id,
            "mfa" => Exception.format_mfa(m, f, length(a)),
            "source_paths" => Map.fetch!(t, :source_paths),
            "discovered" => Map.get(t, :discovered, false),
            "sql" => sql,
            "plan" => plan,
            "error" => nil
          }
        rescue
          e ->
            %{
              "id" => id,
              "mfa" => Exception.format_mfa(m, f, length(a)),
              "source_paths" => Map.fetch!(t, :source_paths),
              "discovered" => Map.get(t, :discovered, false),
              "sql" => nil,
              "plan" => nil,
              "error" => Exception.message(e)
            }
        end
      end)

    payload = %{
      "version" => 1,
      "suggest_registry_opt_in" => suggest?,
      "targets" => results
    }

    File.write!(output_json, Jason.encode!(payload, pretty: true))
    File.write!(output_markdown, build_markdown(payload))
  end

  defp build_markdown(payload) do
    targets = Map.fetch!(payload, "targets")
    suggest? = Map.fetch!(payload, "suggest_registry_opt_in")

    sha = System.get_env("GITHUB_SHA", "local")
    base = System.get_env("GITHUB_BASE_REF", "")

    meta_lines =
      [
        "- Commit: `#{sha}`",
        if(base != "", do: "- Base ref: `#{base}`", else: nil),
        "- Targets run: **#{length(targets)}**"
      ]
      |> Enum.reject(&is_nil/1)

    header =
      [
        "<!-- ci-query-explain -->",
        "## Query EXPLAIN (CI)",
        "",
        "_This comment is updated by GitHub Actions on each push._",
        ""
      ]
      |> Enum.concat(meta_lines)
      |> Enum.concat([""])
      |> Enum.join("\n")

    opt_in =
      if suggest? do
        """
        Query-shaped changes were detected in this PR, but no registered or auto-discovered explain targets matched the changed files.

        Auto-discovery runs public zero-arity `*_query` functions from changed modules when they return `%Ecto.Query{}`. For queries that need arguments or live behind side-effecting functions, add or extend a row in `priv/ci/query_explain_targets.exs` and point `source_paths` at the modules you care about.

        """
      else
        ""
      end

    sections = Enum.map_join(targets, "\n", &section_for_target/1)

    header <> opt_in <> sections
  end

  defp auto_discovered_targets(:all), do: []

  defp auto_discovered_targets(changed) do
    changed
    |> Enum.filter(&changed_elixir_source?/1)
    |> Enum.flat_map(&auto_discovered_targets_for_file/1)
  end

  defp changed_elixir_source?(path) do
    String.starts_with?(path, "lib/") and String.ends_with?(path, ".ex")
  end

  defp auto_discovered_targets_for_file(path) do
    path
    |> modules_in_file()
    |> Enum.flat_map(fn module ->
      if Code.ensure_loaded?(module) do
        module
        |> module_query_functions()
        |> Enum.map(&auto_target(module, &1, path))
      else
        []
      end
    end)
  end

  defp modules_in_file(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(contents) do
      {_ast, modules} =
        Macro.prewalk(ast, [], fn
          {:defmodule, _, [{:__aliases__, _, parts}, _body]} = node, acc ->
            {node, [Module.concat(parts) | acc]}

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(modules)
    else
      _ -> []
    end
  end

  defp module_query_functions(module) do
    module.__info__(:functions)
    |> Enum.filter(fn {name, arity} ->
      arity == 0 and String.ends_with?(Atom.to_string(name), "_query") and
        query_function?(module, name)
    end)
    |> Enum.map(fn {name, 0} -> name end)
    |> Enum.sort()
  end

  defp query_function?(module, function) do
    query = apply(module, function, [])
    match?(%Ecto.Query{}, query)
  rescue
    _ -> false
  end

  defp auto_target(module, function, path) do
    id =
      [
        module |> Module.split() |> Enum.map_join("_", &Macro.underscore/1),
        function
      ]
      |> Enum.join("_")
      |> Macro.underscore()

    %{
      id: "auto_#{id}",
      source_paths: [path],
      mfa: {module, function, []},
      discovered: true
    }
  end

  defp target_key(t) do
    {module, function, args} = Map.fetch!(t, :mfa)
    {module, function, length(args)}
  end

  defp section_for_target(%{"error" => err} = t) when is_binary(err) do
    id = Map.fetch!(t, "id")

    """
    ### `#{id}`

    **Error:** #{err}

    """
  end

  defp section_for_target(t) do
    id = Map.fetch!(t, "id")
    sql = Map.fetch!(t, "sql")
    plan = Map.fetch!(t, "plan")
    mfa = Map.fetch!(t, "mfa")
    paths = Map.fetch!(t, "source_paths") |> Enum.join(", ")
    discovered? = Map.get(t, "discovered", false)
    source = if discovered?, do: "auto-discovered", else: "registered"

    """
    ### `#{id}`

    - **MFA:** `#{mfa}`
    - **Source:** #{source}
    - **Watched paths:** #{paths}

    <details>
    <summary>SQL</summary>

    ```sql
    #{sql}
    ```

    </details>

    <details>
    <summary>EXPLAIN</summary>

    ```text
    #{plan}
    ```

    </details>

    """
  end
end
