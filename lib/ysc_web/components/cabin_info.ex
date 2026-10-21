defmodule YscWeb.Components.CabinInfo do
  @moduledoc """
  Editorial building blocks for the cabin booking pages' information tabs
  (Tahoe and Clear Lake).

  The pages read as a document, not a dashboard: sections sit directly on the
  page canvas, separated by hairlines, with the section title in a left rail
  and the content on the right (`info_sections/1` + `info_section/1`). Inside a
  section, prefer a definition list (`spec_list/1`), a stat strip
  (`stat_strip/1`) or a plain list over bordered cards, so nothing is ever a box
  inside a box. Color is reserved for small semantic accents.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents, only: [icon: 1]

  alias Ysc.Bookings.RefundPolicyDisplay

  @doc """
  Underline tab bar for the three reference tabs, ordered by when a member needs
  them: the cabin and its rooms (deciding), the arrival and house manual
  (packing and on site), and the booking policies (the fine print).

  Fires `switch-info-tab` with `phx-value-tab` set to `general`, `manual` or
  `rules`.
  """
  attr :active, :atom, required: true, values: [:general, :manual, :rules]
  attr :accent, :atom, default: :blue, values: [:blue, :teal]

  def info_tabs(assigns) do
    ~H"""
    <div class="sticky top-0 z-10 bg-white/90 backdrop-blur-md border-b border-zinc-200 mb-8 -mx-4 px-4">
      <nav class="flex gap-6 overflow-x-auto" role="tablist">
        <.info_tab
          id="info-tab-general"
          tab="general"
          icon="hero-home-modern"
          active={@active == :general}
          accent={@accent}
        >
          The Cabin & Rooms
        </.info_tab>
        <.info_tab
          id="info-tab-manual"
          tab="manual"
          icon="hero-key"
          active={@active == :manual}
          accent={@accent}
        >
          Arrival & House Manual
        </.info_tab>
        <.info_tab
          id="info-tab-rules"
          tab="rules"
          icon="hero-clipboard-document-list"
          active={@active == :rules}
          accent={@accent}
        >
          Booking & Cancellation Policies
        </.info_tab>
      </nav>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :tab, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, required: true
  attr :accent, :atom, required: true
  slot :inner_block, required: true

  defp info_tab(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="tab"
      aria-selected={to_string(@active)}
      phx-click="switch-info-tab"
      phx-value-tab={@tab}
      class={[
        "inline-flex items-center gap-2 min-h-11 -mb-px border-b-2 text-sm whitespace-nowrap transition-colors",
        if(@active,
          do: ["font-semibold text-zinc-900", tab_underline(@accent)],
          else: "font-medium border-transparent text-zinc-500 hover:text-zinc-900"
        )
      ]}
    >
      <.icon name={@icon} class="w-4 h-4 shrink-0" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp tab_underline(:blue), do: "border-blue-600"
  defp tab_underline(:teal), do: "border-teal-600"

  @doc """
  One quiet line of must-know rules, shown once under the hero. Items wrap on
  small screens. Each `:item` takes a hero `icon`.
  """
  attr :id, :string, default: nil
  attr :accent, :atom, default: :blue, values: [:blue, :teal]

  slot :item, required: true do
    attr :icon, :string, required: true
    attr :id, :string
  end

  def essentials_strip(assigns) do
    ~H"""
    <ul
      id={@id}
      class="flex flex-wrap gap-x-6 gap-y-2 py-3 border-y border-zinc-200 text-sm text-zinc-700"
    >
      <li
        :for={item <- @item}
        id={Map.get(item, :id)}
        class="flex items-center gap-2"
      >
        <.icon name={item.icon} class={["w-4 h-4 shrink-0", accent_icon(@accent)]} />
        <span>{render_slot(item)}</span>
      </li>
    </ul>
    """
  end

  defp accent_icon(:blue), do: "text-blue-600"
  defp accent_icon(:teal), do: "text-teal-600"

  @doc """
  One-line helper bar of constraints that affect picking dates, set directly above
  the calendar. Each `:rule` takes a hero `icon`.
  """
  attr :id, :string, default: nil

  slot :rule, required: true do
    attr :icon, :string, required: true
  end

  def rules_bar(assigns) do
    ~H"""
    <ul
      id={@id}
      class="flex flex-wrap gap-x-5 gap-y-1.5 text-xs text-zinc-600"
    >
      <li :for={rule <- @rule} class="flex items-center gap-1.5">
        <.icon name={rule.icon} class="w-4 h-4 shrink-0 text-zinc-400" />
        <span>{render_slot(rule)}</span>
      </li>
    </ul>
    """
  end

  @doc """
  Short refund summary for the booking sidebar, one line per stay type.

  `columns` is a list of `%{label: String.t(), rules: [rule]}`. The best refund
  tier is the largest percentage; among ties, the shortest notice. Stay types
  without a refundable tier are left out, and nothing renders if none qualify.
  """
  attr :id, :string, default: nil
  attr :columns, :list, required: true

  def refund_summary(assigns) do
    assigns = assign(assigns, :lines, refund_summary_lines(assigns.columns))

    ~H"""
    <p
      :if={@lines != []}
      id={@id}
      class="mt-2 text-xs text-zinc-500 leading-relaxed"
    >
      <span :for={line <- @lines} class="block">{line}</span>
      <span class="block">3% processing fee on cash refunds.</span>
    </p>
    """
  end

  @doc false
  def refund_summary_lines(columns) do
    columns
    |> Enum.map(fn %{label: label, rules: rules} ->
      {label, best_refund_rule(rules)}
    end)
    |> Enum.reject(fn {_label, rule} -> is_nil(rule) end)
    |> Enum.map(fn {label, rule} ->
      pct = RefundPolicyDisplay.refund_percentage_int(rule.refund_percentage)

      "#{label}: #{pct}% refund #{rule.days_before_checkin}+ days before check-in"
    end)
  end

  defp best_refund_rule(rules) do
    rules
    |> Enum.filter(
      &(RefundPolicyDisplay.refund_percentage_int(&1.refund_percentage) > 0)
    )
    |> Enum.sort_by(
      &{-RefundPolicyDisplay.refund_percentage_int(&1.refund_percentage),
       &1.days_before_checkin}
    )
    |> List.first()
  end

  @doc """
  Hairline-divided stack of `info_section/1` rows.
  """
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def info_sections(assigns) do
    ~H"""
    <div
      id={@id}
      class={["divide-y divide-zinc-200 border-t border-zinc-200", @class]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  One editorial row: title and a one-line description in a left rail, content on
  the right. Stacks on small screens.

  ## Examples

      <.info_section id="cancellation-policy" heading_id="tahoe-cancellation-heading"
        title="Cancellation policy" description="Refunds depend on notice.">
        ...
      </.info_section>
  """
  attr :id, :string, default: nil
  attr :heading_id, :string, default: nil
  attr :title, :string, required: true
  attr :eyebrow, :string, default: nil
  attr :description, :string, default: nil
  attr :class, :any, default: nil

  slot :aside, doc: "Extra content under the description in the left rail"
  slot :inner_block, required: true

  def info_section(assigns) do
    ~H"""
    <section
      id={@id}
      class={["py-10 grid grid-cols-1 lg:grid-cols-12 gap-x-8 gap-y-6", @class]}
    >
      <div class="lg:col-span-4">
        <p :if={@eyebrow} class="type-eyebrow text-xs text-amber-700 mb-1">
          {@eyebrow}
        </p>
        <h2 id={@heading_id} class="type-subhead text-lg text-zinc-900">
          {@title}
        </h2>
        <p :if={@description} class="text-sm text-zinc-500 mt-1.5 leading-relaxed">
          {@description}
        </p>
        {render_slot(@aside)}
      </div>
      <div class="lg:col-span-8 min-w-0 space-y-8">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc """
  Single-row banner of short, non-negotiable rules (one hairline box, not three
  cards). Each item takes an `icon` (hero name), a `title`, a `detail` and an
  optional `tone` of `:danger` (default), `:warn` or `:neutral`.
  """
  attr :id, :string, default: nil

  slot :item, required: true do
    attr :icon, :string, required: true
    attr :title, :string, required: true
    attr :detail, :string
    attr :tone, :atom
  end

  def rule_strip(assigns) do
    ~H"""
    <ul
      id={@id}
      class="grid grid-cols-1 md:grid-cols-3 divide-y md:divide-y-0 md:divide-x divide-zinc-200 border border-zinc-200 rounded-lg bg-zinc-50/50"
    >
      <li :for={item <- @item} class="p-4 flex items-start gap-3.5">
        <.icon
          name={item.icon}
          class={["w-5 h-5 shrink-0 mt-0.5", tone_class(Map.get(item, :tone))]}
        />
        <div>
          <p class="text-sm font-semibold text-zinc-900">{item.title}</p>
          <p :if={Map.get(item, :detail)} class="text-xs text-zinc-500 mt-0.5">
            {item.detail}
          </p>
        </div>
      </li>
    </ul>
    """
  end

  defp tone_class(:warn), do: "text-amber-600"
  defp tone_class(:neutral), do: "text-zinc-500"
  defp tone_class(_danger), do: "text-red-600"

  @doc """
  Single callout with a coloured left rule. The one place a tinted fill is
  allowed, because it is the one thing on the page that should stand out.
  """
  attr :id, :string, default: nil
  attr :icon, :string, default: nil
  attr :title, :string, default: nil
  attr :accent, :atom, default: :blue, values: [:blue, :teal, :amber, :red]
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def info_callout(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "border-l-4 bg-zinc-50 rounded-r-lg px-5 py-4 flex items-start gap-3",
        callout_border(@accent),
        @class
      ]}
    >
      <.icon
        :if={@icon}
        name={@icon}
        class={["w-5 h-5 shrink-0 mt-0.5", callout_icon(@accent)]}
      />
      <div class="text-sm text-zinc-600 leading-relaxed space-y-1">
        <p :if={@title} class="font-semibold text-zinc-900">{@title}</p>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp callout_border(:blue), do: "border-blue-600"
  defp callout_border(:teal), do: "border-teal-600"
  defp callout_border(:amber), do: "border-amber-500"
  defp callout_border(:red), do: "border-red-600"

  defp callout_icon(:blue), do: "text-blue-600"
  defp callout_icon(:teal), do: "text-teal-600"
  defp callout_icon(:amber), do: "text-amber-600"
  defp callout_icon(:red), do: "text-red-600"

  @doc """
  Hairline-gridded row of key figures (rates, capacity). Each `:stat` has a
  `label`, a `value` and optionally a `unit` (small, after the value) or
  `detail` (under the value).
  """
  attr :id, :string, default: nil
  attr :columns, :integer, default: 3, values: [2, 3, 4]
  attr :class, :any, default: nil

  slot :stat, required: true do
    attr :label, :string, required: true
    attr :value, :string, required: true
    attr :unit, :string
    attr :detail, :string
  end

  def stat_strip(assigns) do
    ~H"""
    <dl
      id={@id}
      class={[
        "grid gap-px bg-zinc-200 border border-zinc-200 rounded-lg overflow-hidden",
        stat_columns(@columns),
        @class
      ]}
    >
      <div :for={stat <- @stat} class="bg-zinc-50 px-4 py-3">
        <dt class="type-eyebrow text-xs text-zinc-500">{stat.label}</dt>
        <dd class="mt-1 text-xl font-semibold text-zinc-900">
          {stat.value}<span
            :if={Map.get(stat, :unit)}
            class="block sm:inline sm:ml-0.5 text-xs font-normal text-zinc-500"
          >{stat.unit}</span>
        </dd>
        <dd :if={Map.get(stat, :detail)} class="text-xs text-zinc-500 mt-0.5">
          {stat.detail}
        </dd>
      </div>
    </dl>
    """
  end

  defp stat_columns(2), do: "grid-cols-2"
  defp stat_columns(3), do: "grid-cols-3"
  defp stat_columns(4), do: "grid-cols-2 lg:grid-cols-4"

  @doc """
  Key/value definition list for rules, hours and limits. Each `:row` has a
  `label` and an optional `id` placed on the value, so tests and anchors can
  target a single answer.
  """
  attr :id, :string, default: nil

  slot :row, required: true do
    attr :label, :string, required: true
    attr :id, :string
  end

  def spec_list(assigns) do
    ~H"""
    <dl id={@id} class="divide-y divide-zinc-100 text-sm">
      <div :for={row <- @row} class="py-3 flex flex-col gap-1 sm:flex-row sm:gap-6">
        <dt class="sm:w-44 shrink-0 font-medium text-zinc-900">{row.label}</dt>
        <dd id={Map.get(row, :id)} class="text-zinc-600 leading-relaxed">
          {render_slot(row)}
        </dd>
      </div>
    </dl>
    """
  end

  @doc """
  Plain list with a small leading icon per item. Replaces stacks of bordered
  "rule" cards.
  """
  attr :id, :string, default: nil
  attr :tone, :atom, default: :muted, values: [:muted, :strong]

  slot :item, required: true do
    attr :icon, :string
    attr :title, :string
  end

  def icon_list(assigns) do
    ~H"""
    <ul id={@id} class="space-y-3 text-sm text-zinc-600 leading-relaxed">
      <li :for={item <- @item} class="flex items-start gap-2.5">
        <.icon
          name={Map.get(item, :icon) || "hero-check"}
          class={[
            "w-4 h-4 shrink-0 mt-1",
            if(@tone == :strong, do: "text-zinc-900", else: "text-zinc-400")
          ]}
        />
        <span>
          <strong :if={Map.get(item, :title)} class="font-semibold text-zinc-900">
            {item.title}
          </strong>
          {render_slot(item)}
        </span>
      </li>
    </ul>
    """
  end

  @doc """
  Titled, numbered sequence (`01`, `02`, ...) with a coloured status dot beside
  the title. For ordered procedures such as the bear wire.
  """
  attr :id, :string, default: nil
  attr :title, :string, default: nil, doc: "Omit for an untitled sequence"
  attr :dot, :atom, default: :emerald, values: [:emerald, :amber, :blue, :teal]

  slot :step, required: true

  def numbered_steps(assigns) do
    ~H"""
    <div id={@id}>
      <div
        :if={@title}
        class="flex items-center gap-2 mb-4 pb-2 border-b border-zinc-200"
      >
        <span class={["w-2 h-2 rounded-full", dot_class(@dot)]}></span>
        <h3 class="type-subhead text-sm text-zinc-900">{@title}</h3>
      </div>
      <ol class="space-y-3 text-sm text-zinc-700 leading-relaxed">
        <li :for={{step, index} <- Enum.with_index(@step, 1)} class="flex gap-3">
          <span class="font-mono text-xs font-bold text-zinc-400 mt-0.5">
            {String.pad_leading(Integer.to_string(index), 2, "0")}
          </span>
          <span>{render_slot(step)}</span>
        </li>
      </ol>
    </div>
    """
  end

  defp dot_class(:emerald), do: "bg-emerald-500"
  defp dot_class(:amber), do: "bg-amber-500"
  defp dot_class(:blue), do: "bg-blue-500"
  defp dot_class(:teal), do: "bg-teal-500"

  @doc """
  Bulleted list of fine print, set small and muted. Goes directly under the
  table or list it qualifies.
  """
  attr :id, :string, default: nil
  slot :note, required: true

  def fine_print(assigns) do
    ~H"""
    <ul id={@id} class="text-xs text-zinc-600 leading-relaxed space-y-1.5">
      <li :for={note <- @note} class="flex gap-2">
        <span aria-hidden="true">•</span>
        <span>{render_slot(note)}</span>
      </li>
    </ul>
    """
  end

  @doc """
  Hairline-divided checklist. Purely a reading aid: the boxes are not saved.

  Each item is a string, or a `{label, detail}` tuple for a quieter second line.
  """
  attr :id, :string, default: nil
  attr :items, :list, required: true

  def checklist(assigns) do
    ~H"""
    <ul
      id={@id}
      class="divide-y divide-zinc-100 border border-zinc-200 rounded-lg"
    >
      <li :for={item <- @items}>
        <label class="flex items-center gap-3.5 px-4 py-3 min-h-11 cursor-pointer hover:bg-zinc-50 transition-colors">
          <input
            type="checkbox"
            class="w-4 h-4 rounded-sm border-zinc-300 text-zinc-900 focus:ring-zinc-900"
          />
          <span class="text-sm text-zinc-700">
            {checklist_label(item)}
            <span :if={checklist_detail(item)} class="block text-xs text-zinc-500">
              {checklist_detail(item)}
            </span>
          </span>
        </label>
      </li>
    </ul>
    """
  end

  defp checklist_label({label, _detail}), do: label
  defp checklist_label(label), do: label

  defp checklist_detail({_label, detail}), do: detail
  defp checklist_detail(_label), do: nil

  @doc """
  Plain list of nearby places with approximate drive times.
  """
  attr :id, :string, default: nil

  slot :place, required: true do
    attr :name, :string, required: true
    attr :minutes, :integer, required: true
  end

  def nearby_list(assigns) do
    ~H"""
    <ul id={@id} class="divide-y divide-zinc-100 text-sm">
      <li
        :for={{place, index} <- Enum.with_index(@place)}
        id={@id && "#{@id}-#{index}"}
        class="py-3 flex items-baseline justify-between gap-4"
      >
        <span class="font-medium text-zinc-900">{place.name}</span>
        <span class="text-zinc-500 tabular-nums">{place.minutes} min</span>
      </li>
    </ul>
    """
  end

  @doc """
  Refund percentage by notice given, one column per stay type.

  `columns` is a list of `%{label: String.t(), rules: [rule]}`. Rows are the
  union of every column's `days_before_checkin` thresholds. A column with no
  rule at a threshold shows an em dash. With no rules at all, an empty-state row
  is shown instead.
  """
  attr :id, :string, default: nil
  attr :columns, :list, required: true

  def refund_table(assigns) do
    days =
      assigns.columns
      |> Enum.map(& &1.rules)
      |> RefundPolicyDisplay.unique_threshold_days_desc()

    assigns = assign(assigns, :days, days)

    ~H"""
    <div id={@id} class="overflow-x-auto border border-zinc-200 rounded-lg">
      <table class="w-full text-sm">
        <caption class="sr-only">Refund by notice before check-in</caption>
        <thead>
          <tr class="bg-zinc-50 border-b border-zinc-200 text-zinc-600">
            <th scope="col" class="px-4 py-2.5 text-left font-medium">
              Cancel
            </th>
            <th
              :for={column <- @columns}
              scope="col"
              class="px-4 py-2.5 text-left font-medium"
            >
              {column.label}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-zinc-200 text-zinc-700">
          <tr :if={@days == []}>
            <td colspan={length(@columns) + 1} class="px-4 py-3 text-zinc-500">
              Policy information will be displayed here
            </td>
          </tr>
          <tr :for={days <- @days}>
            <th scope="row" class="px-4 py-3 text-left font-medium text-zinc-900">
              {days} or more days before check-in
            </th>
            <td :for={column <- @columns} class="px-4 py-3 tabular-nums">
              <.refund_cell rule={
                RefundPolicyDisplay.find_rule_for_days(column.rules, days)
              } />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :rule, :map, default: nil

  defp refund_cell(%{rule: %{refund_percentage: percentage}} = assigns)
       when not is_nil(percentage) do
    assigns =
      assign(
        assigns,
        :percentage,
        RefundPolicyDisplay.refund_percentage_int(percentage)
      )

    ~H"""
    <span class={if(@percentage == 0, do: "text-zinc-400", else: "font-medium")}>
      {@percentage}%
    </span>
    """
  end

  defp refund_cell(assigns) do
    ~H"""
    <span class="text-zinc-400">—</span>
    """
  end
end
