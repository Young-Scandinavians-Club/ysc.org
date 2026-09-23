defmodule YscWeb.AdminUserSearch do
  @moduledoc """
  Shared LiveView/LiveComponent assign helpers for `<.admin_user_autocomplete>`.

  The picker UI lives in `YscWeb.AdminComponents.admin_user_autocomplete/1`.
  Every admin caller previously copied the same search / select / clear
  assign updates (`:user_search`, `:user_search_results`, `:selected_user`).

  ## Usage

      alias YscWeb.AdminUserSearch

      socket
      |> AdminUserSearch.assign_blank()

      def handle_event("search-users", %{"value" => query}, socket) do
        {:noreply, AdminUserSearch.search(socket, query)}
      end

      def handle_event("select-user", %{"id" => id}, socket) do
        {:noreply, AdminUserSearch.select(socket, id)}
      end

      def handle_event("clear-user", _params, socket) do
        {:noreply, AdminUserSearch.assign_blank(socket)}
      end

  Override assign names when a page hosts more than one picker:

      @grant_user [
        search: :grant_user_search,
        results: :grant_user_results,
        selected: :grant_selected_user
      ]

      AdminUserSearch.search(socket, query, @grant_user)
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ysc.Accounts

  @default_search :user_search
  @default_results :user_search_results
  @default_selected :selected_user
  @default_min_chars 2
  @default_limit 10

  @doc """
  Clears the picker: no selected user, empty query, empty results.

  Used on mount / modal open and for the clear-selection event.
  """
  def assign_blank(socket, opts \\ []) do
    keys = keys(opts)

    socket
    |> assign(keys.selected, nil)
    |> assign(keys.search, "")
    |> assign(keys.results, [])
  end

  @doc """
  Sets an already-loaded user as the selection and clears the query/results.

  Used when editing a record that already has a member attached.
  """
  def assign_selected(socket, user, opts \\ []) do
    keys = keys(opts)

    socket
    |> assign(keys.selected, user)
    |> assign(keys.search, "")
    |> assign(keys.results, [])
  end

  @doc """
  Runs `Accounts.search_users/2` when the query is at least `min_chars`
  (default 2) and assigns the query plus results.
  """
  def search(socket, query, opts \\ []) when is_binary(query) do
    keys = keys(opts)
    min_chars = Keyword.get(opts, :min_chars, @default_min_chars)
    limit = Keyword.get(opts, :limit, @default_limit)

    results =
      if String.length(query) >= min_chars do
        Accounts.search_users(query, limit: limit)
      else
        []
      end

    socket
    |> assign(keys.search, query)
    |> assign(keys.results, results)
  end

  @doc """
  Loads the user with `Accounts.get_user!/1` and selects them.
  """
  def select(socket, id, opts \\ []) do
    assign_selected(socket, Accounts.get_user!(id), opts)
  end

  defp keys(opts) do
    %{
      search: Keyword.get(opts, :search, @default_search),
      results: Keyword.get(opts, :results, @default_results),
      selected: Keyword.get(opts, :selected, @default_selected)
    }
  end
end
