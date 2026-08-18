defmodule YscWeb.Admin.EditingPresence do
  @moduledoc """
  Tracks which admins currently have a given post/newsletter/event editor open.

  Presence metadata is resolved once at `track/4` time (name + avatar URL) so
  rendering never needs a DB hit — editor pages and their listing pages both
  read from the same per-resource-type topic.
  """

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
end
