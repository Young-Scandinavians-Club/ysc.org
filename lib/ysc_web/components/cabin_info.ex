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
  The must-know rules, once, directly under the hero: a single hairline panel
  with one cell per rule. Each cell has a tinted icon, a small label and the
  rule itself, so it scans in a second. Cells sit in a row on wide screens, two
  by two on tablets and stacked on phones.

  Each `:item` takes a hero `icon`, a short `title` and an optional `id`; the
  slot body is the rule.
  """
  attr :id, :string, default: nil
  attr :accent, :atom, default: :blue, values: [:blue, :teal]

  slot :item, required: true do
    attr :icon, :string, required: true
    attr :title, :string, required: true
    attr :id, :string
  end

  def essentials_strip(assigns) do
    ~H"""
    <ul
      id={@id}
      class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-px overflow-hidden rounded-lg border border-zinc-200 bg-zinc-200"
    >
      <li
        :for={item <- @item}
        id={Map.get(item, :id)}
        class="flex items-start gap-3 bg-white px-4 py-3.5"
      >
        <span class={[
          "mt-0.5 inline-flex size-8 shrink-0 items-center justify-center rounded-full",
          accent_tint(@accent)
        ]}>
          <.icon name={item.icon} class="size-4" />
        </span>
        <div class="min-w-0">
          <p class="type-eyebrow text-xs text-zinc-500">{item.title}</p>
          <p class="mt-0.5 text-sm font-medium text-zinc-900 leading-snug">
            {render_slot(item)}
          </p>
        </div>
      </li>
    </ul>
    """
  end

  defp accent_tint(:blue), do: "bg-blue-50 text-blue-700"
  defp accent_tint(:teal), do: "bg-teal-50 text-teal-700"

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
  Dialog shell for the booking pages' rules and review modals.

  Sits at `z-200`, above the sticky navbar (`z-100`) and the mobile booking bar,
  but below toasts. `data-modal-open` lets `app.css` lift `<main>` out of its
  hero-page stacking context while the dialog is open. A bottom sheet on phones, a centered panel from `sm` up.
  The body scrolls inside the panel, so the header and footer stay in reach.
  Clicking the backdrop or pressing Escape pushes `on_close`.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true

  attr :on_close, :string,
    required: true,
    doc: "LiveView event to push to close"

  attr :size, :atom, default: :md, values: [:md, :lg]
  attr :description, :string, default: nil
  attr :accent, :atom, default: :blue, values: [:blue, :teal]

  slot :inner_block, required: true
  slot :footer, required: true

  def cabin_modal(assigns) do
    ~H"""
    <div
      id={@id}
      data-modal-open
      class="fixed inset-0 z-200 flex items-end sm:items-center justify-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-window-keydown={@on_close}
      phx-key="escape"
    >
      <div
        id={"#{@id}-backdrop"}
        class="absolute inset-0 bg-zinc-900/50"
        phx-click={@on_close}
        aria-hidden="true"
      >
      </div>
      <div class={[
        "relative flex flex-col w-full max-h-[92dvh] sm:max-h-[85dvh] bg-white rounded-t-xl sm:rounded-xl shadow-xl sm:m-6",
        if(@size == :lg, do: "sm:max-w-3xl", else: "sm:max-w-lg")
      ]}>
        <header class="flex items-start justify-between gap-4 px-6 pt-5 pb-4 border-b border-zinc-200">
          <div>
            <h2 id={"#{@id}-title"} class="type-subhead text-xl text-zinc-900">
              {@title}
            </h2>
            <p
              :if={@description}
              id={"#{@id}-intro"}
              class="mt-1 text-sm text-zinc-500 leading-relaxed"
            >
              {@description}
            </p>
          </div>
          <button
            type="button"
            phx-click={@on_close}
            class="-m-2 p-2 min-h-11 min-w-11 inline-flex items-center justify-center rounded-md text-zinc-500 hover:text-zinc-900 hover:bg-zinc-100 transition-colors"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </header>
        <div class="flex-1 overflow-y-auto overscroll-contain px-6 cabin-copy">
          {render_slot(@inner_block)}
        </div>
        <footer class={[
          "flex flex-col-reverse gap-3 px-6 py-4 border-t border-zinc-200 sm:flex-row sm:justify-end pb-[max(1rem,env(safe-area-inset-bottom))]"
        ]}>
          {render_slot(@footer)}
        </footer>
      </div>
    </div>
    """
  end

  @doc """
  One topic inside a `cabin_modal/1`: the title on the left, rows on the right,
  hairline-separated from the next topic. Use `spec_list/1` inside for rows.
  """
  attr :title, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def modal_section(assigns) do
    ~H"""
    <section
      id={@id}
      class="py-5 grid grid-cols-1 gap-2 sm:grid-cols-[10rem_1fr] sm:gap-6 border-b border-zinc-100 last:border-b-0"
    >
      <h3 class="type-subhead text-sm text-zinc-900">{@title}</h3>
      <div class="min-w-0 space-y-3 text-sm text-zinc-600 leading-relaxed">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
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
          <strong :if={Map.get(item, :title)}>
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
      <ol class="space-y-3 text-sm text-zinc-600 leading-relaxed">
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
  Refund percentage by how far ahead of check-in a guest cancels, one column
  per stay type.

  `columns` is a list of `%{label: String.t(), rules: [rule]}`. A rule applies
  when the cancellation is within its `days_before_checkin` (the tightest
  matching rule wins, as in `Ysc.Bookings`), so rows are the bands between the
  union of every column's thresholds; cancelling earlier than all of them is a
  full refund. With no rules at all, an empty-state row is shown instead.
  """
  attr :id, :string, default: nil
  attr :columns, :list, required: true

  def refund_table(assigns) do
    thresholds =
      assigns.columns
      |> Enum.map(& &1.rules)
      |> RefundPolicyDisplay.unique_threshold_days_desc()

    assigns = assign(assigns, :bands, refund_bands(thresholds, assigns.columns))

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
          <tr :if={@bands == []}>
            <td colspan={length(@columns) + 1} class="px-4 py-3 text-zinc-500">
              Policy information will be displayed here
            </td>
          </tr>
          <tr :for={band <- @bands}>
            <th scope="row" class="px-4 py-3 text-left font-medium text-zinc-900">
              {band.label}
            </th>
            <td :for={percentage <- band.percentages} class="px-4 py-3 tabular-nums">
              <span class={
                if(percentage == 0, do: "text-zinc-500", else: "font-medium")
              }>
                {percentage}%
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # Rows for the refund table: everything earlier than the loosest threshold is a
  # full refund, then one band per threshold down to check-in.
  defp refund_bands([], _columns), do: []

  defp refund_bands([loosest | _] = thresholds, columns) do
    full = %{
      label: "More than #{loosest} days before check-in",
      percentages: Enum.map(columns, fn _ -> 100 end)
    }

    lower_bounds = Enum.drop(thresholds, 1) ++ [nil]

    bands =
      thresholds
      |> Enum.zip(lower_bounds)
      |> Enum.map(fn {upper, lower} ->
        %{
          label: band_label(upper, lower),
          percentages: Enum.map(columns, &refund_for_band(&1.rules, upper))
        }
      end)

    [full | bands]
  end

  defp band_label(upper, nil), do: "#{upper} days or fewer before check-in"

  defp band_label(upper, lower) when lower + 1 == upper,
    do: "#{upper} days before check-in"

  defp band_label(upper, lower),
    do: "#{lower + 1}–#{upper} days before check-in"

  # The tightest rule that still covers the band's upper edge; none means the
  # band is looser than every rule, so a full refund.
  defp refund_for_band(rules, upper) do
    rules
    |> Enum.filter(&(&1.days_before_checkin >= upper))
    |> Enum.min_by(& &1.days_before_checkin, fn -> nil end)
    |> case do
      nil -> 100
      rule -> RefundPolicyDisplay.refund_percentage_int(rule.refund_percentage)
    end
  end
end
