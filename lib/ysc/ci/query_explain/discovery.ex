defmodule Ysc.Ci.QueryExplain.Discovery do
  @moduledoc false

  @query_shape_pattern ~r/\bfrom\s*\(|\bfrom\s+\w+\s+in\b|\bjoin\s*\(|\bjoin\s+\w+\s+in\b|dynamic\s*\(|fragment\s*\(|subquery\s*\(|union_all\s*\(|\bexcept\s*\(|\bintersect\s*\(/

  @doc false
  def discoverable_query_name?(name) when is_atom(name) do
    name == :base_query or String.ends_with?(Atom.to_string(name), "_query")
  end

  @doc false
  def query_functions_for_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      module
      |> function_names()
      |> Enum.filter(fn name ->
        discoverable_query_name?(name) and
          callable_query_function?(module, name)
      end)
      |> Enum.sort()
    else
      []
    end
  end

  @doc false
  def callable_query_function?(module, function)
      when is_atom(module) and is_atom(function) do
    query = apply(module, function, [])
    match?(%Ecto.Query{}, query)
  rescue
    _ -> false
  end

  @doc false
  def modules_in_file(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(contents) do
      ast
      |> collect_modules(nil)
      |> Enum.uniq()
    else
      _ -> []
    end
  end

  defp collect_modules({:defmodule, _, [alias_node, [do: body]]}, parent) do
    module = expand_module_alias(alias_node, parent)
    [module | collect_modules(body, module)]
  end

  defp collect_modules({:defmodule, _, [alias_node, body]}, parent)
       when is_list(body) do
    module = expand_module_alias(alias_node, parent)
    [module | Enum.flat_map(body, &collect_modules(&1, module))]
  end

  defp collect_modules({_, _, args}, parent) when is_list(args) do
    Enum.flat_map(args, &collect_modules(&1, parent))
  end

  defp collect_modules(list, parent) when is_list(list) do
    Enum.flat_map(list, &collect_modules(&1, parent))
  end

  defp collect_modules(_other, _parent), do: []

  defp expand_module_alias({:__aliases__, _, parts}, nil),
    do: Module.concat(parts)

  defp expand_module_alias({:__aliases__, _, parts}, parent),
    do: Module.concat([parent | parts])

  @doc false
  def elixir_source_path?(path) when is_binary(path) do
    String.starts_with?(path, "lib/") and String.ends_with?(path, ".ex")
  end

  @doc false
  def file_has_query_shape?(path) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} -> Regex.match?(@query_shape_pattern, contents)
      {:error, _} -> false
    end
  end

  @doc false
  def auto_targets_for_file(path) when is_binary(path) do
    path
    |> modules_in_file()
    |> Enum.flat_map(fn module ->
      module
      |> query_functions_for_module()
      |> Enum.map(&auto_target(module, &1, path))
    end)
  end

  @doc false
  def auto_target(module, function, path) do
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

  defp function_names(module) do
    module.__info__(:functions)
    |> Enum.map(fn {name, _arity} -> name end)
    |> Enum.uniq()
  end
end
