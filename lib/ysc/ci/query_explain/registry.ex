defmodule Ysc.Ci.QueryExplain.Registry do
  @moduledoc false

  alias Ysc.Ci.QueryExplain.Discovery

  @ysc_prefix "lib/ysc/"
  @skip_paths MapSet.new([
                "lib/ysc/ci/query_explain/discovery.ex"
              ])

  @doc false
  def all_targets do
    key = {__MODULE__, :all_targets}

    case :persistent_term.get(key, :miss) do
      :miss ->
        targets = build_all_targets()
        :persistent_term.put(key, targets)
        targets

      targets when is_list(targets) ->
        targets
    end
  end

  defp build_all_targets do
    load_ysc_modules!()

    lib_ysc_paths()
    |> Enum.flat_map(&targets_for_path/1)
    |> Enum.concat(extra_targets())
    |> Enum.uniq_by(&target_key/1)
    |> Enum.sort_by(&Map.fetch!(&1, :id))
  end

  @doc false
  def lib_ysc_scope?(changed) when changed == :all, do: false

  def lib_ysc_scope?(changed) do
    changed
    |> Enum.any?(fn path ->
      String.starts_with?(path, @ysc_prefix) and
        not MapSet.member?(@skip_paths, path)
    end)
  end

  @doc false
  def ysc_target?(target) do
    {module, _function, _args} = Map.fetch!(target, :mfa)

    case Module.split(module) do
      ["Ysc" | _] -> true
      _ -> ysc_source_paths?(Map.fetch!(target, :source_paths))
    end
  end

  @doc false
  def lib_ysc_paths do
    (@ysc_prefix <> "**/*.ex")
    |> Path.wildcard()
    |> Enum.reject(&MapSet.member?(@skip_paths, &1))
    |> Enum.sort()
  end

  defp targets_for_path(path) do
    path
    |> Discovery.modules_in_file()
    |> Enum.flat_map(fn module ->
      module
      |> Discovery.query_functions_for_module()
      |> Enum.map(&registered_target(module, &1, path))
    end)
  end

  defp registered_target(module, function, path) do
    id =
      [
        module |> Module.split() |> Enum.map_join("_", &Macro.underscore/1),
        function
      ]
      |> Enum.join("_")
      |> Macro.underscore()

    %{
      id: id,
      source_paths: [path],
      mfa: {module, function, []},
      discovered: false
    }
  end

  defp extra_targets do
    [
      %{
        id: "ticket_orders_pending_timeout",
        source_paths: [
          "lib/ysc/ci/query_explain.ex",
          "lib/ysc/tickets/timeout_worker.ex"
        ],
        mfa:
          {Ysc.Ci.QueryExplain, :ticket_orders_pending_timeout_batch_query, []}
      }
    ]
  end

  defp ysc_source_paths?(paths) do
    Enum.any?(paths, &String.starts_with?(&1, @ysc_prefix))
  end

  defp target_key(target) do
    {module, function, args} = Map.fetch!(target, :mfa)
    {module, function, length(args)}
  end

  defp load_ysc_modules! do
    lib_ysc_paths()
    |> Enum.flat_map(&Discovery.modules_in_file/1)
    |> Enum.uniq()
    |> Enum.each(fn module ->
      Code.ensure_loaded(module)
    end)
  end
end
