defmodule Ysc.Credo.DateFieldConversions do
  use Credo.Check,
    id: "EX9004",
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{
        included: ["lib/**/*.{ex,exs}"],
        excluded: [
          "lib/ysc/ecto/date_kind.ex",
          "lib/ysc/date_fields.ex",
          "lib/ysc_web/date_display.ex"
        ]
      }
    ],
    explanations: [
      check: """
      Do not mix timezone conversions across `Ysc.Ecto.DateKind` kinds.

      The kind is configured on the schema field. This check uses the
      conventional receiver name (`event`, `booking`, `ticket_tier`, …) plus
      `schema.__schema__(:type, field)` to decide what is legal.

      ## Never `shift_zone` (California calendar days / Pacific wall-clock)

      Event `start_date` / `end_date`, cabin `checkin_date` / `checkout_date`,
      and event `start_time` / `end_time`. Use `DateTime.to_date/1` (or
      `YscWeb.DateDisplay.calendar_date/1`) without shifting. Midnight UTC of
      Aug 28 is August 28, not the previous evening in Pacific time.

          # BAD
          event.start_date
          |> DateTime.shift_zone!("America/Los_Angeles")
          |> DateTime.to_date()

          DateDisplay.format_date_in_zone(event.start_date, @timezone)

          # GOOD
          DateDisplay.format_event_date_range(event)
          DateDisplay.days_until_event(event)

      ## Shift to Pacific (sale windows)

      Ticket-tier `start_date` / `end_date` are real UTC instants picked as
      Pacific days. Use `format_pacific_date/1` / `format_sale_window_range/2`.
      Raw `shift_zone` is allowed only when the zone is Pacific
      (`"America/Los_Angeles"` or `TimeZone.default()`), not `@timezone`.

      ## Shift to the browser timezone (UTC instants)

      `published_on`, membership period ends, payments. Use
      `format_date_in_zone/2` with `@timezone`.

      See `Ysc.Ecto.DateKind` and `mix credo explain EX9003`.
      """
    ]

  alias Ysc.DateFields
  alias Ysc.Ecto.DateKind
  alias YscWeb.TimeZone

  @shift_funs MapSet.new([:shift_zone, :shift_zone!, :shift])

  @never_formatters MapSet.new([
                      :format_date_in_zone,
                      :format_date_short_in_zone,
                      :format_in_zone,
                      :format_pacific_date,
                      :format_pacific_date_short,
                      :format_sale_window_range
                    ])

  @pacific_browser_formatters MapSet.new([
                                :format_date_in_zone,
                                :format_date_short_in_zone,
                                :format_in_zone,
                                :format_event_date_range
                              ])

  @browser_event_formatters MapSet.new([
                              :format_event_date_range,
                              :format_sale_window_range,
                              :days_until_event,
                              :event_day_label
                            ])

  # Every formatter this check has an opinion about — anything named in one of
  # the kind-specific sets above. Deriving this instead of listing it a fourth
  # time means adding a formatter to any one set is enough to make `traverse/3`
  # actually look at its calls; a name present in `forbidden_formatter?/2` but
  # missing here would otherwise be silently skipped.
  @formatter_funs MapSet.union(@never_formatters, @pacific_browser_formatters)
                  |> MapSet.union(@browser_event_formatters)

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    {issues, _bindings} =
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta), {[], %{}})

    Enum.reverse(issues)
  end

  # Bindings are function-local. Reset them on every def/defp so a variable
  # name bound inside one function (see the :case clause below) can't leak
  # into an unrelated same-named local variable in a later function.
  defp traverse(
         {def_kind, _, _} = ast,
         {issues, _bindings},
         _issue_meta
       )
       when def_kind in [:def, :defp] do
    {ast, {issues, %{}}}
  end

  # case event.start_date do
  #   nil -> nil
  #   start_date -> start_date |> ...
  # end
  #
  # Binds a bare-variable case clause pattern back to the field its subject
  # resolved from, so a later reference to the plain variable (not the
  # `receiver.field` expression) is still recognized as that DateKind field.
  defp traverse(
         {:case, _, [subject, [do: clauses]]} = ast,
         {issues, bindings},
         _issue_meta
       )
       when is_list(clauses) do
    bindings =
      case field_access(subject, bindings) do
        nil ->
          bindings

        field_ref ->
          Enum.reduce(clauses, bindings, fn
            {:->, _, [[{name, _, ctx}], _body]}, acc
            when is_atom(name) and name != :_ and (is_nil(ctx) or is_atom(ctx)) ->
              Map.put(acc, name, field_ref)

            _clause, acc ->
              acc
          end)
      end

    {ast, {issues, bindings}}
  end

  # event.start_date |> DateTime.shift_zone!(tz)
  defp traverse(
         {:|>, meta, [left, {{:., _, [_, fun]}, _, args}]} = ast,
         {issues, bindings},
         issue_meta
       )
       when fun in [:shift_zone, :shift_zone!, :shift] do
    issues =
      maybe_shift_issue(left, List.first(args), meta, issue_meta, issues, bindings)

    {ast, {issues, bindings}}
  end

  # DateTime.shift_zone!(event.start_date, tz)
  defp traverse(
         {{:., _, [_, fun]}, meta, [value | rest]} = ast,
         {issues, bindings},
         issue_meta
       )
       when fun in [:shift_zone, :shift_zone!, :shift] do
    issues =
      maybe_shift_issue(
        value,
        List.first(rest),
        meta,
        issue_meta,
        issues,
        bindings
      )

    {ast, {issues, bindings}}
  end

  # DateDisplay.format_date_in_zone(event.start_date, tz)
  # DateDisplay.days_until_event(event, tz)
  defp traverse(
         {{:., _, [_, fun]}, meta, [value | rest]} = ast,
         {issues, bindings},
         issue_meta
       )
       when is_atom(fun) do
    issues =
      if fun in @formatter_funs do
        maybe_formatter_issue(fun, value, rest, meta, issue_meta, issues, bindings)
      else
        issues
      end

    {ast, {issues, bindings}}
  end

  defp traverse(ast, acc, _issue_meta), do: {ast, acc}

  defp maybe_shift_issue(value, timezone_arg, meta, issue_meta, issues, bindings) do
    case field_kind(value, bindings) do
      {schema, field, kind} ->
        case DateKind.shift_zone_policy(kind) do
          :never ->
            [
              issue(
                issue_meta,
                meta,
                field,
                "Do not shift_zone #{inspect(schema)}.#{field} " <>
                  "(#{kind}; #{DateKind.display_hint(kind)}). " <>
                  "See `mix credo explain #{id()}`."
              )
              | issues
            ]

          :pacific ->
            if pacific_timezone_arg?(timezone_arg) do
              issues
            else
              [
                issue(
                  issue_meta,
                  meta,
                  field,
                  "Shift #{inspect(schema)}.#{field} only to Pacific time " <>
                    "(#{kind}; #{DateKind.display_hint(kind)}). " <>
                    "Do not use the browser timezone. See `mix credo explain #{id()}`."
                )
                | issues
              ]
            end

          _ ->
            issues
        end

      _ ->
        issues
    end
  end

  defp pacific_timezone_arg?(literal) when is_binary(literal),
    do: literal == TimeZone.default()

  defp pacific_timezone_arg?(
         {{:., _, [{:__aliases__, _, parts}, :default]}, _, []}
       )
       when parts in [[:TimeZone], [:YscWeb, :TimeZone]],
       do: true

  defp pacific_timezone_arg?(_), do: false

  defp maybe_formatter_issue(fun, value, rest, meta, issue_meta, issues, bindings) do
    cond do
      fun in [:days_until_event, :event_day_label] and rest != [] ->
        [
          issue(
            issue_meta,
            meta,
            fun,
            "#{fun}/1 compares against Pacific today — do not pass a browser timezone. " <>
              "See `mix credo explain #{id()}`."
          )
          | issues
        ]

      fun == :format_event_date_range ->
        maybe_wrong_range(
          value,
          :pacific_anchored_datetime,
          meta,
          issue_meta,
          issues,
          "Use DateDisplay.format_sale_window_range/2 for ticket-tier sale windows, " <>
            "not format_event_date_range/2 (that helper never shift_zones)."
        )

      fun == :format_sale_window_range ->
        maybe_wrong_range(
          value,
          :california_calendar_datetime,
          meta,
          issue_meta,
          issues,
          "Use DateDisplay.format_event_date_range/2 for event dates, " <>
            "not format_sale_window_range/2 (that helper shifts to Pacific)."
        )

      true ->
        case field_kind(value, bindings) do
          {_schema, field, kind} ->
            if forbidden_formatter?(kind, fun) do
              [
                issue(
                  issue_meta,
                  meta,
                  fun,
                  "#{fun} is the wrong conversion for #{field} (#{kind}; " <>
                    "#{DateKind.display_hint(kind)}). See `mix credo explain #{id()}`."
                )
                | issues
              ]
            else
              issues
            end

          _ ->
            issues
        end
    end
  end

  defp maybe_wrong_range(value, bad_kind, meta, issue_meta, issues, message) do
    case receiver_schema(value) do
      nil ->
        issues

      schema ->
        if DateFields.kind(schema, :start_date) == bad_kind do
          [
            issue(
              issue_meta,
              meta,
              :start_date,
              message <> " See `mix credo explain #{id()}`."
            )
            | issues
          ]
        else
          issues
        end
    end
  end

  defp forbidden_formatter?(:california_calendar_datetime, fun),
    do: fun in @never_formatters

  defp forbidden_formatter?(:california_date, fun),
    do: fun in @never_formatters

  defp forbidden_formatter?(:pacific_time, fun),
    do: fun in @never_formatters or fun in @shift_funs

  defp forbidden_formatter?(:pacific_anchored_datetime, fun),
    do: fun in @pacific_browser_formatters

  defp forbidden_formatter?(:utc_instant, fun),
    do: fun in @browser_event_formatters

  defp forbidden_formatter?(:naive_date, fun),
    do: fun in @never_formatters

  defp forbidden_formatter?(_, _), do: false

  defp field_kind(ast, bindings) do
    with {schema, field} <- field_access(ast, bindings),
         kind when not is_nil(kind) <- DateFields.kind(schema, field) do
      {schema, field, kind}
    else
      _ -> nil
    end
  end

  # event.start_date / @event.start_date / assigns.event.start_date
  defp field_access({{:., _, [receiver, field]}, _, []}, _bindings)
       when is_atom(field) do
    case receiver_schema(receiver) do
      nil -> nil
      schema -> {schema, field}
    end
  end

  # Map.get(event, :start_date)
  defp field_access(
         {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [receiver, field]},
         _bindings
       )
       when is_atom(field) do
    case receiver_schema(receiver) do
      nil -> nil
      schema -> {schema, field}
    end
  end

  # A bare variable previously bound to a field access via
  # `case receiver.field do var -> ... end` (see the :case traverse clause).
  defp field_access({name, _, ctx}, bindings)
       when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) do
    Map.get(bindings, name)
  end

  defp field_access(_ast, _bindings), do: nil

  defp receiver_schema({:@, _, [{name, _, _}]}) when is_atom(name),
    do: DateFields.schema_for_receiver(name)

  defp receiver_schema({name, _, _}) when is_atom(name),
    do: DateFields.schema_for_receiver(name)

  defp receiver_schema({{:., _, [{:assigns, _, _}, name]}, _, []})
       when is_atom(name),
       do: DateFields.schema_for_receiver(name)

  defp receiver_schema({{:., _, [{:@, _, [{:assigns, _, _}]}, name]}, _, []})
       when is_atom(name),
       do: DateFields.schema_for_receiver(name)

  defp receiver_schema(_), do: nil

  defp issue(issue_meta, meta, trigger, message) do
    format_issue(issue_meta,
      message: message,
      trigger: to_string(trigger),
      line_no: meta[:line]
    )
  end
end
