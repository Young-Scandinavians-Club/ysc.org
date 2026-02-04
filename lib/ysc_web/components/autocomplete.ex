defmodule YscWeb.Components.Autocomplete do
  @moduledoc """
  A reusable autocomplete/combobox component for searching and selecting items.

  ## Usage

  In your LiveView, add the necessary assigns and handlers:

      # In mount or apply_action:
      socket
      |> assign(:user_search, "")
      |> assign(:user_search_results, [])
      |> assign(:selected_user, nil)

      # Handle search event:
      def handle_event("search-users", %{"query" => query}, socket) do
        results = if String.length(query) >= 2 do
          Accounts.search_users(query, limit: 10)
        else
          []
        end

        {:noreply,
         socket
         |> assign(:user_search, query)
         |> assign(:user_search_results, results)}
      end

      # Handle selection event:
      def handle_event("select-user", %{"id" => id}, socket) do
        user = Accounts.get_user!(id)
        {:noreply,
         socket
         |> assign(:selected_user, user)
         |> assign(:user_search, "")
         |> assign(:user_search_results, [])}
      end

      # Handle clear event:
      def handle_event("clear-user", _, socket) do
        {:noreply,
         socket
         |> assign(:selected_user, nil)
         |> assign(:user_search, "")
         |> assign(:user_search_results, [])}
      end

  In your template:

      <.autocomplete
        id="user-autocomplete"
        label="User"
        name="booking[user_id]"
        search_event="search-users"
        select_event="select-user"
        clear_event="clear-user"
        search_value={@user_search}
        results={@user_search_results}
        selected={@selected_user}
        display_fn={fn user -> "\#{user.first_name} \#{user.last_name}" end}
        subtitle_fn={fn user -> user.email end}
        placeholder="Search by name or email..."
        required
      />
  """
  use Phoenix.Component

  import YscWeb.CoreComponents, only: [icon: 1]

  attr :id, :string, required: true
  attr :label, :string, default: ""
  attr :name, :string, required: true
  attr :search_event, :string, required: true
  attr :select_event, :string, required: true
  attr :clear_event, :string, required: true
  attr :search_value, :string, default: ""
  attr :results, :list, default: []
  attr :selected, :any, default: nil
  attr :display_fn, :any, required: true
  attr :subtitle_fn, :any, default: nil
  attr :value_fn, :any, default: nil
  attr :placeholder, :string, default: "Search..."
  attr :required, :boolean, default: false
  attr :min_chars, :integer, default: 2
  attr :debounce, :integer, default: 300
  attr :errors, :list, default: []
  attr :class, :string, default: ""

  def autocomplete(assigns) do
    # Default value_fn extracts :id field if not provided or nil
    default_value_fn = fn item -> Map.get(item, :id) end

    assigns =
      if is_nil(assigns[:value_fn]) do
        assign(assigns, :value_fn, default_value_fn)
      else
        assigns
      end

    ~H"""
    <div class={["relative", @class]} id={@id} phx-hook="Autocomplete">
      <label
        :if={@label != ""}
        class="block text-sm font-semibold leading-6 text-zinc-800"
      >
        <%= @label %>
      </label>

      <%!-- Hidden input for form submission --%>
      <input
        type="hidden"
        name={@name}
        value={if @selected, do: @value_fn.(@selected), else: ""}
      />

      <%!-- Selected item display --%>
      <div :if={@selected} class="mt-2">
        <div class="flex items-center justify-between px-3 py-2 bg-blue-50 border border-blue-200 rounded-md">
          <div class="flex-1 min-w-0">
            <div class="text-sm font-medium text-zinc-900 truncate">
              <%= @display_fn.(@selected) %>
            </div>
            <div :if={@subtitle_fn} class="text-xs text-zinc-500 truncate">
              <%= @subtitle_fn.(@selected) %>
            </div>
          </div>
          <button
            type="button"
            phx-click={@clear_event}
            class="ml-2 p-1 text-zinc-400 hover:text-zinc-600 rounded-full hover:bg-blue-100 transition-colors"
            aria-label="Clear selection"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>
      </div>

      <%!-- Search input --%>
      <div :if={!@selected} class="relative mt-2">
        <div class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none">
          <.icon name="hero-magnifying-glass" class="w-4 h-4 text-zinc-400" />
        </div>
        <input
          type="text"
          id={"#{@id}-input"}
          value={@search_value}
          phx-keyup={@search_event}
          phx-debounce={@debounce}
          placeholder={@placeholder}
          autocomplete="off"
          class={[
            "block w-full pl-10 py-2 text-sm rounded-md shadow-sm",
            if(@search_value != "", do: "pr-9", else: "pr-3"),
            "border focus:ring-0 focus:outline-none",
            "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
            @errors == [] && "border-zinc-300 focus:border-zinc-400",
            @errors != [] && "border-rose-400 focus:border-rose-400"
          ]}
        />
        <%!-- Clear search button --%>
        <button
          :if={@search_value != ""}
          type="button"
          phx-click={@clear_event}
          class="absolute inset-y-0 right-0 flex items-center pr-3 text-zinc-400 hover:text-zinc-600 transition-colors"
          aria-label="Clear search"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>

        <%!-- Results dropdown --%>
        <div
          role="listbox"
          class={[
            "absolute z-50 w-full mt-1 bg-white border border-zinc-200 rounded-md shadow-lg max-h-60 overflow-auto",
            "transition-all duration-150 ease-out origin-top",
            if(length(@results) > 0,
              do: "opacity-100 scale-y-100 translate-y-0",
              else: "opacity-0 scale-y-95 -translate-y-1 pointer-events-none"
            )
          ]}
        >
          <ul class="py-1" role="list">
            <li :for={result <- @results} role="option">
              <button
                type="button"
                phx-click={@select_event}
                phx-value-id={@value_fn.(result)}
                class="w-full px-3 py-2 text-left hover:bg-zinc-100 focus:bg-zinc-100 focus:outline-none transition-colors duration-75 cursor-pointer"
              >
                <div class="text-sm font-medium text-zinc-900">
                  <%= @display_fn.(result) %>
                </div>
                <div :if={@subtitle_fn} class="text-xs text-zinc-500">
                  <%= @subtitle_fn.(result) %>
                </div>
              </button>
            </li>
          </ul>
        </div>

        <%!-- No results message --%>
        <div class={[
          "absolute z-50 w-full mt-1 bg-white border border-zinc-200 rounded-md shadow-lg",
          "transition-all duration-150 ease-out origin-top",
          if(
            @search_value != "" && String.length(@search_value) >= @min_chars &&
              length(@results) == 0,
            do: "opacity-100 scale-y-100 translate-y-0",
            else: "opacity-0 scale-y-95 -translate-y-1 pointer-events-none"
          )
        ]}>
          <div class="px-3 py-4 text-sm text-zinc-500 text-center">
            No results found for "<%= @search_value %>"
          </div>
        </div>

        <%!-- Typing hint --%>
        <div class={[
          "absolute z-50 w-full mt-1 bg-white border border-zinc-200 rounded-md shadow-lg",
          "transition-all duration-150 ease-out origin-top",
          if(@search_value != "" && String.length(@search_value) < @min_chars,
            do: "opacity-100 scale-y-100 translate-y-0",
            else: "opacity-0 scale-y-95 -translate-y-1 pointer-events-none"
          )
        ]}>
          <div class="px-3 py-3 text-sm text-zinc-400 text-center">
            Type at least <%= @min_chars %> characters to search
          </div>
        </div>
      </div>

      <%!-- Error messages --%>
      <p :for={msg <- @errors} class="mt-1 text-sm text-rose-600">
        <%= msg %>
      </p>
    </div>
    """
  end
end
