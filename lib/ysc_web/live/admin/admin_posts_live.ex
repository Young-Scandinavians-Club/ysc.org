defmodule YscWeb.AdminPostsLive do
  alias Ysc.Posts.Post

  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

  alias Ysc.Posts

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex justify-between py-6">
        <.admin_page_title>Posts</.admin_page_title>

        <.button id="admin-posts-new-post" navigate={~p"/admin/posts/new"}>
          <.icon name="hero-document-plus" class="w-5 h-5 -mt-0.5" />
          <span class="ms-1">
            New Post
          </span>
        </.button>
      </div>

      <div class="w-full pt-4">
        <div>
          <.admin_search_bar
            id="posts-search-form"
            input_id="posts-search-input"
            name="q"
            value={@search_query}
            placeholder="Search by post title..."
            on_change="search"
            phx-submit="search"
          />
        </div>

        <div class="py-6 w-full">
          <div id="admin-post-filters" class="pb-4 flex">
            <.dropdown id="filter-posts-dropdown" class="group hover:bg-zinc-100">
              <:button_block>
                <.icon
                  name="hero-funnel"
                  class="mr-1 text-zinc-600 w-5 h-5 group-hover:text-zinc-800 -mt-0.5"
                /> Filters
              </:button_block>

              <div class="w-full px-4 py-3">
                <.filter_form
                  fields={[
                    state: [
                      label: "State",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: [
                        {"Published", :published},
                        {"Draft", :draft}
                      ]
                    ],
                    user_id: [
                      label: "Author",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: @author_filter
                    ]
                  ]}
                  meta={@meta}
                  id="posts-filter-form"
                >
                  <div class="mt-4">
                    <p class="block text-sm font-semibold leading-6 text-zinc-800 mb-1">
                      Date Posted
                    </p>
                    <div class="space-y-2">
                      <.input
                        type="date"
                        name="date_from"
                        value={@date_from}
                        label="From"
                        id="filter-date-from"
                        phx-debounce="300"
                      />
                      <.input
                        type="date"
                        name="date_to"
                        value={@date_to}
                        label="To"
                        id="filter-date-to"
                        phx-debounce="300"
                      />
                    </div>
                  </div>
                </.filter_form>
              </div>

              <div class="px-4 py-4">
                <.button
                  id="admin-posts-clear-filters"
                  patch={~p"/admin/posts"}
                  variant="outline"
                  color="zinc"
                  class="w-full justify-center gap-2 py-2 px-3 text-sm font-semibold"
                >
                  <.icon name="hero-x-circle" class="w-5 h-5 -mt-0.5 shrink-0" />
                  Clear filters
                </.button>
              </div>
            </.dropdown>
          </div>
          <%!-- Mobile Card View --%>
          <div class="block md:hidden space-y-4">
            <%= for {_, post} <- @streams.posts do %>
              <div
                class="bg-white rounded-lg border border-zinc-200 p-4 hover:shadow-md transition-shadow cursor-pointer"
                phx-click={JS.navigate(~p"/admin/posts/#{post.id}")}
              >
                <div class="flex items-start justify-between mb-3">
                  <div class="flex-1 min-w-0">
                    <h3 class="text-base font-semibold text-zinc-900 mb-1 flex items-center gap-1.5 min-w-0">
                      <.icon
                        :if={post.featured_post}
                        name="hero-star-solid"
                        class="h-4 w-4 shrink-0 text-yellow-500"
                      />
                      <span class="truncate">{post.title}</span>
                    </h3>
                    <div class="flex items-center gap-2 flex-wrap">
                      <span class="text-sm text-zinc-600">
                        {"#{Ysc.title_case(post.author.first_name)} #{Ysc.title_case(post.author.last_name)}"}
                      </span>
                      <span class="text-zinc-400">•</span>
                      <span class="text-sm text-zinc-600">
                        {Timex.format!(post.inserted_at, "{Mshort} {D}, {YYYY}")}
                      </span>
                    </div>
                  </div>
                  <.post_actions_dropdown
                    post={post}
                    menu_id={"post-actions-mob-#{post.id}"}
                  />
                </div>

                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-3">
                    <.tooltip
                      :if={post.published_on != nil}
                      tooltip_text={
                        Timex.format!(post.published_on, "%b %e, %Y", :strftime)
                      }
                    >
                      <.badge type={post_state_to_badge_style(post.state)}>
                        {String.capitalize("#{post.state}")}
                      </.badge>
                    </.tooltip>

                    <.badge
                      :if={post.published_on == nil}
                      type={post_state_to_badge_style(post.state)}
                    >
                      {String.capitalize("#{post.state}")}
                    </.badge>

                    <span
                      :if={post.comment_count > 0}
                      class="flex items-center gap-1 text-zinc-600 text-sm"
                    >
                      <.icon name="hero-chat-bubble-oval-left" class="w-4 h-4" />
                      {post.comment_count}
                    </span>
                  </div>
                </div>
              </div>
            <% end %>
            <%!-- Mobile Pagination --%>
            <div :if={@meta} class="pt-4">
              <.admin_flop_pagination
                meta={@meta}
                path={~p"/admin/posts?#{non_flop_params(@params)}"}
                density={:compact}
              />
            </div>
          </div>
          <%!-- Desktop Table View --%>
          <div class="hidden md:block">
            <Flop.Phoenix.table
              id="admin_posts_list"
              items={@streams.posts}
              meta={@meta}
              path={~p"/admin/posts?#{non_flop_params(@params)}"}
              row_click={
                fn {_, post} -> JS.navigate(~p"/admin/posts/#{post.id}") end
              }
              opts={[tbody_tr_attrs: [class: "cursor-pointer"]]}
            >
              <:col :let={{_, post}} label="Title" field={:title}>
                <p class="text-sm font-semibold flex items-center gap-1.5">
                  <.icon
                    :if={post.featured_post}
                    name="hero-star-solid"
                    class="h-4 w-4 shrink-0 text-yellow-500"
                  />
                  <span>
                    {post.title}
                    <span
                      :if={post.comment_count > 0}
                      class="relative text-zinc-600 ml-2 rounded px-2 py-1 text-sm"
                    >
                      <.icon
                        name="hero-chat-bubble-oval-left"
                        class="w-4 h-4 -mt-0.5"
                      />
                      {post.comment_count}
                    </span>
                  </span>
                </p>
              </:col>

              <:col :let={{_, post}} label="Author" field={:author_name}>
                {"#{Ysc.title_case(post.author.first_name)} #{Ysc.title_case(post.author.last_name)}"}
              </:col>

              <:col :let={{_, post}} label="State" field={:state}>
                <.tooltip
                  :if={post.published_on != nil}
                  tooltip_text={
                    Timex.format!(post.published_on, "%b %e, %Y", :strftime)
                  }
                >
                  <.badge type={post_state_to_badge_style(post.state)}>
                    {String.capitalize("#{post.state}")}
                  </.badge>
                </.tooltip>

                <.badge
                  :if={post.published_on == nil}
                  type={post_state_to_badge_style(post.state)}
                >
                  {String.capitalize("#{post.state}")}
                </.badge>
              </:col>

              <:col :let={{_, post}} label="Created" field={:inserted_at}>
                {Timex.format!(post.inserted_at, "{Mshort} {D}, {YYYY}")}
              </:col>

              <:action :let={{_, post}}>
                <.post_actions_dropdown
                  post={post}
                  menu_id={"post-actions-dt-#{post.id}"}
                />
              </:action>
            </Flop.Phoenix.table>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  attr :post, :map, required: true
  attr :menu_id, :string, required: true

  def post_actions_dropdown(assigns) do
    ~H"""
    <div class="flex justify-end" onclick="event.stopPropagation()">
      <.dropdown
        id={@menu_id}
        right={true}
        class="min-w-0 !w-auto shrink-0 rounded-md px-1 py-1 text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900"
      >
        <:button_block>
          <span class="sr-only">Post actions</span>
          <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
        </:button_block>

        <div class="w-full divide-y divide-zinc-100 py-1 text-sm text-zinc-700">
          <ul class="py-1">
            <li :if={@post.state == :published}>
              <.link
                id={"#{@menu_id}-view-live"}
                href={~p"/posts/#{@post.id}"}
                target="_blank"
                rel="noopener noreferrer"
                class="flex w-full items-center gap-2 px-4 py-2 text-left transition hover:bg-zinc-100"
              >
                <.icon
                  name="hero-arrow-top-right-on-square"
                  class="h-5 w-5 shrink-0 text-zinc-500"
                />
                <span>View live</span>
              </.link>
            </li>
            <li>
              <.link
                id={"#{@menu_id}-edit"}
                navigate={~p"/admin/posts/#{@post.id}"}
                class="flex w-full items-center gap-2 px-4 py-2 text-left transition hover:bg-zinc-100"
              >
                <.icon
                  name="hero-pencil-square"
                  class="h-5 w-5 shrink-0 text-zinc-500"
                />
                <span>Edit</span>
              </.link>
            </li>
            <li>
              <button
                id={"#{@menu_id}-toggle-featured"}
                type="button"
                phx-click="toggle-featured"
                phx-value-id={@post.id}
                class="flex w-full items-center gap-2 px-4 py-2 text-left transition hover:bg-zinc-100"
              >
                <.icon
                  name={
                    if @post.featured_post, do: "hero-star-solid", else: "hero-star"
                  }
                  class={[
                    "h-5 w-5 shrink-0",
                    if(@post.featured_post,
                      do: "text-yellow-500",
                      else: "text-zinc-500"
                    )
                  ]}
                />
                <span>
                  {if @post.featured_post, do: "Unpin post", else: "Pin post"}
                </span>
              </button>
            </li>
            <li :if={@post.state == :draft}>
              <button
                id={"#{@menu_id}-delete"}
                type="button"
                phx-click="delete-post"
                phx-value-id={@post.id}
                data-confirm="Delete this draft? It will be marked as deleted."
                class="flex w-full items-center gap-2 px-4 py-2 text-left text-red-600 transition hover:bg-zinc-100"
              >
                <.icon name="hero-trash" class="h-5 w-5 shrink-0" />
                <span>Delete</span>
              </button>
            </li>
          </ul>
        </div>
      </.dropdown>
    </div>
    """
  end

  @dialyzer {:nowarn_function, mount: 3}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Posts")
     |> assign(:active_page, :news)
     |> assign(:params, %{})
     |> assign(:search_query, "")
     |> assign(:date_from, "")
     |> assign(:date_to, "")
     |> assign(:author_filter, [])}
  end

  def handle_params(params, _uri, socket) do
    date_from = Map.get(params, "date_from", "")
    date_to = Map.get(params, "date_to", "")

    case Posts.list_posts_paginated(params,
           date_from: date_from,
           date_to: date_to
         ) do
      {:ok, {posts, meta}} ->
        author_filter = Ysc.Posts.get_all_authors()
        title_filter = Enum.find(meta.flop.filters, &(&1.field == :title))
        search_query = if title_filter, do: title_filter.value, else: ""

        {:noreply,
         socket
         |> assign(:meta, meta)
         |> assign(:params, params)
         |> assign(:author_filter, author_filter)
         |> assign(:search_query, search_query)
         |> assign(:date_from, date_from)
         |> assign(:date_to, date_to)
         |> stream(:posts, posts, reset: true)}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: ~p"/admin/posts")}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    existing_filters =
      socket.assigns.meta.flop.filters
      |> Enum.reject(&(&1.field == :title))

    new_filters =
      if q != "" do
        [%Flop.Filter{field: :title, op: :ilike, value: q} | existing_filters]
      else
        existing_filters
      end

    filter_params =
      new_filters
      |> Enum.with_index()
      |> Enum.into(%{}, fn {filter, idx} ->
        {"#{idx}",
         %{
           "field" => "#{filter.field}",
           "op" => "#{filter.op}",
           "value" => "#{filter.value}"
         }}
      end)

    date_from = socket.assigns.date_from
    date_to = socket.assigns.date_to

    new_params =
      %{"filters" => filter_params}
      |> then(fn p ->
        if date_from != "", do: Map.put(p, "date_from", date_from), else: p
      end)
      |> then(fn p ->
        if date_to != "", do: Map.put(p, "date_to", date_to), else: p
      end)

    {:noreply, push_patch(socket, to: ~p"/admin/posts?#{new_params}")}
  end

  def handle_event("clear-search", %{"input-id" => _input_id}, socket) do
    handle_event("search", %{"q" => ""}, socket)
  end

  def handle_event("update-filter", params, socket) do
    date_from = Map.get(params, "date_from", "")
    date_to = Map.get(params, "date_to", "")

    params =
      params
      |> Map.delete("_target")
      |> Map.delete("date_from")
      |> Map.delete("date_to")

    updated_filters =
      Enum.reduce(params["filters"] || %{}, %{}, fn {k, v}, acc ->
        updated = maybe_update_filter(v)

        if updated["value"] in ["", nil] do
          acc
        else
          Map.put(acc, k, updated)
        end
      end)

    title_filter =
      Enum.find(socket.assigns.meta.flop.filters, &(&1.field == :title))

    final_filters =
      if title_filter && title_filter.value != "" do
        next_idx = map_size(updated_filters)

        Map.put(updated_filters, "#{next_idx}", %{
          "field" => "title",
          "op" => "ilike",
          "value" => title_filter.value
        })
      else
        updated_filters
      end

    new_params =
      Map.merge(params, %{"filters" => final_filters})
      |> then(fn p ->
        if date_from != "", do: Map.put(p, "date_from", date_from), else: p
      end)
      |> then(fn p ->
        if date_to != "", do: Map.put(p, "date_to", date_to), else: p
      end)

    {:noreply, push_patch(socket, to: ~p"/admin/posts?#{new_params}")}
  end

  def handle_event("delete-post", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user

    with {:ok, target_id} <- Ecto.ULID.cast(id),
         %Post{} = target <- Posts.get_post(target_id, [:author]),
         :draft <- target.state,
         {:ok, _} <-
           Posts.update_post(
             target,
             %{
               state: :deleted,
               deleted_on: Timex.now(),
               published_on: nil,
               featured_post: false
             },
             current_user
           ) do
      {:noreply,
       socket
       |> stream_delete(:posts, target)
       |> YscWeb.Flash.put_toast(:info, "Post deleted.", title: "Post deleted")}
    else
      :error ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Something went wrong. Please try again.",
           title: "Delete failed"
         )}

      _ ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Only draft posts can be deleted from here.",
           title: "Delete failed"
         )}
    end
  end

  def handle_event("toggle-featured", %{"id" => id}, socket) do
    current_user = socket.assigns[:current_user]

    current_featured = Posts.get_featured_post()
    {:ok, target_id} = Ecto.ULID.cast(id)
    target = Posts.get_post(target_id)

    result =
      cond do
        is_nil(target) ->
          {:error, :not_found}

        current_featured && current_featured.id == target_id ->
          Posts.update_post(
            current_featured,
            %{"featured_post" => false},
            current_user
          )

        true ->
          _ =
            if current_featured,
              do:
                Posts.update_post(
                  current_featured,
                  %{"featured_post" => false},
                  current_user
                )

          Posts.update_post(target, %{"featured_post" => true}, current_user)
      end

    case result do
      {:ok, _} ->
        # Refresh the two possibly affected rows
        updated = Posts.get_post(target_id, [:author])
        socket = maybe_stream_update_post(socket, updated)

        socket =
          case current_featured do
            nil ->
              socket

            cf when cf.id == target_id ->
              socket

            cf ->
              maybe_stream_update_post(socket, Posts.get_post(cf.id, [:author]))
          end

        {:noreply, socket}

      _ ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Could not update featured post"
         )}
    end
  end

  defp maybe_update_filter(%{"value" => [""]} = filter),
    do: Map.replace(filter, "value", "")

  defp maybe_update_filter(filter), do: filter

  defp post_state_to_badge_style(:draft), do: "yellow"
  defp post_state_to_badge_style(:published), do: "green"
  defp post_state_to_badge_style(:deleted), do: "red"
  defp post_state_to_badge_style(_), do: "default"

  defp maybe_stream_update_post(socket, nil), do: socket

  defp maybe_stream_update_post(socket, %Post{} = post) do
    stream_insert(socket, :posts, post)
  end

  @flop_keys ~w(order_by order_directions page page_size limit offset filters)
  defp non_flop_params(params) when is_map(params),
    do: Map.drop(params, @flop_keys)

  defp non_flop_params(_), do: %{}
end
