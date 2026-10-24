defmodule YscWeb.AdminEventSearch do
  @moduledoc """
  Shared LiveView/LiveComponent assign helpers for `<.admin_event_autocomplete>`.

  The picker UI lives in `YscWeb.AdminComponents.admin_event_autocomplete/1`
  and the lookups in `Ysc.Events.Picker`. This module owns the assigns
  (`:event_search`, `:event_search_results`, `:selected_event`,
  `:event_suggestions`), the same way `YscWeb.AdminUserSearch` does for the
  member picker.

  ## Usage

      alias YscWeb.AdminEventSearch

      # Run the suggestions query only once connected.
      socket
      |> AdminEventSearch.assign_blank()
      |> then(&if connected?(&1), do: AdminEventSearch.assign_suggestions(&1), else: &1)

      def handle_event("search-events", %{"value" => query}, socket) do
        {:noreply, AdminEventSearch.search(socket, query)}
      end

      def handle_event("select-event", %{"id" => id}, socket) do
        {:noreply, AdminEventSearch.select(socket, id)}
      end

      def handle_event("clear-event", _params, socket) do
        {:noreply, AdminEventSearch.assign_blank(socket)}
      end

  Override assign names when a page hosts more than one picker, by passing
  `search:`, `results:`, `selected:` or `suggestions:` options to any function.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ysc.Events.Picker

  @default_search :event_search
  @default_results :event_search_results
  @default_selected :selected_event
  @default_suggestions :event_suggestions
  @default_min_chars 2
  @default_limit 10

  @doc """
  Clears the picker: no selected event, empty query, empty results.

  Suggestions are left alone so they can be reused after clearing.
  """
  def assign_blank(socket, opts \\ []) do
    keys = keys(opts)

    socket
    |> assign(keys.selected, nil)
    |> assign(keys.search, "")
    |> assign(keys.results, [])
    |> ensure_suggestions(keys)
  end

  @doc "Loads the events offered before anyone types."
  def assign_suggestions(socket, opts \\ []) do
    assign(socket, keys(opts).suggestions, Picker.suggestions())
  end

  @doc """
  Sets an already-loaded event as the selection and clears the query/results.

  Accepts any map with `id`, `title`, `start_date` and `state`.
  """
  def assign_selected(socket, event, opts \\ []) do
    keys = keys(opts)

    socket
    |> assign(keys.selected, event)
    |> assign(keys.search, "")
    |> assign(keys.results, [])
  end

  @doc """
  Runs `Ysc.Events.Picker.search/2` when the trimmed query is at least
  `min_chars` (default 2) and assigns the query plus results.
  """
  def search(socket, query, opts \\ []) when is_binary(query) do
    keys = keys(opts)
    min_chars = Keyword.get(opts, :min_chars, @default_min_chars)
    limit = Keyword.get(opts, :limit, @default_limit)
    trimmed = String.trim(query)

    results =
      if String.length(trimmed) >= min_chars,
        do: Picker.search(trimmed, limit: limit),
        else: []

    socket
    |> assign(keys.search, query)
    |> assign(keys.results, results)
  end

  @doc """
  Looks the event up and selects it. An event that has since been deleted
  leaves the picker blank.
  """
  def select(socket, id, opts \\ []) do
    case Picker.get(id) do
      nil -> assign_blank(socket, opts)
      event -> assign_selected(socket, event, opts)
    end
  end

  defp ensure_suggestions(socket, keys) do
    if Map.has_key?(socket.assigns, keys.suggestions),
      do: socket,
      else: assign(socket, keys.suggestions, [])
  end

  defp keys(opts) do
    %{
      search: Keyword.get(opts, :search, @default_search),
      results: Keyword.get(opts, :results, @default_results),
      selected: Keyword.get(opts, :selected, @default_selected),
      suggestions: Keyword.get(opts, :suggestions, @default_suggestions)
    }
  end
end
