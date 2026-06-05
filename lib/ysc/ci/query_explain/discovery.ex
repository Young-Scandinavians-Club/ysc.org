defmodule Ysc.Ci.QueryExplain.Discovery do
  @moduledoc false

  @query_shape_pattern ~r/\bfrom\s*\(|\bjoin\s*\(|dynamic\s*\(|fragment\s*\(|subquery\s*\(|union_all\s*\(|\bexcept\s*\(|\bintersect\s*\(/

  @doc false
  def discoverable_query_name?(name) when is_atom(name) do
    name == :base_query or String.ends_with?(Atom.to_string(name), "_query")
  end

  @doc false
  def query_functions_for_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      module
      |> function_names()
      |> Enum.filter(&discoverable_query_name?/1)
      |> Enum.filter(&callable_query_function?(module, &1))
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
