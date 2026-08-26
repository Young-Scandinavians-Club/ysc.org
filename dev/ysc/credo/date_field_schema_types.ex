defmodule Ysc.Credo.DateFieldSchemaTypes do
  use Credo.Check,
    id: "EX9003",
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{included: ["lib/ysc/**/*.ex"]}
    ],
    explanations: [
      check: """
      Ambiguous date/time field names must be declared with `Ysc.Ecto.DateKind`
      so timezone conversion is part of the field configuration.

      `start_date` means a California calendar day on `Ysc.Events.Event`, a
      Pacific-anchored sale window on `Ysc.Events.TicketTier`, and a UTC instant
      on `Ysc.Subscriptions.Subscription`. A bare `:utc_datetime` cannot tell
      those apart.

          # BAD
          field :start_date, :utc_datetime

          # GOOD
          field :start_date, Ysc.Ecto.DateKind, kind: :california_calendar_datetime

      Required names: `start_date`, `end_date`, `checkin_date`, `checkout_date`,
      `start_time`, `end_time`, `published_on`, `day`, `current_period_start`,
      `current_period_end`.

      See `Ysc.Ecto.DateKind` for the kind list and `mix credo explain EX9004`
      for conversion rules.
      """
    ]

  alias Ysc.DateFields
  alias Ysc.Ecto.DateKind

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    {_ast, {issues, _aliases}} =
      source_file
      |> Credo.SourceFile.ast()
      |> Macro.prewalk({[], %{}}, &traverse(&1, &2, issue_meta))

    Enum.reverse(issues)
  end

  defp traverse({:alias, _, args} = ast, {issues, aliases}, _issue_meta) do
    {ast, {issues, merge_alias(aliases, args)}}
  end

  defp traverse(
         {:field, meta, [name | rest]} = ast,
         {issues, aliases},
         issue_meta
       )
       when is_atom(name) do
    if name in DateFields.required_field_names() do
      {type_ast, opts_ast} = field_type_and_opts(rest)

      case classified_kind(type_ast, opts_ast, aliases) do
        {:ok, _kind} ->
          {ast, {issues, aliases}}

        {:error, message} ->
          issue =
            format_issue(issue_meta,
              message: message,
              trigger: inspect(name),
              line_no: meta[:line]
            )

          {ast, {[issue | issues], aliases}}
      end
    else
      {ast, {issues, aliases}}
    end
  end

  defp traverse(ast, acc, _issue_meta), do: {ast, acc}

  defp field_type_and_opts([type_ast]), do: {type_ast, []}
  defp field_type_and_opts([type_ast, opts_ast]), do: {type_ast, opts_ast}
  defp field_type_and_opts(_), do: {nil, []}

  defp classified_kind(type_ast, opts_ast, aliases) do
    cond do
      date_kind_type?(type_ast, aliases) ->
        case kind_from_opts(opts_ast) do
          nil ->
            {:error,
             "Ysc.Ecto.DateKind field is missing `kind:`. " <>
               "Example: field :start_date, Ysc.Ecto.DateKind, kind: :california_calendar_datetime. " <>
               "See `mix credo explain #{id()}`."}

          kind ->
            if DateKind.valid_kind?(kind) do
              {:ok, kind}
            else
              {:error,
               "Unknown Ysc.Ecto.DateKind kind #{inspect(kind)}. " <>
                 "Valid kinds: #{DateKind.kinds() |> Enum.sort() |> Enum.map_join(", ", &inspect/1)}."}
            end
        end

      primitive_date_type?(type_ast) ->
        {:error,
         "Field must use `Ysc.Ecto.DateKind, kind: :…` instead of #{inspect_type(type_ast)}. " <>
           "Timezone conversion is part of the field configuration. " <>
           "See `mix credo explain #{id()}`."}

      true ->
        {:error,
         "Field must use `Ysc.Ecto.DateKind, kind: :…` so timezone conversion " <>
           "can be linted. See `mix credo explain #{id()}`."}
    end
  end

  defp date_kind_type?({:__aliases__, _, parts}, aliases) do
    expand_alias(parts, aliases) == [:Ysc, :Ecto, :DateKind]
  end

  defp date_kind_type?(_, _), do: false

  defp primitive_date_type?(type)
       when type in [:utc_datetime, :date, :time, :utc_datetime_usec],
       do: true

  defp primitive_date_type?({:__aliases__, _, [:Date]}), do: true
  defp primitive_date_type?({:__aliases__, _, [:Time]}), do: true
  defp primitive_date_type?({:__aliases__, _, [:DateTime]}), do: true
  defp primitive_date_type?(_), do: false

  defp kind_from_opts(opts) when is_list(opts) do
    case Keyword.get(opts, :kind) do
      kind when is_atom(kind) -> kind
      _ -> nil
    end
  end

  defp kind_from_opts(_), do: nil

  defp inspect_type(type) when is_atom(type), do: inspect(type)

  defp inspect_type({:__aliases__, _, parts}),
    do: Enum.map_join(parts, ".", &to_string/1)

  defp inspect_type(_), do: "this type"

  defp merge_alias(aliases, [{:__aliases__, _, parts}]) do
    Map.put(aliases, List.last(parts), parts)
  end

  defp merge_alias(aliases, [
         {:__aliases__, _, parts},
         [as: {:__aliases__, _, [as]}]
       ]) do
    Map.put(aliases, as, parts)
  end

  defp merge_alias(aliases, _), do: aliases

  defp expand_alias([head | rest], aliases) do
    case Map.get(aliases, head) do
      nil -> [head | rest]
      prefix -> prefix ++ rest
    end
  end

  defp expand_alias(parts, _), do: parts
end
