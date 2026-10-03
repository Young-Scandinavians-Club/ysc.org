defmodule YscWeb.Admin.EditingPresence do
  @moduledoc """
  Tracks which admins currently have a given post/newsletter/event editor open.

  Presence metadata is resolved once at `track/4` time (name + avatar URL) so
  rendering never needs a DB hit — editor pages and their listing pages both
  read from the same per-resource-type topic.

  Listing pages should call `refresh_list_stream/3` from their `presence_diff`
  handler instead of copying the stream-insert + editors-assign loop.
  Editor pages should call `assign_editors/3`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream_insert: 3]

  alias Ysc.Accounts.UserDisplay
  alias YscWeb.Presence

  @type resource_type :: :post | :newsletter | :event

  @spec topic(resource_type()) :: String.t()
  def topic(:post), do: "presence:posts"
  def topic(:newsletter), do: "presence:newsletters"
  def topic(:event), do: "presence:events"

  @doc "Subscribes the current process to presence diffs for a resource type."
  def subscribe(type), do: Phoenix.PubSub.subscribe(Ysc.PubSub, topic(type))

  @doc "Tracks the current LiveView as editing `resource_id`."
  def track(socket, type, resource_id, user) do
    Presence.track(self(), topic(type), socket.id, %{
      user_id: user.id,
      name: UserDisplay.full_name(user),
      avatar_url: Ysc.Avatars.display_avatar_url(user, :thumb),
      resource_id: resource_id
    })
  end

  @doc "Stops tracking the current LiveView (e.g. before switching resource_id)."
  def untrack(socket, type),
    do: Presence.untrack(self(), topic(type), socket.id)

  @doc """
  Everyone currently editing `resource_id`, deduped by user, excluding `current_user_id`.
  """
  def editors(type, resource_id, current_user_id) do
    type
    |> topic()
    |> Presence.list()
    |> Enum.flat_map(fn {_key, %{metas: metas}} -> metas end)
    |> Enum.filter(
      &(&1.resource_id == resource_id && &1.user_id != current_user_id)
    )
    |> Enum.uniq_by(& &1.user_id)
  end

  @doc """
  Map of `resource_id => deduped editor list` for every resource of `type`
  currently being edited, excluding `current_user_id`. Used by listing pages.
  """
  def editors_by_resource(type, current_user_id) do
    type
    |> topic()
    |> Presence.list()
    |> Enum.flat_map(fn {_key, %{metas: metas}} -> metas end)
    |> Enum.filter(&(&1.user_id != current_user_id))
    |> Enum.uniq_by(&{&1.resource_id, &1.user_id})
    |> Enum.group_by(& &1.resource_id)
  end

  @doc """
  Resource ids touched by a `presence_diff` broadcast's payload (joins and/or
  leaves). Lets listing pages re-render only the rows actually affected by a
  diff instead of the whole page.
  """
  @spec diff_resource_ids(%{joins: map(), leaves: map()}) :: [term()]
  def diff_resource_ids(%{joins: joins, leaves: leaves}) do
    (Map.values(joins) ++ Map.values(leaves))
    |> Enum.flat_map(fn %{metas: metas} -> metas end)
    |> Enum.map(& &1.resource_id)
    |> Enum.uniq()
  end

  @doc """
  Ids from a `presence_diff` payload that are currently on the listing page.

  `by_id` is the `%{id => item}` assign the listing keeps for visible rows.
  """
  def visible_diff_ids(payload, by_id) when is_map(by_id) do
    payload
    |> diff_resource_ids()
    |> Enum.filter(&Map.has_key?(by_id, &1))
  end

  @doc """
  Assigns `:editors` for a single resource currently open in an editor LiveView.

  Pass `nil` (or a non-binary id) when the resource is not persisted yet —
  that clears the assign to `[]` without hitting Presence.
  """
  def assign_editors(socket, type, resource_id)
      when type in [:post, :newsletter, :event] do
    editor_list =
      case resource_id do
        id when is_binary(id) ->
          editors(type, id, socket.assigns.current_user.id)

        _ ->
          []
      end

    assign(socket, :editors, editor_list)
  end

  @doc """
  Refreshes listing-page presence avatars after a `presence_diff`.

  Recomputes the `editors` assign from Presence, then `stream_insert`s only
  rows whose presence actually changed *and* that are currently on the page
  (looked up in the `by_id` assign). Other rows need neither a DB hit nor a
  stream touch — content inside a `phx-update="stream"` container only
  updates via explicit stream operations.

  ## Options

    * `:resource` — `:post | :newsletter | :event`
    * `:stream` — stream name, e.g. `:events`
    * `:by_id` — assign holding `%{id => item}` for the current page
    * `:editors` — assign to store `editors_by_resource/2`
    * `:visible?` — when `false`, still updates the editors assign but skips
      stream inserts (e.g. newsletters when not on the editions tab).
      Defaults to `true`.

  ## Usage

      def handle_info(
            %Phoenix.Socket.Broadcast{event: "presence_diff", payload: payload},
            socket
          ) do
        {:noreply,
         EditingPresence.refresh_list_stream(socket, payload,
           resource: :event,
           stream: :events,
           by_id: :events_by_id,
           editors: :editors_by_event
         )}
      end
  """
  def refresh_list_stream(socket, payload, opts) do
    resource = Keyword.fetch!(opts, :resource)
    stream = Keyword.fetch!(opts, :stream)
    by_id_key = Keyword.fetch!(opts, :by_id)
    editors_key = Keyword.fetch!(opts, :editors)
    visible? = Keyword.get(opts, :visible?, true)

    editors_by = editors_by_resource(resource, socket.assigns.current_user.id)
    by_id = Map.fetch!(socket.assigns, by_id_key)

    changed_ids =
      if visible? do
        visible_diff_ids(payload, by_id)
      else
        []
      end

    changed_ids
    |> Enum.reduce(socket, fn id, acc ->
      stream_insert(acc, stream, Map.fetch!(by_id, id))
    end)
    |> assign(editors_key, editors_by)
  end
end
