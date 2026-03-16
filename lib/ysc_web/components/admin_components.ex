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
        {format_form_error(msg)}
      </.error>
    </div>
    """
  end

  defp format_form_error({_key, {msg, _type}}), do: msg
  defp format_form_error({msg, _type}), do: msg

  # ---------------------------------------------------------------------------
  # side_menu
  # ---------------------------------------------------------------------------

  attr :active_page, :string
  attr :email, :string
  attr :first_name, :string
  attr :last_name, :string
  attr :user_id, :string
  attr :most_connected_country, :string
  attr :board_position, :any, default: nil
  slot :inner_block, required: true

  def side_menu(assigns) do
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

              <li>
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

              <li>
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

              <li>
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

              <li :if={@board_position == :treasurer}>
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
          class="flex-shrink-0 px-4 py-4 border-t border-zinc-800 bg-zinc-900"
        >
          <.user_card
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
            email={@email}
            user_id={@user_id}
            country={@most_connected_country}
            class="w-8 h-8 rounded-full ring-2 ring-zinc-600"
          />
        </div>
      </div>
    </aside>

    <main id="admin-main" class="px-4 lg:px-10 lg:ml-72 mt-0 lg:-mt-14 min-h-screen">
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
    <div class={["relative inline-block", @class]}>
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
      assign(assigns, form: Phoenix.Component.to_form(meta), meta: nil)

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
  attr :rest, :global, include: ~w(phx-submit phx-submit-disable)

  def admin_search_bar(assigns) do
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
end
