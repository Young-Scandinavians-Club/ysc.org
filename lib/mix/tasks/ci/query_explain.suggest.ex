defmodule Mix.Tasks.Ci.QueryExplain.Suggest do
  @moduledoc """
  Lists `lib/**/*.ex` modules that contain query-shaped code but lack CI explain targets.

  Scans for `from(`, `join(`, and similar patterns, then reports modules with no
  auto-discoverable `*_query` / `base_query` function and no registered target in
  `priv/ci/query_explain_targets.exs`.

  ## Examples

      mix ci.query_explain.suggest
      mix ci.query_explain.suggest lib/ysc/tickets/booking_locker.ex
  """

  use Mix.Task

  alias Ysc.Ci.QueryExplain.Discovery

  @shortdoc "Suggest modules that need query EXPLAIN CI targets"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.config")
    Mix.Task.run("app.start")

    paths =
      case argv do
        [] -> all_lib_ex_paths()
        files -> files
      end

    registry_modules = registered_modules()

    paths
    |> Enum.filter(&Discovery.elixir_source_path?/1)
    |> Enum.filter(&Discovery.file_has_query_shape?/1)
    |> Enum.flat_map(fn path ->
      path
      |> Discovery.modules_in_file()
      |> Enum.map(&{path, &1})
    end)
    |> Enum.uniq_by(fn {_path, module} -> module end)
    |> Enum.reject(fn {_path, module} ->
      covered_by_discovery?(module) or MapSet.member?(registry_modules, module)
    end)
    |> Enum.sort_by(fn {path, module} -> {path, module} end)
    |> print_suggestions()
  end

  defp all_lib_ex_paths do
    "lib/**/*.ex"
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp registered_modules do
    registry_path = Path.join(File.cwd!(), "priv/ci/query_explain_targets.exs")

    case Code.eval_file(registry_path) do
      {targets, _} when is_list(targets) ->
        targets
        |> Enum.map(fn t -> t |> Map.fetch!(:mfa) |> elem(0) end)
        |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end

  defp covered_by_discovery?(module) do
    Discovery.query_functions_for_module(module) != []
  end

  defp print_suggestions([]) do
    Mix.shell().info(
      "All scanned modules have CI explain coverage or discoverable *_query functions."
    )
  end

  defp print_suggestions(rows) do
    Mix.shell().info(
      "Modules with query-shaped code but no CI explain target (#{length(rows)}):\n"
    )

    Enum.each(rows, fn {path, module} ->
      Mix.shell().info("  #{path}  (#{inspect(module)})")
    end)

    Mix.shell().info("""

    Next steps:
      1. Extract queries into public *_query/0 or *_query(opts \\\\ []) functions returning %Ecto.Query{}
      2. Or add a fixture wrapper in lib/ysc/ci/query_explain.ex
      3. Register cross-file triggers in priv/ci/query_explain_targets.exs

    See docs/QUERY_EXPLAIN_CI.md
    """)
  end
end
