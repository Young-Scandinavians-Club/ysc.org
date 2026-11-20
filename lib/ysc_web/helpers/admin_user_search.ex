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
  # Autocomplete only renders name/email. Merch order prefill also needs
  # phone. Omits hashed_password, bios, Stripe ids, and the current_avatar
  # preload default `search_users/2` uses for pickers that render photos.
  @autocomplete_user_fields [
    :id,
    :email,
    :first_name,
    :last_name,
    :phone_number
  ]

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

  Passes `:select` so typeahead keystrokes do not SELECT `hashed_password` /
  bios or preload avatars. App members JSON and event-host pickers still use
  the default (full row + avatar).
  """
  def search(socket, query, opts \\ []) when is_binary(query) do
    keys = keys(opts)
    min_chars = Keyword.get(opts, :min_chars, @default_min_chars)
    limit = Keyword.get(opts, :limit, @default_limit)

    results =
      if String.length(query) >= min_chars do
        Accounts.search_users(query,
          limit: limit,
          select: @autocomplete_user_fields
        )
      else
        []
      end

    socket
    |> assign(keys.search, query)
    |> assign(keys.results, results)
  end

  @doc """
  Selects the user from the current search results.

  Search already loaded name/email/phone. A second `Accounts.get_user!/1`
  would SELECT `hashed_password` / bios. Crafted `phx-value` ids still go
  through `get_user!/1`.
  """
  def select(socket, id, opts \\ []) do
    keys = keys(opts)
    results = Map.get(socket.assigns, keys.results, [])

    assign_selected(socket, resolve_selected_user(results, id), opts)
  end

  defp resolve_selected_user(results, id) when is_list(results) do
    match_id = to_string(id)

    case Enum.find(results, fn user -> to_string(user.id) == match_id end) do
      %Accounts.User{} = user -> user
      nil -> Accounts.get_user!(id)
    end
  end

  defp resolve_selected_user(_results, id), do: Accounts.get_user!(id)

  defp keys(opts) do
    %{
      search: Keyword.get(opts, :search, @default_search),
      results: Keyword.get(opts, :results, @default_results),
      selected: Keyword.get(opts, :selected, @default_selected)
    }
  end
end
