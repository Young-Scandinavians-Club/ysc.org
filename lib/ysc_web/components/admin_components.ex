defmodule YscWeb.AdminComponents do
  @moduledoc """
  UI components that are exclusively used in the admin section of the application.

  These components are imported automatically in all admin LiveViews via the
  `use YscWeb, :admin_live_view` macro. For admin LiveComponents, import this
  module explicitly if you need to use any of these components.
  """
  use Phoenix.Component
  use Gettext, backend: YscWeb.Gettext

  alias Phoenix.LiveView.JS
  alias YscWeb.FormHelpers

  import Flop.Phoenix
  import YscWeb.CoreComponents

  @min_date Date.utc_today() |> Date.add(-365)

  # ---------------------------------------------------------------------------
  # date_picker
  # ---------------------------------------------------------------------------

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)

  attr(:start_date_field, :any,
    doc:
      "a %Phoenix.HTML.Form{}/field name tuple, for example: @form[:start_date]"
  )

  attr(:required, :boolean, default: false)
  attr(:readonly, :boolean, default: false)
  attr(:min, :any, default: @min_date, doc: "the earliest date that can be set")
  attr(:errors, :list, default: [])
  attr(:form, :any)

  def date_picker(assigns) do
    ~H"""
    <.live_component
      module={YscWeb.Components.DateRangePicker}
      label={@label}
      id={@id}
      form={@form}
      start_date_field={@start_date_field}
      required={@required}
      readonly={@readonly}
      is_range?={false}
      min={@min}
    />
    <div :if={Phoenix.Component.used_input?(@start_date_field)}>
      <.error :for={msg <- @start_date_field.errors}>
        {FormHelpers.format_form_error(msg)}
      </.error>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_page_title
  # ---------------------------------------------------------------------------

  @doc """
  Renders a consistent primary heading for admin pages and modals.

  Use `variant={:emphasis}` for bold modal or panel titles (e.g. review flows).
  Pass extra Tailwind utilities via `class` (e.g. `mb-4`).
  """
  attr :level, :integer, default: 1, values: [1, 2]
  attr :variant, :atom, default: :default, values: [:default, :emphasis]

  attr :class, :any,
    default: nil,
    doc: "Additional classes merged with the default title styles"

  attr :subtitle, :string,
    default: nil,
    doc: "Optional muted description rendered below the title"

  slot :inner_block, required: true

  def admin_page_title(assigns) do
    ~H"""
    <%= case @level do %>
      <% 1 -> %>
        <h1 class={[title_base_classes(@variant), @class]}>
          {render_slot(@inner_block)}
        </h1>
      <% 2 -> %>
        <h2 class={[title_base_classes(@variant), @class]}>
          {render_slot(@inner_block)}
        </h2>
    <% end %>
    <p :if={@subtitle} class="text-sm text-zinc-500 mt-1">
      {@subtitle}
    </p>
    """
  end

  defp title_base_classes(:emphasis), do: "text-2xl font-bold text-zinc-900"

  defp title_base_classes(:default),
    do: "text-2xl font-semibold leading-8 text-zinc-800"

  # ---------------------------------------------------------------------------
  # admin_kbd
  # ---------------------------------------------------------------------------

  @doc """
  Renders a small keyboard-key pill for admin shortcut hints (check-in flows, etc.).

  - `size={:compact}` — square keys (arrows, single digits); uses `min-w` matching check-in UIs.
  - `size={:inline}` — wider keys (`↵ enter`, `alt`); horizontal padding only.
  - `tone={:muted}` — slightly softer text (`text-zinc-400`) for secondary hints.

  Pass `data-key`, `title`, or other safe global attributes via `rest`.

  ## Examples

      <.admin_kbd size={:compact}>↑</.admin_kbd>
      <.admin_kbd size={:inline}>↵ enter</.admin_kbd>
      <.admin_kbd size={:inline} data-key="alt">alt</.admin_kbd>
      <.admin_kbd size={:compact} tone={:muted}>{@index + 1}</.admin_kbd>
  """
  attr :size, :atom,
    default: :compact,
    values: [:compact, :inline],
    doc: ":compact for single-character keys; :inline for wider labels"

  attr :tone, :atom,
    default: :default,
    values: [:default, :muted],
    doc: ":muted for de-emphasized shortcut badges"

  attr :class, :any,
    default: nil,
    doc: "Additional Tailwind classes merged onto the key"

  attr :rest, :global, include: ~w(data-key id title aria-label)

  slot :inner_block, required: true

  def admin_kbd(assigns) do
    ~H"""
    <kbd class={kbd_class_list(@size, @tone, @class)} {@rest}>
      {render_slot(@inner_block)}
    </kbd>
    """
  end

  defp kbd_class_list(:compact, :default, extra),
    do: kbd_base(:default) ++ ["min-w-[1.375rem] px-1 py-0.5", extra]

  defp kbd_class_list(:inline, :default, extra),
    do: kbd_base(:default) ++ ["px-1.5 py-0.5", extra]

  defp kbd_class_list(:compact, :muted, extra),
    do: kbd_base(:muted) ++ ["min-w-[1.375rem] px-1 py-0.5", extra]

  defp kbd_class_list(:inline, :muted, extra),
    do: kbd_base(:muted) ++ ["px-1.5 py-0.5", extra]

  defp kbd_base(:default),
    do: [
      "inline-flex justify-center items-center min-h-[1.375rem]",
      "bg-white border border-zinc-300 font-mono text-[10px] text-zinc-500 rounded",
      "shadow-[0_2px_0_0_theme(colors.zinc.300)]"
    ]

  defp kbd_base(:muted),
    do: [
      "inline-flex justify-center items-center min-h-[1.375rem]",
      "bg-white border border-zinc-300 font-mono text-[10px] text-zinc-400 rounded",
      "shadow-[0_2px_0_0_theme(colors.zinc.300)]"
    ]

  # ---------------------------------------------------------------------------
  # admin_check_in_keyboard_hints
  # ---------------------------------------------------------------------------

  @doc """
  Keyboard shortcut legend shown below admin check-in search bars.

  Used on event and membership check-in LiveViews; keeps shortcut copy and
  `admin_kbd` layout consistent.
  """
  attr :class, :any,
    default: nil,
    doc: "Additional Tailwind classes merged onto the hint row"

  attr :show, :boolean,
    default: true,
    doc: "When false, the shortcut legend is not rendered"

  def admin_check_in_keyboard_hints(assigns) do
    ~H"""
    <p
      :if={@show}
      class={[
        "mt-1.5 hidden sm:flex items-center gap-1.5 text-xs text-zinc-400 select-none",
        @class
      ]}
    >
      <span class="flex items-center gap-0.5">
        <.admin_kbd size={:compact}>↑</.admin_kbd>
        <.admin_kbd size={:compact}>↓</.admin_kbd>
      </span>
      <span>navigate</span>
      <span class="text-zinc-300">·</span>
      <.admin_kbd size={:inline}>↵ enter</.admin_kbd>
      <span>check in</span>
      <span class="text-zinc-300">·</span>
      <span class="flex items-center gap-0.5">
        <.admin_kbd size={:inline} data-key="alt">alt</.admin_kbd>
        <.admin_kbd size={:compact}>1–3</.admin_kbd>
      </span>
      <span>quick check in</span>
    </p>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_check_in_counter
  # ---------------------------------------------------------------------------

  @doc """
  Live attendance counter for admin check-in sticky headers.

  Pass `total` to show a `checked / total` fraction inside the green badge.
  """
  attr :count, :integer, required: true
  attr :total, :integer, default: nil
  attr :label, :string, default: "Checked in:"

  def admin_check_in_counter(assigns) do
    ~H"""
    <div class="flex items-center gap-2 shrink-0">
      <span class="text-sm text-zinc-500 hidden sm:inline">{@label}</span>
      <.badge type="green">
        <.icon name="hero-user-group" class="inline -mt-0.5" />
        {counter_text(@count, @total)}
      </.badge>
    </div>
    """
  end

  defp counter_text(count, nil), do: "#{count}"
  defp counter_text(count, total), do: "#{count} / #{total}"

  # ---------------------------------------------------------------------------
  # admin_message_type_badge
  # ---------------------------------------------------------------------------

  @doc """
  Badge for notification / idempotency `message_type` (`:email` or `:sms`).

  - `variant={:table}` — colored by channel (email blue, SMS green) with uppercase label
  - `variant={:detail}` — default blue badge with sentence-case label (detail panels)
  """
  attr :message_type, :atom, required: true
  attr :variant, :atom, default: :table, values: [:table, :detail]

  def admin_message_type_badge(assigns) do
    badge_type =
      case assigns.variant do
        :table ->
          YscWeb.AdminBadgeHelpers.message_type_badge_type(assigns.message_type)

        :detail ->
          "default"
      end

    label =
      YscWeb.AdminBadgeHelpers.message_type_label(
        assigns.message_type,
        assigns.variant
      )

    assigns = assign(assigns, badge_type: badge_type, label: label)

    ~H"""
    <.badge type={@badge_type}>
      {@label}
    </.badge>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_section_heading
  # ---------------------------------------------------------------------------

  @doc """
  Uppercase section label for admin check-in and similar list panels.

  Optionally appends a pill count badge (`badge_tone` controls colors).
  """
  attr :count, :integer, default: nil
  attr :badge_tone, :atom, default: :zinc, values: [:zinc, :emerald]

  attr :class, :any,
    default: nil,
    doc: "Additional classes merged onto the heading"

  slot :inner_block, required: true

  def admin_section_heading(assigns) do
    ~H"""
    <h2 class={[
      "text-sm font-semibold uppercase tracking-wide text-zinc-500",
      @class
    ]}>
      {render_slot(@inner_block)}
      <span
        :if={@count != nil}
        class={[
          "ml-1.5 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
          section_badge_classes(@badge_tone)
        ]}
      >
        {@count}
      </span>
    </h2>
    """
  end

  defp section_badge_classes(:zinc), do: "bg-zinc-100 text-zinc-700"
  defp section_badge_classes(:emerald), do: "bg-emerald-100 text-emerald-700"

  # ---------------------------------------------------------------------------
  # admin_collapsible_section
  # ---------------------------------------------------------------------------

  @doc """
  Collapsible panel for admin pages (e.g. Money Management sections).

  Fires `phx-click="toggle_section"` with `phx-value-section` set to `section`.
  The parent LiveView should track collapse state in a map assign (e.g.
  `sections_collapsed`).

  - `content_variant={:padded}` — content wrapper uses `p-4 pt-0` (card grids)
  - `content_variant={:table}` — content wrapper uses `overflow-hidden` (tables)
  """
  attr :section, :string, required: true
  attr :title, :string, required: true
  attr :collapsed?, :boolean, required: true

  attr :content_variant, :atom,
    default: :table,
    values: [:padded, :table]

  attr :class, :any,
    default: "mb-8 bg-white rounded border",
    doc: "Classes on the outer bordered container"

  slot :inner_block, required: true

  def admin_collapsible_section(assigns) do
    ~H"""
    <div class={@class}>
      <button
        type="button"
        phx-click="toggle_section"
        phx-value-section={@section}
        class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
      >
        <h2 class="text-xl font-semibold text-zinc-800">{@title}</h2>
        <.icon
          name={
            if @collapsed?,
              do: "hero-chevron-right",
              else: "hero-chevron-down"
          }
          class="w-5 h-5 text-zinc-600"
        />
      </button>
      <div :if={!@collapsed?} class={collapsible_content_classes(@content_variant)}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp collapsible_content_classes(:padded), do: "p-4 pt-0"
  defp collapsible_content_classes(:table), do: "overflow-hidden"

  # ---------------------------------------------------------------------------
  # QuickBooks sync status (admin money / ledgers)
  # ---------------------------------------------------------------------------

  @doc """
  Maps a QuickBooks sync status string to a `<.badge>` type.

  Used by `admin_quickbooks_sync_status/1` and available for custom layouts.
  """
  def quickbooks_sync_status_badge_type(status) do
    case String.downcase(to_string(status || "")) do
      "pending" -> "yellow"
      "synced" -> "green"
      "failed" -> "red"
      "processing" -> "default"
      _ -> "dark"
    end
  end

  @doc """
  Formats a QuickBooks sync error for display (string, map, or nil).
  """
  def format_quickbooks_sync_error(nil), do: ""
  def format_quickbooks_sync_error(error) when is_binary(error), do: error

  def format_quickbooks_sync_error(error) when is_map(error) do
    case Jason.encode(error, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(error)
    end
  end

  def format_quickbooks_sync_error(error), do: inspect(error)

  @doc """
  Renders QuickBooks sync status badge with optional sync error hint.

  Use in admin money tables and detail panels. `default_label` is shown when
  status is nil (expense reports use `"unknown"`, ledger entities use `"not_synced"`).
  """
  attr :status, :string, default: nil
  attr :error, :any, default: nil
  attr :default_label, :string, default: "not_synced"
  attr :layout, :atom, default: :stack, values: [:stack, :inline]
  attr :error_hint, :atom, default: :truncate, values: [:truncate, :label]

  def admin_quickbooks_sync_status(assigns) do
    label = String.capitalize(assigns.status || assigns.default_label)
    badge_type = quickbooks_sync_status_badge_type(assigns.status)
    error_text = format_quickbooks_sync_error(assigns.error)

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:badge_type, badge_type)
      |> assign(:error_text, error_text)

    ~H"""
    <%= if @layout == :inline do %>
      <.badge type={@badge_type}>{@label}</.badge>
    <% else %>
      <div class="flex flex-col">
        <.badge type={@badge_type}>{@label}</.badge>
        <%= if @error do %>
          <.tooltip
            tooltip_text={@error_text}
            max_width="max-w-md"
            text_align="text-left"
          >
            <span class={error_hint_classes(@error_hint)}>
              {error_hint_content(@error_hint, @error_text)}
            </span>
          </.tooltip>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp error_hint_classes(:label),
    do: "text-xs text-red-600 mt-1 cursor-help"

  defp error_hint_classes(:truncate),
    do: "text-xs text-red-600 mt-1 truncate max-w-xs cursor-help"

  defp error_hint_content(:label, _error_text), do: "Error"
  defp error_hint_content(:truncate, error_text), do: error_text

  # ---------------------------------------------------------------------------
  # admin_check_in_sticky_bar
  # ---------------------------------------------------------------------------

  @doc """
  Sticky header shell for admin check-in LiveViews.

  Use `width={:wide}` for event check-in (`max-w-7xl`); default is membership layout
  (`max-w-5xl`). Place back link, title, counter, and action buttons in the slot.
  """
  attr :width, :atom, default: :standard, values: [:standard, :wide]

  slot :inner_block, required: true

  def admin_check_in_sticky_bar(assigns) do
    ~H"""
    <div class="bg-white border-b border-zinc-200 sticky top-0 z-10">
      <div class={check_in_container_classes(@width)}>
        <div class="flex items-center justify-between h-16 gap-4">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_check_in_search_section
  # ---------------------------------------------------------------------------

  @doc """
  Bordered search panel below the check-in sticky bar (search form + keyboard hints).
  """
  attr :width, :atom, default: :standard, values: [:standard, :wide]

  slot :inner_block, required: true

  def admin_check_in_search_section(assigns) do
    ~H"""
    <div class="bg-white border-b border-zinc-200">
      <div class={[check_in_container_classes(@width), "pt-3 pb-2"]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_check_in_content
  # ---------------------------------------------------------------------------

  @doc """
  Main scrollable content area for admin check-in pages.
  """
  attr :width, :atom, default: :standard, values: [:standard, :wide]
  attr :class, :any, default: nil

  slot :inner_block, required: true

  def admin_check_in_content(assigns) do
    ~H"""
    <div class={[
      check_in_container_classes(@width),
      "py-6 space-y-8",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_loading_panel
  # ---------------------------------------------------------------------------

  @doc """
  Centered loading spinner for admin pages (check-in flows, etc.).

  Use inside content areas while async data is loading.
  """
  attr :class, :any,
    default: nil,
    doc: "Additional Tailwind classes merged onto the outer container"

  attr :spinner_class, :any,
    default: "w-8 h-8 text-zinc-400",
    doc: "Classes passed to the inner `<.spinner>`"

  def admin_loading_panel(assigns) do
    ~H"""
    <div class={["flex items-center justify-center py-24", @class]}>
      <.spinner class={@spinner_class} />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_flop_loading_state
  # ---------------------------------------------------------------------------

  @doc """
  Centered spinner shown while Flop list `@meta` is still loading (async assign).

  Pair with `<div :if={@meta}>` for the loaded table content.
  """
  attr :message, :string, required: true

  attr :class, :any,
    default: nil,
    doc: "Additional Tailwind classes merged onto the outer container"

  def admin_flop_loading_state(assigns) do
    ~H"""
    <div class={["py-16 text-center", @class]}>
      <.icon
        name="hero-arrow-path"
        class="w-8 h-8 text-zinc-300 mx-auto mb-4 animate-spin"
      />
      <p class="text-zinc-500 font-medium">{@message}</p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_event_check_in_table_header
  # ---------------------------------------------------------------------------

  @doc """
  Column header row for the event check-in desktop ticket table.

  Shared by `AdminEventCheckInLive` and the check-in help ghost preview.
  """
  def admin_event_check_in_table_header(assigns) do
    ~H"""
    <div class="grid grid-cols-12 gap-4 px-4 py-2.5 bg-zinc-50 border-b border-zinc-200 text-xs font-semibold uppercase tracking-wide text-zinc-500">
      <div class="col-span-1"></div>
      <div class="col-span-3">Attendee</div>
      <div class="col-span-2">Email</div>
      <div class="col-span-2">Tier</div>
      <div class="col-span-2">Ticket</div>
      <div class="col-span-2">Order</div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_event_check_in_order_group_header
  # ---------------------------------------------------------------------------

  @doc """
  Order group header row for event check-in ticket tables.

  Shows the order reference, ticket count, and optional bulk check-in action.
  Use `variant={:desktop}` inside the 12-column table layout; `variant={:mobile}`
  for the stacked card list. Set `interactive={false}` for static ghost previews.
  """
  attr :order_ref, :string, required: true
  attr :ticket_count, :integer, required: true
  attr :order_id, :any, default: nil
  attr :id, :string, default: nil

  attr :variant, :atom,
    default: :desktop,
    values: [:desktop, :mobile]

  attr :interactive, :boolean,
    default: true,
    doc: "When false, renders a static bulk action (ghost preview)"

  def admin_event_check_in_order_group_header(assigns) do
    ~H"""
    <div class={order_group_header_container_class(@variant)}>
      <div class={order_group_header_info_class(@variant)}>
        <.icon
          name="hero-shopping-bag"
          class={[
            "w-3.5 h-3.5 text-zinc-400",
            @variant == :desktop && "shrink-0"
          ]}
        />
        <span class="text-xs font-semibold text-zinc-600">{@order_ref}</span>
        <span :if={@variant == :desktop} class="text-xs text-zinc-400">
          ({ticket_count_label(@ticket_count)})
        </span>
      </div>
      <div :if={@variant == :desktop} class="col-span-2 flex items-center">
        <.admin_check_in_all_button
          :if={@ticket_count > 1}
          id={@id}
          order_id={@order_id}
          variant={:desktop}
          interactive={@interactive}
        />
      </div>
      <.admin_check_in_all_button
        :if={@variant == :mobile and @ticket_count > 1}
        id={@id}
        order_id={@order_id}
        variant={:mobile}
        interactive={@interactive}
      />
    </div>
    """
  end

  defp order_group_header_container_class(:desktop),
    do: "grid grid-cols-12 gap-4 px-4 py-2 bg-zinc-50 border-b border-zinc-100"

  defp order_group_header_container_class(:mobile),
    do:
      "flex items-center justify-between px-4 py-2.5 bg-zinc-50 border-b border-zinc-100"

  defp order_group_header_info_class(:desktop),
    do: "col-span-10 flex items-center gap-2"

  defp order_group_header_info_class(:mobile),
    do: "flex items-center gap-2"

  defp ticket_count_label(count),
    do: "#{count} ticket" <> if(count != 1, do: "s", else: "")

  # ---------------------------------------------------------------------------
  # admin_check_in_all_button
  # ---------------------------------------------------------------------------

  @doc """
  Bulk check-in control for multi-ticket orders in event check-in flows.

  Renders a `phx-click="check-in-order"` button by default, or a static label when
  `interactive` is false (ghost preview).
  """
  attr :id, :string, default: nil
  attr :order_id, :any, default: nil

  attr :variant, :atom,
    default: :desktop,
    values: [:desktop, :mobile]

  attr :interactive, :boolean, default: true

  def admin_check_in_all_button(assigns) do
    ~H"""
    <%= if @interactive do %>
      <button
        :if={@variant == :desktop}
        id={@id}
        phx-click="check-in-order"
        phx-value-order-id={@order_id}
        class="inline-flex items-center gap-1 text-xs font-medium text-emerald-700 hover:text-emerald-900 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 rounded px-2 py-1 transition-colors whitespace-nowrap"
      >
        <.icon name="hero-check-circle" class="w-3.5 h-3.5 shrink-0" /> Check in all
      </button>
      <button
        :if={@variant == :mobile}
        id={@id}
        phx-click="check-in-order"
        phx-value-order-id={@order_id}
        class="text-xs font-medium text-emerald-700 hover:text-emerald-900"
      >
        Check in all
      </button>
    <% else %>
      <span
        :if={@variant == :desktop}
        id={@id}
        class="inline-flex items-center gap-1 text-xs font-medium text-emerald-700 bg-emerald-50 border border-emerald-200 rounded px-2 py-1 whitespace-nowrap"
      >
        <.icon name="hero-check-circle" class="w-3.5 h-3.5 shrink-0" /> Check in all
      </span>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_responsive_icon_button
  # ---------------------------------------------------------------------------

  @doc """
  Action control with a labeled `<.button>` on `sm+` and an icon-only button on mobile.

  Used in check-in sticky headers (QR scanner, complete session, etc.).
  Pass LiveView attributes (`data-confirm`, `phx-value-*`, etc.) via `rest`.
  """
  attr :id, :string, default: nil
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :aria_label, :string, required: true
  attr :phx_click, :string, required: true

  attr :variant, :string,
    default: "solid",
    values: ["solid", "outline"],
    doc: "Desktop button variant"

  attr :color, :string,
    default: "blue",
    values: ["blue", "zinc"],
    doc: "Desktop button color"

  attr :mobile_tone, :atom,
    default: :primary,
    values: [:primary, :zinc],
    doc: "Icon-only mobile button text/hover colors"

  attr :rest, :global,
    include: ~w(data-confirm phx-value-id phx-value-order-id title)

  def admin_responsive_icon_button(assigns) do
    ~H"""
    <.button
      id={@id}
      phx-click={@phx_click}
      variant={@variant}
      color={@color}
      class="hidden sm:inline-flex"
      {@rest}
    >
      <.icon name={@icon} class="w-5 h-5 me-1 mt-0.5" />
      {@label}
    </.button>
    <button
      phx-click={@phx_click}
      class={["sm:hidden p-2", responsive_icon_button_mobile_classes(@mobile_tone)]}
      aria-label={@aria_label}
      {@rest}
    >
      <.icon name={@icon} class="w-6 h-6" />
    </button>
    """
  end

  defp responsive_icon_button_mobile_classes(:primary),
    do: "text-blue-700 hover:text-blue-900"

  defp responsive_icon_button_mobile_classes(:zinc),
    do: "text-zinc-500 hover:text-zinc-700"

  # ---------------------------------------------------------------------------
  # admin_responsive_clipboard_button
  # ---------------------------------------------------------------------------

  @doc """
  Clipboard control with a labeled `<.button>` on `sm+` and an icon-only button on mobile.

  Uses the `ClipboardCopy` LiveView hook. Provide `copy` for inline text or
  `copy_target` for an element id whose value/text should be copied.
  """
  attr :id, :string, required: true
  attr :icon, :string, default: "hero-clipboard"
  attr :label, :string, required: true
  attr :aria_label, :string, required: true
  attr :copy, :string, default: nil, doc: "Text copied via data-copy"

  attr :copy_target, :string,
    default: nil,
    doc: "Element id copied via data-copy-target"

  attr :variant, :string,
    default: "outline",
    values: ["solid", "outline"],
    doc: "Desktop button variant"

  attr :color, :string,
    default: "zinc",
    values: ["blue", "zinc"],
    doc: "Desktop button color"

  attr :mobile_tone, :atom,
    default: :zinc,
    values: [:primary, :zinc],
    doc: "Icon-only mobile button text/hover colors"

  attr :rest, :global, include: ~w(title)

  def admin_responsive_clipboard_button(assigns) do
    ~H"""
    <.button
      id={@id}
      type="button"
      phx-hook="ClipboardCopy"
      variant={@variant}
      color={@color}
      class="hidden sm:inline-flex"
      data-copy={@copy}
      data-copy-target={@copy_target}
      {@rest}
    >
      <.icon name={@icon} class="w-5 h-5 me-1 mt-0.5" />
      {@label}
    </.button>
    <button
      type="button"
      phx-hook="ClipboardCopy"
      class={["sm:hidden p-2", responsive_icon_button_mobile_classes(@mobile_tone)]}
      aria-label={@aria_label}
      data-copy={@copy}
      data-copy-target={@copy_target}
      {@rest}
    >
      <.icon name={@icon} class="w-6 h-6" />
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_clipboard_button
  # ---------------------------------------------------------------------------

  @doc """
  Copy-to-clipboard button using the `ClipboardCopy` hook.

  ## Variants

  - `:icon` — compact icon-only control (e.g. booking reference IDs)
  - `:labeled_feedback` — labeled button with inline "Copied" feedback (e.g. media library)
  """
  attr :id, :string, required: true
  attr :variant, :atom, required: true, values: [:icon, :labeled_feedback]
  attr :copy, :string, default: nil, doc: "Text copied via data-copy"

  attr :copy_target, :string,
    default: nil,
    doc: "Element id copied via data-copy-target"

  attr :icon, :string, default: "hero-clipboard"
  attr :label, :string, default: nil
  attr :title, :string, default: nil
  attr :aria_label, :string, default: nil

  attr :class, :any,
    default: nil,
    doc: "Additional Tailwind classes merged onto the button"

  def admin_clipboard_button(assigns) do
    feedback_id = "#{assigns.id}-feedback"

    assigns =
      assigns
      |> assign(:feedback_id, feedback_id)
      |> assign(
        :aria_label,
        assigns.aria_label || assigns.title || assigns.label
      )
      |> assign(:icon_class, clipboard_button_icon_class(assigns.variant))

    ~H"""
    <%= case @variant do %>
      <% :icon -> %>
        <button
          type="button"
          id={@id}
          phx-hook="ClipboardCopy"
          data-copy={@copy}
          data-copy-target={@copy_target}
          class={[
            "inline-flex items-center justify-center p-1.5 text-zinc-500 hover:text-zinc-700 border border-zinc-300 hover:border-zinc-400 hover:bg-zinc-50 rounded transition-colors flex-shrink-0",
            @class
          ]}
          title={@title}
          aria-label={@aria_label}
        >
          <.icon name={@icon} class={@icon_class} />
        </button>
      <% :labeled_feedback -> %>
        <button
          type="button"
          id={@id}
          phx-hook="ClipboardCopy"
          data-copy={@copy}
          data-copy-target={@copy_target}
          data-copy-feedback={@feedback_id}
          class={[
            "flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-zinc-300 hover:border-zinc-400 hover:bg-zinc-50 rounded transition-colors",
            @class
          ]}
          title={@title}
        >
          <.icon name={@icon} class={@icon_class} />
          {@label}
          <span
            id={@feedback_id}
            class="hidden items-center gap-1 text-green-700"
            aria-live="polite"
          >
            <.icon name="hero-check" class="h-3.5 w-3.5" />
            <span data-copy-feedback-label>Copied</span>
          </span>
        </button>
    <% end %>
    """
  end

  defp clipboard_button_icon_class(:icon), do: "w-4 h-4"
  defp clipboard_button_icon_class(:labeled_feedback), do: "w-3.5 h-3.5"

  # ---------------------------------------------------------------------------
  # admin_check_in_qr_scanner
  # ---------------------------------------------------------------------------

  @doc """
  Responsive QR scanner control: full label on `sm+`, icon-only button on mobile.

  Used on event and membership check-in sticky headers.
  """
  attr :id, :string, default: nil, doc: "Optional DOM id for the desktop button"
  attr :phx_click, :string, default: "launch-scanner"

  def admin_check_in_qr_scanner(assigns) do
    ~H"""
    <.admin_responsive_icon_button
      id={@id}
      icon="hero-qr-code"
      label="QR Scanner"
      aria_label="Open QR Scanner"
      phx_click={@phx_click}
    />
    """
  end

  defp check_in_container_classes(:standard),
    do: "max-w-5xl mx-auto px-4 sm:px-6 lg:px-8"

  defp check_in_container_classes(:wide),
    do: "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8"

  # ---------------------------------------------------------------------------
  # admin_dashed_more_button
  # ---------------------------------------------------------------------------

  @doc """
  Full-width dashed outline control for secondary actions such as “show more” rows
  in admin pickers (e.g. newsletter post and event grids).

  Pass LiveView attributes (`phx-click`, `phx-target`, etc.) via `rest`. Label
  content goes in the default slot.
  """
  attr :class, :any,
    default: nil,
    doc: "Additional Tailwind classes merged onto the button"

  attr :rest, :global, include: ~w(phx-click phx-target id disabled aria-label)

  slot :inner_block, required: true

  def admin_dashed_more_button(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "mt-3 w-full text-center text-xs font-medium text-zinc-500 hover:text-zinc-800",
        "py-1.5 border border-dashed border-zinc-200 hover:border-zinc-400 rounded-lg transition-colors",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_table_message
  # ---------------------------------------------------------------------------

  @doc """
  Centered status text below admin data tables (loading placeholders, empty filters).

  ## Examples

      <.admin_table_message :if={@loading?} id="entitlements-loading">
        Loading entitlements…
      </.admin_table_message>

      <.admin_table_message :if={@empty?}>
        No outstanding entitlements for this filter.
      </.admin_table_message>
  """
  attr :id, :string, default: nil

  attr :class, :any,
    default: nil,
    doc: "Additional Tailwind classes merged onto the message paragraph"

  slot :inner_block, required: true

  def admin_table_message(assigns) do
    ~H"""
    <p
      id={@id}
      class={["px-4 py-8 text-center text-zinc-500 text-sm", @class]}
    >
      {render_slot(@inner_block)}
    </p>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_list_empty_state
  # ---------------------------------------------------------------------------

  @doc """
  Centered Viking empty state for admin Flop list pages (mobile + desktop table views).

  Wraps `<.empty_viking_state>` in the standard `py-16` container. Optionally renders a
  "Clear filters" action below the illustration.

  ## Examples

      <.admin_list_empty_state
        :if={@empty}
        title="No results found"
        suggestion="Try adjusting your search term and filters."
        clear_id="admin-users-clear-filters-empty"
        clear_patch={~p"/admin/users"}
      />

      <.admin_list_empty_state
        :if={@reservation_empty}
        title="No reservations found"
        suggestion="Try adjusting your search term and filters."
        clear_event="clear-reservation-filters"
      />
  """
  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :suggestion, :string, default: nil
  attr :viking, :integer, default: 4

  attr :clear_id, :string,
    default: nil,
    doc:
      "DOM id for the clear-filters control (required when using clear_patch)"

  attr :clear_patch, :any,
    default: nil,
    doc: "LiveView patch path; renders outline `<.button>` clear filters"

  attr :clear_event, :string,
    default: nil,
    doc:
      "phx-click event name; renders legacy text button clear filters (bookings)"

  attr :class, :any,
    default: nil,
    doc: "Additional classes on the outer py-16 container"

  def admin_list_empty_state(assigns) do
    ~H"""
    <div id={@id} class={["py-16", @class]}>
      <.empty_viking_state title={@title} suggestion={@suggestion} viking={@viking} />
      <div
        :if={@clear_patch || @clear_event}
        class="px-4 py-4 flex items-center align-center justify-center"
      >
        <.button
          :if={@clear_patch}
          id={@clear_id}
          patch={@clear_patch}
          variant="outline"
          color="zinc"
          class="mx-auto w-36 justify-center gap-2 py-2 px-3 text-sm font-semibold"
        >
          <.icon name="hero-x-circle" class="w-5 h-5 -mt-0.5 shrink-0" />
          Clear filters
        </.button>
        <button
          :if={@clear_event}
          id={@clear_id}
          type="button"
          class="rounded mx-auto hover:bg-zinc-100 w-36 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-100/80"
          phx-click={@clear_event}
          phx-disable-with="Clearing..."
        >
          <.icon name="hero-x-circle" class="w-5 h-5 -mt-0.5" /> Clear filters
        </button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_empty_panel
  # ---------------------------------------------------------------------------

  @doc """
  Dashed-outline panel for empty admin detail sections (booking payments, refunds, etc.).

  Pass the message in the default slot. Use `:if` on the component to show only when a list is empty.

  ## Examples

      <.admin_empty_panel :if={@payments == []}>
        No payments found for this booking.
      </.admin_empty_panel>
  """
  attr :id, :string, default: nil

  attr :class, :any,
    default: nil,
    doc: "Additional Tailwind classes merged onto the panel container"

  slot :inner_block, required: true

  def admin_empty_panel(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "rounded-lg border-2 border-dashed border-zinc-300 p-4 text-center",
        @class
      ]}
    >
      <p class="text-sm text-zinc-500">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_icon_empty_state
  # ---------------------------------------------------------------------------

  @doc """
  Centered hero icon + title empty state for admin pages.

  Used on scanner sessions, check-in flows, and dashboard widgets. Pass `title` as an
  attribute or override with the `title` slot for dynamic copy.

  ## Variants

  - `:default` — `py-16`, large icon, prominent title (scanner, event check-in)
  - `:compact` — `py-10`, medium icon (search no-results, stream empty lists)
  - `:dashed` — dashed border panel for dashboard widgets (default `py-12`)
  - `:success` — bordered success panel with emerald icon (all attendees checked in)

  ## Examples

      <.admin_icon_empty_state
        icon="hero-qr-code"
        title="No scan sessions yet"
        description="Start a new scan session to begin."
      />

      <.admin_icon_empty_state
        variant={:dashed}
        icon="hero-calendar"
        title="No upcoming events"
        class="py-8"
        icon_class="w-7 h-7 text-zinc-200 mx-auto mb-2"
      />

      <.admin_icon_empty_state
        id="checked-in-members-empty"
        variant={:compact}
        icon="hero-identification"
        title="No members checked in yet"
        description="Use the search bar above to find and check in members"
        class="hidden only:flex flex-col items-center"
      />
  """
  attr :id, :string, default: nil
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil

  attr :variant, :atom,
    default: :default,
    values: [:default, :compact, :dashed, :success],
    doc:
      "Layout density; :dashed adds a bordered panel; :success uses emerald icon styling"

  attr :icon_class, :any,
    default: nil,
    doc: "Override default icon Tailwind classes for the variant"

  attr :class, :any,
    default: nil,
    doc: "Additional classes merged onto the outer container"

  slot :action,
    doc: "Optional CTA below the description (e.g. upload button on media page)"

  def admin_icon_empty_state(assigns) do
    icon_class =
      assigns.icon_class || icon_empty_state_icon_class(assigns.variant)

    assigns = assign(assigns, :icon_class, icon_class)

    ~H"""
    <div id={@id} class={icon_empty_state_container_class(@variant, @class)}>
      <.icon name={@icon} class={@icon_class} />
      <p :if={@title} class={icon_empty_state_title_class(@variant)}>
        {@title}
      </p>
      <p :if={@description} class={icon_empty_state_description_class(@variant)}>
        {@description}
      </p>
      <div :if={@action != []} class="mt-4">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  defp icon_empty_state_container_class(:default, extra),
    do: ["py-16 text-center text-zinc-500", extra]

  defp icon_empty_state_container_class(:compact, extra),
    do: ["py-10 text-center text-zinc-500", extra]

  defp icon_empty_state_container_class(:dashed, extra),
    do: [
      "text-center py-12 border-2 border-dashed border-zinc-100 rounded-lg",
      extra
    ]

  defp icon_empty_state_container_class(:success, extra),
    do: [
      "bg-white rounded border border-zinc-200 py-12 text-center text-zinc-500",
      extra
    ]

  defp icon_empty_state_icon_class(:default),
    do: "w-12 h-12 mx-auto mb-3 text-zinc-300"

  defp icon_empty_state_icon_class(:compact),
    do: "w-10 h-10 mx-auto mb-2 text-zinc-300"

  defp icon_empty_state_icon_class(:dashed),
    do: "w-8 h-8 text-zinc-200 mx-auto mb-2"

  defp icon_empty_state_icon_class(:success),
    do: "w-10 h-10 mx-auto mb-2 text-emerald-400"

  defp icon_empty_state_title_class(:default), do: "text-lg font-medium"
  defp icon_empty_state_title_class(:compact), do: "font-medium"
  defp icon_empty_state_title_class(:dashed), do: "text-sm text-zinc-400"
  defp icon_empty_state_title_class(:success), do: "font-medium"

  defp icon_empty_state_description_class(:default), do: "text-sm mt-1"

  defp icon_empty_state_description_class(:compact),
    do: "text-sm mt-1 text-zinc-400"

  defp icon_empty_state_description_class(:dashed),
    do: "text-sm mt-1 text-zinc-400"

  defp icon_empty_state_description_class(:success),
    do: "text-sm mt-1 text-zinc-400"

  # ---------------------------------------------------------------------------
  # admin_tabs / admin_tab
  # ---------------------------------------------------------------------------

  @doc """
  Underline tab bar wrapper for admin list pages (events, newsletters, bookings).

  Place `<.admin_tab>` children inside the default slot. Set `role="tablist"` when tabs
  use WAI-ARIA tab semantics on each `<.admin_tab>`.

  The bar scrolls horizontally on narrow viewports instead of widening the page.

  - `density={:compact}` — `py-3 px-4`, rounded top, active tab has white background
    (newsletters, events, user detail).
  - `density={:spacious}` — `py-4 px-1`, no rounded top (bookings property/section tabs).
  """
  attr :id, :string, default: nil
  attr :aria_label, :string, required: true
  attr :role, :string, default: nil
  attr :density, :atom, default: :compact, values: [:compact, :spacious]

  attr :class, :any,
    default: nil,
    doc: "Additional classes on the outer bordered container"

  slot :inner_block, required: true

  def admin_tabs(assigns) do
    ~H"""
    <div class={["border-b border-zinc-200 mb-6 w-full min-w-0", @class]}>
      <nav
        id={@id}
        class={[
          admin_tabs_nav_class(@density),
          "admin-tabs-nav flex-nowrap min-w-0 overflow-x-auto overflow-y-hidden"
        ]}
        aria-label={@aria_label}
        role={@role}
      >
        {render_slot(@inner_block)}
      </nav>
    </div>
    """
  end

  @doc """
  A single tab in `<.admin_tabs>`. Renders a `<button>` by default, or a `<.link>` when
  `patch` or `navigate` is set.

  Pass `phx-click`, `role="tab"`, `aria-selected`, etc. via `rest` on button tabs.
  """
  attr :active, :boolean, default: false
  attr :density, :atom, default: :compact, values: [:compact, :spacious]
  attr :patch, :any, default: nil
  attr :navigate, :any, default: nil

  attr :class, :any,
    default: nil,
    doc: "Additional classes merged onto the tab control"

  attr :rest, :global,
    include:
      ~w(phx-click phx-value-tab phx-value-section phx-value-filter role aria-selected id type)

  slot :inner_block, required: true

  def admin_tab(assigns) do
    ~H"""
    <%= if @patch || @navigate do %>
      <.link
        patch={@patch}
        navigate={@navigate}
        class={admin_tab_class(@active, @density, @class)}
      >
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button
        type="button"
        class={admin_tab_class(@active, @density, @class)}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  defp admin_tabs_nav_class(:compact), do: "-mb-px flex gap-0"
  defp admin_tabs_nav_class(:spacious), do: "-mb-px flex space-x-8"

  defp admin_tab_class(active, density, extra) do
    [admin_tab_base(density), admin_tab_state(active, density), extra]
  end

  defp admin_tab_base(:compact),
    do:
      "shrink-0 whitespace-nowrap py-3 px-4 border-b-2 font-medium text-sm transition-colors rounded-t"

  defp admin_tab_base(:spacious),
    do:
      "shrink-0 whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors"

  defp admin_tab_state(true, :compact),
    do: "border-blue-500 text-blue-600 bg-white"

  defp admin_tab_state(false, :compact),
    do:
      "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"

  defp admin_tab_state(true, :spacious), do: "border-blue-500 text-blue-600"

  defp admin_tab_state(false, :spacious),
    do:
      "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"

  # ---------------------------------------------------------------------------
  # admin_sending_badge
  # ---------------------------------------------------------------------------

  @doc """
  Inline pill with spinner for in-progress sends (newsletter editions, etc.).
  """
  attr :label, :string, default: "Sending…"

  def admin_sending_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold bg-blue-100 text-blue-700">
      <span class="inline-block w-3 h-3 border-2 border-blue-400 border-t-transparent rounded-full animate-spin"></span>
      {@label}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_stat_card
  # ---------------------------------------------------------------------------

  @doc """
  Metric summary card for admin dashboards (membership counts, KPI tiles).

  ## Examples

      <.admin_stat_card label="Total" value={42} subtitle="Active primary accounts" />
  """
  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :subtitle, :string, default: nil

  attr :class, :any,
    default: nil,
    doc: "Additional classes on the card container"

  def admin_stat_card(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "bg-white p-6 rounded-lg shadow-sm border border-zinc-100",
        @class
      ]}
    >
      <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-3">
        {@label}
      </p>
      <p class="text-3xl font-black text-zinc-900">
        {@value}
      </p>
      <p :if={@subtitle} class="text-xs text-zinc-500 mt-1 font-medium">
        {@subtitle}
      </p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_toggle_pill
  # ---------------------------------------------------------------------------

  @doc """
  Segmented filter control (e.g. subscriber status All / Active / Inactive).

  - `variant={:muted}` — zinc active state (default; newsletter subscriber filters).
  - `variant={:primary}` — blue active state (URL patch filters such as membership type).
  - `variant={:dark}` — dark active state (compact media-library year filters).
  - `size={:compact}` — smaller text and padding (media-library year pills).
  - `shape={:pill}` — fully rounded pill shape.

  Use `patch` or `navigate` for LiveView URL-driven filters; pass `phx-click` and
  `phx-value-*` via `rest` for event-driven filters.
  """
  attr :id, :string, default: nil
  attr :active, :boolean, default: false

  attr :variant, :atom,
    default: :muted,
    values: [:muted, :primary, :dark],
    doc: ":primary uses blue background when active (patch-based list filters)"

  attr :size, :atom,
    default: :default,
    values: [:default, :compact],
    doc: ":compact for smaller media-library year pills"

  attr :shape, :atom,
    default: :rounded,
    values: [:rounded, :pill],
    doc: ":pill for fully rounded filter pills"

  attr :patch, :any, default: nil
  attr :navigate, :any, default: nil

  attr :class, :any,
    default: nil,
    doc: "Additional classes merged onto the pill control"

  attr :rest, :global,
    include:
      ~w(phx-click phx-target phx-value-filter phx-value-section phx-value-year id disabled aria-label)

  slot :inner_block, required: true

  def admin_toggle_pill(assigns) do
    ~H"""
    <%= if @patch || @navigate do %>
      <.link
        id={@id}
        patch={@patch}
        navigate={@navigate}
        class={admin_toggle_pill_class(@active, @variant, @size, @shape, @class)}
      >
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button
        id={@id}
        type="button"
        class={admin_toggle_pill_class(@active, @variant, @size, @shape, @class)}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  defp admin_toggle_pill_class(active, variant, size, shape, extra) do
    [
      admin_toggle_pill_shape(shape),
      admin_toggle_pill_size(size),
      "font-medium transition-colors",
      admin_toggle_pill_state(active, variant),
      extra
    ]
  end

  defp admin_toggle_pill_shape(:rounded), do: "rounded"
  defp admin_toggle_pill_shape(:pill), do: "rounded-full"

  defp admin_toggle_pill_size(:default), do: "px-3 py-1.5 text-sm"
  defp admin_toggle_pill_size(:compact), do: "px-2.5 py-1 text-xs"

  defp admin_toggle_pill_state(true, :muted), do: "bg-zinc-200 text-zinc-800"

  defp admin_toggle_pill_state(false, :muted),
    do: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"

  defp admin_toggle_pill_state(true, :primary), do: "bg-blue-600 text-white"

  defp admin_toggle_pill_state(false, :primary),
    do: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"

  defp admin_toggle_pill_state(true, :dark), do: "bg-zinc-800 text-white"

  defp admin_toggle_pill_state(false, :dark),
    do: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"

  # ---------------------------------------------------------------------------
  # admin_media_library_browser
  # ---------------------------------------------------------------------------

  @doc """
  Searchable, year-filtered media library grid for admin image pickers.

  Used by `YscWeb.MediaPickerComponent` and `YscWeb.TrixImagePickerComponent`.
  Parent LiveComponents must handle `search-media`, `filter-year`, `load-more-media`,
  and `select-image` events.

  ## Examples

      <.admin_media_library_browser
        id={@id}
        target={@myself}
        search={@search}
        selected_year={@selected_year}
        available_years={@available_years}
        picker_images={@streams.picker_images}
        end_of_timeline?={@end_of_timeline?}
      />
  """
  attr :id, :string, required: true

  attr :grid_id, :string,
    required: true,
    doc: "DOM id for the stream grid container"

  attr :target, :any, required: true, doc: "phx-target (typically @myself)"
  attr :search, :string, required: true
  attr :selected_year, :any, default: nil
  attr :available_years, :list, required: true
  attr :picker_images, :any, required: true, doc: "LiveView stream of images"
  attr :end_of_timeline?, :boolean, default: false

  def admin_media_library_browser(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex flex-col sm:flex-row gap-3">
        <form
          id={"#{@id}-search-form"}
          phx-change="search-media"
          phx-target={@target}
          class="flex-1"
        >
          <.input
            type="text"
            name="search"
            value={@search}
            placeholder="Search by title or alt text..."
            phx-debounce="300"
          />
        </form>

        <.admin_year_filter_pills
          target={@target}
          selected_year={@selected_year}
          available_years={@available_years}
        />
      </div>

      <div
        id={@grid_id}
        phx-update="stream"
        phx-viewport-bottom={!@end_of_timeline? && "load-more-media"}
        phx-target={@target}
        class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-2 max-h-[60vh] overflow-y-auto pr-1"
      >
        <button
          :for={{dom_id, image} <- @picker_images}
          type="button"
          id={dom_id}
          phx-click="select-image"
          phx-target={@target}
          phx-value-image-id={image.id}
          class="group relative aspect-square rounded-lg overflow-hidden border-2 border-transparent hover:border-blue-500 focus:border-blue-500 focus:outline-none transition p-0"
        >
          <img
            src={media_library_thumbnail_url(image)}
            alt={image.alt_text || image.title || "Image"}
            loading="lazy"
            class="absolute inset-0 w-full h-full object-cover"
          />
          <div
            :if={image.title}
            class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent p-1.5 opacity-0 group-hover:opacity-100 transition"
          >
            <p class="text-xs text-white truncate">{image.title}</p>
          </div>
        </button>
      </div>
    </div>
    """
  end

  attr :target, :any, required: true
  attr :selected_year, :any, default: nil
  attr :available_years, :list, required: true

  defp admin_year_filter_pills(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1.5 items-center">
      <.admin_toggle_pill
        active={@selected_year == nil}
        variant={:dark}
        size={:compact}
        shape={:pill}
        phx-click="filter-year"
        phx-target={@target}
        phx-value-year=""
      >
        All
      </.admin_toggle_pill>
      <.admin_toggle_pill
        :for={year <- @available_years}
        active={@selected_year == year}
        variant={:dark}
        size={:compact}
        shape={:pill}
        phx-click="filter-year"
        phx-target={@target}
        phx-value-year={year}
      >
        {year}
      </.admin_toggle_pill>
    </div>
    """
  end

  @doc """
  Resolves the best available thumbnail URL for a media library image.
  """
  def media_library_thumbnail_url(%{thumbnail_path: path})
      when is_binary(path) and path != "",
      do: path

  def media_library_thumbnail_url(%{optimized_image_path: path})
      when is_binary(path) and path != "",
      do: path

  def media_library_thumbnail_url(%{raw_image_path: path})
      when is_binary(path) and path != "",
      do: path

  def media_library_thumbnail_url(_), do: "/images/ysc_logo.webp"

  # ---------------------------------------------------------------------------
  # side_menu
  # ---------------------------------------------------------------------------

  attr :active_page, :string

  attr :user, :any,
    default: nil,
    doc: "User struct; when provided, derives email/name/user_id/country/avatar"

  attr :email, :string, default: nil
  attr :first_name, :string, default: nil
  attr :last_name, :string, default: nil
  attr :user_id, :string, default: nil
  attr :most_connected_country, :string, default: nil
  attr :board_position, :any, default: nil
  attr :role, :atom, default: :admin
  slot :inner_block, required: true

  def side_menu(assigns) do
    assigns = derive_side_menu_user(assigns)

    ~H"""
    <button
      class="inline-flex items-center mb-2 p-2 mt-2 ms-3 text-sm text-zinc-500 rounded :hidden hover:bg-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-200"
      aria-controls="sidebar navigation"
      type="button"
      phx-click={show_sidebar("#admin-navigation")}
    >
      <span class="sr-only">Open sidebar navigation</span>
      <.icon name="hero-bars-3" class="w-8 h-8" />
    </button>

    <aside
      id="admin-navigation"
      class="fixed top-0 left-0 z-40 w-72 h-screen overflow-hidden transition-transform -translate-x-full lg:translate-x-0"
      aria-label="Sidebar"
      phx-click-away={hide_sidebar("#admin-navigation")}
    >
      <div class="h-full flex flex-col bg-zinc-900">
        <%!-- Fixed top: logo always visible --%>
        <div id="admin-nav-header" class="flex-shrink-0 px-5 pt-8 pb-4 relative">
          <%!-- Expanded logo --%>
          <div id="admin-nav-logo-expanded">
            <.link navigate="/" class="items-center group ps-2.5 inline-block">
              <div class="flex items-center gap-2">
                <.ysc_logo class="h-20 me-3" width={80} height={80} />
                <span class="text-xs font-black bg-blue-600 text-blue-50 px-2 py-0.5 rounded">
                  ADMIN
                </span>
              </div>
              <span class="block group-hover:underline text-sm font-bold text-zinc-400 py-4">
                Go to site <.icon name="hero-arrow-right" class="h-4 w-4" />
              </span>
            </.link>
          </div>

          <%!-- Collapsed logo (hidden by default, shown via CSS when sidebar-collapsed) --%>
          <div
            id="admin-nav-logo-collapsed"
            class="hidden flex-col items-center justify-center pt-2 pb-1 gap-1"
          >
            <.link navigate="/" aria-label="Go to site">
              <.ysc_logo width={36} height={36} />
            </.link>
          </div>

          <%!-- Collapse toggle button (desktop only) — placed after logos so it flows below in collapsed mode --%>
          <button
            type="button"
            class="hidden lg:flex absolute right-3 top-3 items-center justify-center w-7 h-7 text-zinc-500 hover:text-white hover:bg-zinc-700 rounded transition-colors"
            phx-click={toggle_sidebar_collapse()}
            aria-label="Toggle sidebar width"
          >
            <.icon
              id="admin-collapse-chevron"
              name="hero-chevron-left"
              class="w-4 h-4"
            />
          </button>
        </div>

        <%!-- Scrollable: menu items only --%>
        <div class="flex-1 min-h-0 relative">
          <div
            id="admin-sidebar-menu-scroll"
            phx-hook="ScrollMoreIndicator"
            class="h-full overflow-y-auto px-5 pt-4 pb-4"
          >
            <ul class="space-y-2 leading-6 font-medium">
              <li>
                <.link
                  navigate="/admin"
                  title="Overview"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :dashboard,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :dashboard}
                >
                  <.icon
                    :if={@active_page == :dashboard}
                    name="hero-chart-pie"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :dashboard}
                    name="hero-chart-pie"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :dashboard && "font-semibold"
                  ]}>
                    Overview
                  </span>
                </.link>
              </li>

              <li>
                <.link
                  navigate="/admin/posts"
                  title="Posts"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :news,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :news}
                >
                  <.icon
                    :if={@active_page == :news}
                    name="hero-document-text"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :news}
                    name="hero-document-text"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :news && "font-semibold"
                  ]}>
                    Posts
                  </span>
                </.link>
              </li>

              <li>
                <.link
                  navigate="/admin/events"
                  title="Events"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :events,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :events}
                >
                  <.icon
                    :if={@active_page == :events}
                    name="hero-calendar"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :events}
                    name="hero-calendar"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :events && "font-semibold"
                  ]}>
                    Events
                  </span>
                </.link>
              </li>

              <li>
                <.link
                  navigate="/admin/newsletters"
                  title="Newsletters"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :newsletters,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :newsletters}
                >
                  <.icon
                    :if={@active_page == :newsletters}
                    name="hero-envelope"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :newsletters}
                    name="hero-envelope"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :newsletters && "font-semibold"
                  ]}>
                    Newsletters
                  </span>
                </.link>
              </li>

              <li :if={@role == :admin}>
                <.link
                  navigate="/admin/bookings"
                  title="Bookings"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :bookings,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :bookings}
                >
                  <.icon
                    :if={@active_page == :bookings}
                    name="hero-home"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :bookings}
                    name="hero-home"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :bookings && "font-semibold"
                  ]}>
                    Bookings
                  </span>
                </.link>
              </li>

              <li :if={@role == :admin}>
                <.link
                  navigate="/admin/users"
                  title="Users"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :members,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :members}
                >
                  <.icon
                    :if={@active_page == :members}
                    name="hero-users"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :members}
                    name="hero-users"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :members && "font-semibold"
                  ]}>
                    Users
                  </span>
                </.link>
              </li>

              <li :if={@role == :admin && @board_position == :membership_director}>
                <.link
                  navigate="/admin/memberships"
                  title="Memberships"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :memberships,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :memberships}
                >
                  <.icon
                    :if={@active_page == :memberships}
                    name="hero-identification"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :memberships}
                    name="hero-identification"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :memberships && "font-semibold"
                  ]}>
                    Memberships
                  </span>
                </.link>
              </li>

              <li :if={@role == :admin && @board_position == :treasurer}>
                <.link
                  navigate="/admin/money"
                  title="Money"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :money,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :money}
                >
                  <.icon
                    :if={@active_page == :money}
                    name="hero-wallet"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :money}
                    name="hero-wallet"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :money && "font-semibold"
                  ]}>
                    Money
                  </span>
                </.link>
              </li>

              <li>
                <.link
                  navigate="/admin/media"
                  title="Media"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :media,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :media}
                >
                  <.icon
                    :if={@active_page == :media}
                    name="hero-photo"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :media}
                    name="hero-photo"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :media && "font-semibold"
                  ]}>
                    Media
                  </span>
                </.link>
              </li>

              <li>
                <.link
                  navigate="/admin/help"
                  title="Help"
                  class={[
                    "admin-nav-link flex items-center px-3 py-4 rounded group transition-colors",
                    if(@active_page == :help,
                      do:
                        "bg-gradient-to-r from-blue-600/20 to-transparent border-l-4 border-blue-500 text-white",
                      else: "text-zinc-300 hover:bg-zinc-800 hover:text-white"
                    )
                  ]}
                  aria-current={@active_page == :help}
                >
                  <.icon
                    :if={@active_page == :help}
                    name="hero-question-mark-circle"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-400"
                  />
                  <.icon
                    :if={@active_page != :help}
                    name="hero-question-mark-circle"
                    class="w-5 h-5 shrink-0 transition duration-75 text-blue-500"
                  />
                  <span class={[
                    "admin-nav-label ms-3",
                    @active_page == :help && "font-semibold"
                  ]}>
                    Help
                  </span>
                </.link>
              </li>
            </ul>
          </div>
          <div
            data-scroll-indicator
            class="pointer-events-none absolute bottom-0 left-0 right-0 h-12 bg-gradient-to-t from-zinc-900 to-transparent opacity-0 transition-opacity duration-200"
            aria-hidden="true"
          >
          </div>
        </div>

        <%!-- Fixed bottom user card (expanded) --%>
        <div
          id="admin-nav-user-full"
          class="flex-shrink-0 px-5 py-4 border-t border-zinc-800 bg-zinc-900"
        >
          <.user_card
            user={@user}
            email={@email}
            user_id={@user_id}
            most_connected_country={@most_connected_country}
            first_name={@first_name}
            last_name={@last_name}
            class="[&_.text-zinc-800]:text-zinc-300 [&_.text-zinc-500]:text-zinc-400"
          />
        </div>

        <%!-- Fixed bottom user avatar (collapsed, hidden by default) --%>
        <div
          id="admin-nav-user-collapsed"
          class="hidden flex-shrink-0 py-4 border-t border-zinc-700 bg-zinc-900 items-center justify-center"
        >
          <.user_avatar_image
            user={@user}
            email={@email}
            user_id={@user_id}
            country={@most_connected_country}
            class="w-8 h-8 rounded-full ring-2 ring-zinc-600"
          />
        </div>
      </div>
    </aside>

    <main
      id="admin-main"
      class="px-4 lg:px-10 lg:ml-72 mt-0 lg:-mt-14 min-h-screen min-w-0 overflow-x-clip"
    >
      {render_slot(@inner_block)}
    </main>

    <div
      id="drawer-backdrop"
      class="hidden bg-zinc-900/50 fixed inset-0 z-30"
      drawer-backdrop=""
    >
    </div>
    """
  end

  defp toggle_sidebar_collapse(js \\ %JS{}) do
    js
    |> JS.dispatch("admin:toggle-sidebar")
  end

  # ---------------------------------------------------------------------------
  # notification_badge
  # ---------------------------------------------------------------------------

  @doc """
  Renders a notification badge component that wraps content with a badge overlay.

  The badge appears in the top-right corner of the wrapped content.
  Only displays if count is provided and greater than 0.

  ## Examples

      <.notification_badge count={5}>
        <button>Notifications</button>
      </.notification_badge>

      <.notification_badge count={@pending_count} badge_color="red">
        <.button>Pending Items</.button>
      </.notification_badge>
  """
  attr :count, :integer, default: 0, doc: "The count to display in the badge"

  attr :badge_color, :string,
    default: "red",
    doc: "Color scheme for the badge (red, blue, green, yellow)"

  attr :class, :string,
    default: nil,
    doc: "Additional CSS classes for the wrapper"

  slot :inner_block,
    required: true,
    doc: "The content to wrap with the notification badge"

  def notification_badge(assigns) do
    badge_classes = %{
      "red" => "bg-red-500 text-white border-red-600",
      "blue" => "bg-blue-500 text-white border-blue-600",
      "green" => "bg-green-500 text-white border-green-600",
      "yellow" => "bg-yellow-500 text-white border-yellow-600"
    }

    badge_class = badge_classes[assigns.badge_color] || badge_classes["red"]

    assigns =
      assigns
      |> assign(:badge_class, badge_class)
      |> assign(:show_badge, assigns.count && assigns.count > 0)

    ~H"""
    <div class={["relative inline-flex shrink-0", @class]}>
      {render_slot(@inner_block)}
      <div
        :if={@show_badge}
        class={[
          "absolute inline-flex items-center justify-center w-6 h-6 text-xs font-bold",
          "border-2 rounded-full -top-2 -end-2",
          @badge_class
        ]}
      >
        {if @count > 99, do: "99+", else: @count}
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # spinner
  # ---------------------------------------------------------------------------

  attr :class, :string, default: nil

  def spinner(assigns) do
    ~H"""
    <div role="status">
      <svg
        aria-hidden="true"
        class={"text-zinc-200 animate-spin fill-blue-600 #{@class}"}
        viewBox="0 0 100 101"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <path
          d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z"
          fill="currentColor"
        />
        <path
          d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z"
          fill="currentFill"
        />
      </svg>
      <span class="sr-only">Loading...</span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # progress_bar
  # ---------------------------------------------------------------------------

  attr :progress, :integer, required: true

  @spec progress_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def progress_bar(assigns) do
    ~H"""
    <div class="w-full bg-zinc-200 rounded h-2">
      <div
        class="animate-pulse transition duration-100 ease-in-out bg-blue-600 h-2 rounded "
        style={"width: #{@progress}%"}
      >
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_row_actions_dropdown / admin_dropdown_menu_item
  # ---------------------------------------------------------------------------

  @doc """
  Ellipsis menu for per-row actions in admin tables and card lists.

  Stops row click propagation and renders the standard right-aligned trigger.
  Place `<.admin_dropdown_menu_item>` elements in the default slot.

  ## Examples

      <.admin_row_actions_dropdown id="event-actions-1" label="Event actions">
        <.admin_dropdown_menu_item
          id="event-actions-1-edit"
          icon="hero-pencil-square"
          navigate={~p"/admin/events/1/edit"}
        >
          Edit
        </.admin_dropdown_menu_item>
      </.admin_row_actions_dropdown>
  """
  attr :id, :string, required: true

  attr :label, :string,
    required: true,
    doc: "Accessible name for the trigger (rendered sr-only)"

  slot :inner_block, required: true

  def admin_row_actions_dropdown(assigns) do
    ~H"""
    <div class="flex justify-end" onclick="event.stopPropagation()">
      <.dropdown
        id={@id}
        right={true}
        class="min-w-0 !w-auto shrink-0 rounded-md px-1 py-1 text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900"
      >
        <:button_block>
          <span class="sr-only">{@label}</span>
          <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
        </:button_block>

        <div class="w-full divide-y divide-zinc-100 py-1 text-sm text-zinc-700">
          <ul class="py-1">
            {render_slot(@inner_block)}
          </ul>
        </div>
      </.dropdown>
    </div>
    """
  end

  @doc """
  A single item inside `<.admin_row_actions_dropdown>` (or any admin dropdown menu).

  Renders a `<.link>` when `navigate`, `patch`, or `href` is set; otherwise a `<button>`.
  Set `static` for non-interactive status rows (e.g. "Sending…").

  ## Examples

      <.admin_dropdown_menu_item
        id="post-actions-view"
        icon="hero-arrow-top-right-on-square"
        href={~p"/posts/1"}
        target="_blank"
        rel="noopener noreferrer"
      >
        View live
      </.admin_dropdown_menu_item>

      <.admin_dropdown_menu_item
        id="post-actions-delete"
        icon="hero-trash"
        tone={:danger}
        phx-click="delete-post"
        phx-value-id={@post.id}
        data-confirm="Delete this draft?"
      >
        Delete
      </.admin_dropdown_menu_item>
  """
  attr :id, :string, required: true
  attr :icon, :string, default: nil

  attr :tone, :atom,
    default: :default,
    values: [:default, :success, :danger, :info]

  attr :static, :boolean, default: false
  attr :navigate, :any, default: nil
  attr :patch, :any, default: nil
  attr :href, :any, default: nil

  attr :class, :any,
    default: nil,
    doc: "Additional classes merged onto the menu item"

  attr :icon_class, :any,
    default: nil,
    doc: "Override or extend default icon classes"

  attr :rest, :global,
    include:
      ~w(phx-click phx-value-id phx-value-email data-confirm disabled target rel aria-label)

  slot :inner_block, required: true
  slot :leading, doc: "Custom leading content instead of a hero icon"

  def admin_dropdown_menu_item(assigns) do
    assigns =
      assign(
        assigns,
        :icon_classes,
        dropdown_menu_item_icon_class(assigns.tone, assigns.icon_class)
      )

    ~H"""
    <li>
      <%= cond do %>
        <% @static -> %>
          <span id={@id} class={dropdown_menu_item_class(@tone, @class)}>
            <%= if @leading != [] do %>
              {render_slot(@leading)}
            <% else %>
              <.icon :if={@icon} name={@icon} class={@icon_classes} />
            <% end %>
            <span>{render_slot(@inner_block)}</span>
          </span>
        <% @navigate || @patch || @href -> %>
          <.link
            id={@id}
            navigate={@navigate}
            patch={@patch}
            href={@href}
            class={dropdown_menu_item_class(@tone, @class)}
            {@rest}
          >
            <%= if @leading != [] do %>
              {render_slot(@leading)}
            <% else %>
              <.icon :if={@icon} name={@icon} class={@icon_classes} />
            <% end %>
            <span>{render_slot(@inner_block)}</span>
          </.link>
        <% true -> %>
          <button
            id={@id}
            type="button"
            class={dropdown_menu_item_class(@tone, @class)}
            {@rest}
          >
            <%= if @leading != [] do %>
              {render_slot(@leading)}
            <% else %>
              <.icon :if={@icon} name={@icon} class={@icon_classes} />
            <% end %>
            <span>{render_slot(@inner_block)}</span>
          </button>
      <% end %>
    </li>
    """
  end

  defp dropdown_menu_item_class(tone, extra) do
    [
      "flex w-full items-center gap-2 px-4 py-2 text-left transition hover:bg-zinc-100",
      dropdown_menu_item_tone_class(tone),
      extra
    ]
  end

  defp dropdown_menu_item_tone_class(:default), do: nil
  defp dropdown_menu_item_tone_class(:success), do: "text-emerald-700"
  defp dropdown_menu_item_tone_class(:danger), do: "text-red-600"
  defp dropdown_menu_item_tone_class(:info), do: "text-blue-600"

  defp dropdown_menu_item_icon_class(:default, nil),
    do: "h-5 w-5 shrink-0 text-zinc-500"

  defp dropdown_menu_item_icon_class(_tone, nil), do: "h-5 w-5 shrink-0"

  defp dropdown_menu_item_icon_class(_tone, custom), do: custom

  # ---------------------------------------------------------------------------
  # admin_filter_dropdown
  # ---------------------------------------------------------------------------

  @doc """
  Renders the standard admin Flop filter dropdown: funnel trigger, filter form slot,
  and a full-width "Clear filters" footer button.

  Put a `<.filter_form>` (and optional extra fields) in the default slot.

  ## Examples

      <.admin_filter_dropdown
        id="filter-events-dropdown"
        clear_patch={~p"/admin/events"}
        clear_id="admin-events-clear-filters"
      >
        <.filter_form fields={[...]} meta={@meta} id="events-filter-form">
          ...
        </.filter_form>
      </.admin_filter_dropdown>
  """
  attr :id, :string, required: true

  attr :clear_patch, :any,
    required: true,
    doc: "Verified route to reset filters"

  attr :clear_id, :string,
    default: nil,
    doc: "DOM id for the clear-filters button"

  attr :wide, :boolean, default: false, doc: "Passed through to `<.dropdown>`"

  slot :inner_block, required: true

  def admin_filter_dropdown(assigns) do
    ~H"""
    <.dropdown id={@id} class="group hover:bg-zinc-100" wide={@wide}>
      <:button_block>
        <.icon
          name="hero-funnel"
          class="mr-1 text-zinc-600 w-5 h-5 group-hover:text-zinc-800 -mt-0.5"
        /> Filters
      </:button_block>

      <div class="w-full px-4 py-3">
        {render_slot(@inner_block)}
      </div>

      <div class="px-4 py-4">
        <.button
          id={@clear_id}
          patch={@clear_patch}
          variant="outline"
          color="zinc"
          class="w-full justify-center gap-2 py-2 px-3 text-sm font-semibold"
        >
          <.icon name="hero-x-circle" class="w-5 h-5 -mt-0.5 shrink-0" />
          Clear filters
        </.button>
      </div>
    </.dropdown>
    """
  end

  # ---------------------------------------------------------------------------
  # filter_form
  # ---------------------------------------------------------------------------

  attr :fields, :list, required: true
  attr :meta, Flop.Meta, required: true
  attr :id, :string, default: nil
  attr :on_change, :string, default: "update-filter"
  attr :target, :string, default: nil

  slot :inner_block

  @spec filter_form(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_form(%{meta: meta} = assigns) do
    assigns =
      assigns
      |> assign(:form, Phoenix.Component.to_form(meta))
      |> assign(:meta, nil)
      |> then(fn assigns ->
        if is_nil(assigns.id),
          do: assign(assigns, :id, filter_form_id(assigns)),
          else: assigns
      end)

    ~H"""
    <.form
      for={@form}
      id={@id}
      phx-target={@target}
      phx-change={@on_change}
      phx-submit={@on_change}
    >
      <.filter_fields :let={i} form={@form} fields={@fields}>
        <.input
          field={i.field}
          label={i.label}
          type={i.type}
          phx-debounce={120}
          {i.rest}
        />
      </.filter_fields>
      {render_slot(@inner_block)}
    </.form>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_flop_pagination
  # ---------------------------------------------------------------------------

  attr :meta, :any,
    required: true,
    doc: "Flop.Meta from the query; when nil, nothing is rendered"

  attr :path, :any,
    required: true,
    doc: "Path or verified route passed to Flop.Phoenix"

  attr :density, :atom,
    values: [:compact, :comfortable],
    default: :comfortable,
    doc:
      ":compact is for mobile toolbars (py-4, fewer page links); :comfortable matches desktop tables"

  defp filter_form_id(%{fields: fields}) when is_list(fields) do
    fields
    |> Enum.map_join("-", fn
      {key, _} when is_atom(key) -> Atom.to_string(key)
      {key, _} when is_binary(key) -> key
      key when is_atom(key) -> Atom.to_string(key)
      key when is_binary(key) -> key
    end)
    |> then(&"filter-form-#{&1}")
  end

  def admin_flop_pagination(assigns) do
    assigns =
      case assigns.density do
        :compact ->
          assign(assigns,
            pagination_class: "flex items-center justify-center py-4 text-base",
            page_links_count: 3
          )

        :comfortable ->
          assign(assigns,
            pagination_class:
              "flex items-center justify-center py-10 text-base",
            page_links_count: 5
          )
      end

    ~H"""
    <Flop.Phoenix.pagination
      :if={@meta}
      meta={@meta}
      path={@path}
      class={@pagination_class}
      page_list_attrs={[class: "flex gap-1 order-2 justify-center items-center"]}
      page_list_item_attrs={[class: "list-none"]}
      page_link_attrs={[
        class:
          "flex items-center justify-center w-9 h-9 text-sm font-medium text-zinc-600 rounded hover:bg-zinc-100 hover:text-zinc-900 transition-colors"
      ]}
      current_page_link_attrs={[
        class:
          "flex items-center justify-center w-9 h-9 text-sm font-semibold text-white bg-zinc-800 rounded pointer-events-none"
      ]}
      page_links={@page_links_count}
    >
      <:previous attrs={[
        class:
          "order-1 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
      ]}>
        <.icon name="hero-chevron-left" class="w-4 h-4" />
      </:previous>
      <:next attrs={[
        class:
          "order-3 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
      ]}>
        <.icon name="hero-chevron-right" class="w-4 h-4" />
      </:next>
    </Flop.Phoenix.pagination>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_prev_next_pagination
  # ---------------------------------------------------------------------------

  @doc """
  Previous/Next footer for offset-paginated admin tables (e.g. Money Management).

  Fires `phx-click` on the parent LiveView with `prev_event` / `next_event`.
  """
  attr :page, :integer, required: true
  attr :entry_count, :integer, required: true
  attr :prev_event, :string, required: true
  attr :next_event, :string, required: true
  attr :prev_disabled?, :boolean, required: true
  attr :next_disabled?, :boolean, required: true

  def admin_prev_next_pagination(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-6 py-4 border-t border-zinc-200">
      <div class="text-sm text-zinc-600">
        Page {@page} • Showing {@entry_count} entries
      </div>
      <div class="flex gap-2">
        <.button
          phx-click={@prev_event}
          disabled={@prev_disabled?}
          class={prev_next_button_class(@prev_disabled?)}
        >
          Previous
        </.button>
        <.button
          phx-click={@next_event}
          disabled={@next_disabled?}
          class={prev_next_button_class(@next_disabled?)}
        >
          Next
        </.button>
      </div>
    </div>
    """
  end

  defp prev_next_button_class(true),
    do: "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50"

  defp prev_next_button_class(false), do: "bg-blue-600 hover:bg-blue-700"

  # ---------------------------------------------------------------------------
  # admin_magic_search_section / admin_magic_search_link
  # ---------------------------------------------------------------------------

  @doc """
  A labeled group of results in the admin header magic search dropdown.

  Renders nothing when `show?` is false (e.g. when the result list is empty).
  """
  attr :title, :string, required: true
  attr :show?, :boolean, default: true

  slot :inner_block, required: true

  def admin_magic_search_section(assigns) do
    ~H"""
    <div :if={@show?} class="p-2">
      <div class="px-3 py-2 text-xs font-semibold text-zinc-500 uppercase tracking-wider">
        {@title}
      </div>
      <div class="space-y-1">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  A single navigable row in the admin header magic search dropdown.
  """
  attr :navigate, :string, required: true
  slot :inner_block, required: true

  def admin_magic_search_link(assigns) do
    ~H"""
    <.link
      data-result-item
      navigate={@navigate}
      class="block px-3 py-2 text-sm text-zinc-800 hover:bg-zinc-50 rounded"
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # ---------------------------------------------------------------------------
  # admin_search_bar
  # ---------------------------------------------------------------------------

  attr :id, :string, default: nil
  attr :input_id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: "Search..."
  attr :on_change, :string, default: "change"
  attr :debounce, :string, default: "200"
  attr :clear_event, :string, default: nil
  attr :rest, :global, include: ~w(phx-submit phx-submit-disable phx-hook)

  def admin_search_bar(assigns) do
    assigns =
      if is_nil(assigns.id) do
        assign(assigns, :id, "#{assigns.input_id}-form")
      else
        assigns
      end

    ~H"""
    <form
      id={@id}
      action=""
      novalidate=""
      role="search"
      phx-change={@on_change}
      class="relative"
      {@rest}
    >
      <div class="absolute inset-y-0 rtl:inset-r-0 start-0 flex items-center ps-3 pointer-events-none">
        <.icon name="hero-magnifying-glass" class="w-5 h-5 text-zinc-500" />
      </div>
      <input
        id={@input_id}
        type="search"
        name={@name}
        autocomplete="off"
        autocorrect="off"
        autocapitalize="off"
        enterkeyhint="search"
        spellcheck="false"
        placeholder={@placeholder}
        value={@value}
        tabindex="0"
        phx-debounce={@debounce}
        class="block pt-3 pb-3 ps-10 text-sm text-zinc-800 border border-zinc-200 rounded w-full bg-zinc-50 focus:ring-blue-500 focus:border-blue-500"
      />
      <button
        :if={@clear_event && @value != ""}
        type="button"
        phx-click={@clear_event}
        phx-value-input-id={@input_id}
        class="absolute inset-y-0 end-0 flex items-center pe-3 text-zinc-400 hover:text-zinc-600"
        aria-label="Clear search"
      >
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
    </form>
    """
  end

  # ---------------------------------------------------------------------------
  # phone_mockup
  # ---------------------------------------------------------------------------

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def phone_mockup(assigns) do
    ~H"""
    <div class={"relative mx-auto border-zinc-800 bg-zinc-800 border-[14px] rounded-xl h-[600px] w-[300px] shadow-xl #{@class}"}>
      <div class="w-[148px] h-[18px] bg-zinc-800 top-0 rounded-b-[1rem] left-1/2 -translate-x-1/2 absolute">
      </div>
      <div class="h-[32px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[72px] rounded-s-lg">
      </div>
      <div class="h-[46px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[124px] rounded-s-lg">
      </div>
      <div class="h-[46px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[178px] rounded-s-lg">
      </div>
      <div class="h-[64px] w-[3px] bg-zinc-800 absolute -end-[17px] top-[142px] rounded-e-lg">
      </div>
      <div class="rounded-xl overflow-y-auto w-[272px] h-[572px] bg-white">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # tablet_mockup
  # ---------------------------------------------------------------------------

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def tablet_mockup(assigns) do
    ~H"""
    <div class={"relative mx-auto border-zinc-800 bg-zinc-800 border-[14px] rounded-[2.5rem] h-[454px] max-w-[341px] md:h-[682px] md:max-w-[512px] #{@class}"}>
      <div class="h-[32px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[72px] rounded-s-lg">
      </div>
      <div class="h-[46px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[124px] rounded-s-lg">
      </div>
      <div class="h-[46px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[178px] rounded-s-lg">
      </div>
      <div class="h-[64px] w-[3px] bg-zinc-800 absolute -end-[17px] top-[142px] rounded-e-lg">
      </div>
      <div class="rounded-[2rem] overflow-y-auto h-[426px] md:h-[654px] bg-white">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp derive_side_menu_user(%{user: user} = assigns) when not is_nil(user) do
    assigns
    |> assign(:email, Map.get(user, :email))
    |> assign(
      :user_id,
      case Map.get(user, :id) do
        nil -> nil
        id -> to_string(id)
      end
    )
    |> assign(:most_connected_country, Map.get(user, :most_connected_country))
    |> assign(:first_name, Map.get(user, :first_name))
    |> assign(:last_name, Map.get(user, :last_name))
    |> assign(:board_position, Map.get(user, :board_position))
  end

  defp derive_side_menu_user(assigns), do: assigns
end
