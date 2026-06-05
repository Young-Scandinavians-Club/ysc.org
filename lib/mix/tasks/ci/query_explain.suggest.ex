defmodule Mix.Tasks.Ci.QueryExplain.Suggest do
  @moduledoc """
  Lists `lib/ysc/**/*.ex` modules that contain query-shaped code but lack CI explain
  targets (`ci_query_explain_query/0`, other `*_query`, or `base_query/0`).

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

    paths
    |> Enum.filter(fn path ->
      Discovery.elixir_source_path?(path) and
        Discovery.file_has_query_shape?(path)
    end)
    |> Enum.flat_map(fn path ->
      path
      |> Discovery.modules_in_file()
      |> Enum.map(&{path, &1})
    end)
    |> Enum.uniq_by(fn {_path, module} -> module end)
    |> Enum.reject(fn {_path, module} -> covered_by_discovery?(module) end)
    |> Enum.sort_by(fn {path, module} -> {path, module} end)
    |> print_suggestions()
  end

  defp all_lib_ex_paths do
    Ysc.Ci.QueryExplain.Registry.lib_ysc_paths()
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
      1. Add ci_query_explain_query/0 returning %Ecto.Query{} (use Ysc.Ci.QueryExplain.Fixtures)
      2. Or add *_query/0 with defaults / base_query/0 if more appropriate

    See docs/QUERY_EXPLAIN_CI.md
    """)
  end
end
