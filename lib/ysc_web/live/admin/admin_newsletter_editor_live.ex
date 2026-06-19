defmodule YscWeb.AdminNewsletterEditorLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents

  alias Ysc.Newsletter
  alias Ysc.Newsletter.Edition
  alias Ysc.Posts
  alias Ysc.Events
  alias Ysc.Media
  alias Ysc.Repo
  alias Phoenix.LiveView.JS
  alias HtmlSanitizeEx.Scrubber
  alias YscWeb.Emails.NewsletterEdition

  @auto_save_debounce_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Newsletter")
     |> assign(:active_page, :newsletters)
     |> assign(:post_results, [])
     |> assign(:event_results, [])
     |> assign(:selected_post_ids, [])
     |> assign(:selected_event_ids, [])
     |> assign(:preview_posts, [])
     |> assign(:preview_events, [])
     |> assign(:show_send_modal, false)
     |> assign(:show_schedule_modal, false)
     |> assign(:schedule_datetime, nil)
     |> assign(:auto_save_timer, nil)
     |> assign(:last_saved_at, nil)
     |> assign(:saving?, false)
     |> assign(:preview_cover_image_id, nil)
     |> assign(:preview_ready?, false)
     |> assign(:post_visible_count, 10)
     |> assign(:event_visible_count, 10)
     |> assign(:readonly?, false)
     |> assign(:email_stats, nil)
     |> assign(:click_stats, nil)
     |> assign(:loading_edition?, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:edition, nil)
    |> assign(:readonly?, false)
    |> assign(:loading_edition?, false)
    |> assign_form_from_edition(build_new_edition())
    |> assign(:post_results, [])
    |> assign(:event_results, [])
    |> assign(:picker_data_loaded?, false)
    |> assign(:picker_load_started?, false)
    |> maybe_start_async_load_picker()
    |> assign_preview_data()
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if connected?(socket) do
      socket
      |> assign(:loading_edition?, true)
      |> assign(:edition, nil)
      |> assign(:readonly?, false)
      |> assign(:selected_post_ids, [])
      |> assign(:selected_event_ids, [])
      |> assign(:preview_ready?, false)
      |> assign(:post_results, [])
      |> assign(:event_results, [])
      |> assign(:picker_data_loaded?, false)
      |> assign(:picker_load_started?, false)
      |> assign_form_from_edition(build_placeholder_edition())
      |> start_async(:load_edition, fn -> Newsletter.get_edition!(id) end)
      |> maybe_start_async_load_picker()
    else
      socket
      |> assign(:loading_edition?, true)
      |> assign(:edition, nil)
      |> assign(:readonly?, false)
      |> assign(:selected_post_ids, [])
      |> assign(:selected_event_ids, [])
      |> assign(:preview_ready?, false)
      |> assign(:post_results, [])
      |> assign(:event_results, [])
      |> assign(:picker_data_loaded?, false)
      |> assign(:picker_load_started?, false)
      |> assign_form_from_edition(build_placeholder_edition())
    end
  end

  defp apply_loaded_edition(socket, edition) do
    socket
    |> assign(:loading_edition?, false)
    |> assign(:edition, edition)
    |> assign(:readonly?, edition.status == :sent)
    |> assign(:selected_post_ids, edition.post_ids || [])
    |> assign(:selected_event_ids, edition.event_ids || [])
    |> assign_form_from_edition(edition)
    |> maybe_load_email_stats(edition)
    |> assign_preview_data()
  end

  defp maybe_load_email_stats(socket, %Edition{status: :sent, id: edition_id})
       when is_binary(edition_id) do
    if connected?(socket) do
      start_async(socket, :load_email_stats, fn ->
        %{
          by_type: Newsletter.count_email_events_by_type(edition_id),
          by_link: Newsletter.count_clicks_by_link(edition_id)
        }
      end)
    else
      socket
    end
  end

  defp maybe_load_email_stats(socket, _edition), do: socket

  defp maybe_start_async_load_picker(socket) do
    if connected?(socket) do
      socket
      |> assign(:picker_load_started?, true)
      |> start_async(:load_picker_data, fn ->
        # Load posts and events in parallel (each uses a single query + preload)
        task_posts = Task.async(fn -> Posts.list_posts(50) end)

        task_events =
          Task.async(fn -> Events.list_upcoming_events_with_preload(50) end)

        %{
          posts: Task.await(task_posts, 15_000),
          events: Task.await(task_events, 15_000)
        }
      end)
    else
      socket
    end
  end

  defp build_new_edition do
    %Edition{
      title: "",
      subject: "",
      intro_text: "",
      post_ids: [],
      event_ids: [],
      status: :draft
    }
    |> Edition.changeset(%{})
  end

  defp build_placeholder_edition do
    %Edition{post_ids: [], event_ids: []}
    |> Edition.changeset(%{"title" => "", "subject" => "", "intro_text" => ""})
  end

  defp assign_form_from_edition(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "edition"))
  end

  defp assign_form_from_edition(socket, %Edition{} = edition) do
    changeset = Edition.changeset(edition, edition_to_params(edition))
    assign(socket, form: to_form(changeset, as: "edition"))
  end

  defp edition_to_params(edition) do
    %{
      "title" => edition.title,
      "subject" => edition.subject,
      "intro_text" => edition.intro_text,
      "cover_image_id" => edition.cover_image_id,
      "post_ids" => edition.post_ids || [],
      "event_ids" => edition.event_ids || []
    }
  end

  defp assign_preview_data(socket) do
    post_ids = socket.assigns.selected_post_ids
    event_ids = socket.assigns.selected_event_ids

    raw_cover =
      get_in(socket.assigns.form.params, ["cover_image_id"]) ||
        get_edition_cover(socket)

    cover_image_id = present_cover_image_id(raw_cover)

    # Only re-fetch posts/events from the DB when the selected IDs changed.
    preview_posts =
      if post_ids == Map.get(socket.assigns, :_cached_post_ids) do
        socket.assigns.preview_posts
      else
        Posts.list_posts_by_ids(post_ids, [:featured_image])
      end

    preview_events =
      if event_ids == Map.get(socket.assigns, :_cached_event_ids) do
        socket.assigns.preview_events
      else
        Events.list_events_by_ids(event_ids,
          preloads: [:cover_image, :ticket_tiers]
        )
      end

    cover_image_url =
      if cover_image_id == socket.assigns.preview_cover_image_id do
        Map.get(socket.assigns, :_cached_cover_url)
      else
        preview_cover_image_url(cover_image_id)
      end

    intro_raw = get_in(socket.assigns.form.params, ["intro_text"])

    intro_preview =
      if is_binary(intro_raw) and String.trim(intro_raw) != "" do
        scrub_intro_for_preview(intro_raw)
      else
        nil
      end

    form = socket.assigns.form
    title = Phoenix.HTML.Form.input_value(form, :title) || ""
    intro_text = intro_raw || ""

    preview_assigns =
      NewsletterEdition.build_preview_assigns(
        title,
        intro_text,
        cover_image_url,
        preview_posts,
        preview_events
      )

    preview_html =
      try do
        NewsletterEdition.render(preview_assigns)
      rescue
        _ ->
          "<p style=\"padding: 1rem; color: #71717a;\">Preview unavailable.</p>"
      end

    # Only push the HTML to the client when it actually changed.
    prev_hash = Map.get(socket.assigns, :_preview_hash)
    new_hash = :erlang.phash2(preview_html)

    socket =
      if new_hash != prev_hash do
        socket
        |> assign(:_preview_hash, new_hash)
        |> push_event("preview-html", %{html: preview_html})
      else
        socket
      end

    socket
    |> assign(:preview_posts, preview_posts)
    |> assign(:preview_events, preview_events)
    |> assign(:preview_cover_image_id, cover_image_id)
    |> assign(:_cached_post_ids, post_ids)
    |> assign(:_cached_event_ids, event_ids)
    |> assign(:_cached_cover_url, cover_image_url)
    |> assign(:intro_preview, intro_preview)
    |> assign(:preview_ready?, true)
  end

  defp preview_cover_image_url(nil), do: nil

  defp preview_cover_image_url(image_id) do
    case Repo.get(Media.Image, image_id) do
      nil ->
        nil

      img ->
        path = Media.Image.display_path(img)

        if path && String.starts_with?(path, "/"),
          do: YscWeb.Endpoint.url() <> path,
          else: path
    end
  end

  # html is passed through HtmlSanitizeEx.Scrubber.BasicHTML before being marked
  # safe; content is admin-authored only.
  # sobelow_skip ["XSS.Raw"]
  defp scrub_intro_for_preview(html) when is_binary(html) do
    html |> Scrubber.scrub(Scrubber.BasicHTML) |> Phoenix.HTML.raw()
  end

  defp get_edition_cover(socket) do
    case socket.assigns[:edition] do
      %Edition{cover_image_id: id} when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  # Empty string from form params would hide the upload; treat as no cover.
  defp present_cover_image_id(id) when is_binary(id) and id != "", do: id
  defp present_cover_image_id(_), do: nil

  # Explicit check so upload shows whenever we don't have a valid cover id (nil, "", or other).
  def has_cover_image?(id) when is_binary(id) and id != "", do: true
  def has_cover_image?(_), do: false

  # 1-based position in the selection list, or nil if not selected.
  def selected_position(ids, item_id) when is_list(ids) do
    case Enum.find_index(ids, &(&1 == to_string(item_id))) do
      nil -> nil
      idx -> idx + 1
    end
  end

  # Returns [{1-based_position, item}, ...] in selection order, skipping items not yet loaded.
  def selected_items_in_order(all_items, selected_ids) do
    selected_ids
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {id, pos} ->
      case Enum.find(all_items, &(to_string(&1.id) == id)) do
        nil -> []
        item -> [{pos, item}]
      end
    end)
  end

  def edition_status_badge_type(:draft), do: "yellow"
  def edition_status_badge_type(:scheduled), do: "sky"
  def edition_status_badge_type(:sent), do: "green"
  def edition_status_badge_type(_), do: "dark"

  def edition_status_label(:draft), do: "Draft"
  def edition_status_label(:scheduled), do: "Scheduled"
  def edition_status_label(:sent), do: "Sent"

  def edition_status_label(other),
    do: other |> to_string() |> String.capitalize()

  def format_count(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.join()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex items-center gap-3 py-6">
        <.link
          navigate={~p"/admin/newsletters"}
          class="text-zinc-600 hover:text-zinc-900 text-sm flex items-center gap-1"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to Newsletters
        </.link>
        <.badge :if={@edition} type={edition_status_badge_type(@edition.status)}>
          {edition_status_label(@edition.status)}
        </.badge>
        <.badge :if={!@edition} type="yellow">Draft</.badge>
        <.admin_help_link
          topic="newsletters/compose"
          label="Compose help"
          role={@admin_role}
          class="ms-auto"
        />
      </div>

      <%!-- Sent stats banner (readonly editions only) --%>
      <div
        :if={@readonly?}
        class="mb-6 rounded-xl border border-green-200 bg-green-50 px-5 py-4"
      >
        <div class="flex items-center gap-2 mb-3">
          <.icon name="hero-check-circle" class="w-5 h-5 text-green-600 shrink-0" />
          <p class="text-sm font-semibold text-green-800">
            Newsletter sent — editing is disabled
          </p>
        </div>
        <%!-- Delivery & engagement summary --%>
        <div class="flex flex-wrap gap-x-8 gap-y-3 mb-4">
          <div>
            <p class="text-[11px] font-medium uppercase tracking-wide text-green-600">
              Sent at
            </p>
            <p class="text-sm font-semibold text-green-900 mt-0.5">
              <%= if @edition.sent_at do %>
                <span
                  id="edition-sent-at"
                  phx-hook="LocalTime"
                  phx-update="ignore"
                  data-utc-time={DateTime.to_iso8601(@edition.sent_at)}
                >
                  {Calendar.strftime(@edition.sent_at, "%B %-d, %Y")}
                  <span class="font-normal text-green-700">
                    at {Calendar.strftime(@edition.sent_at, "%-I:%M %p")} UTC
                  </span>
                </span>
              <% else %>
                —
              <% end %>
            </p>
          </div>
          <div>
            <p class="text-[11px] font-medium uppercase tracking-wide text-green-600">
              Emails sent
            </p>
            <p class="text-sm font-semibold text-green-900 mt-0.5">
              {format_count(@edition.sent_count || 0)}
            </p>
          </div>
          <%= cond do %>
            <% is_nil(@email_stats) -> %>
              <div class="flex items-center gap-2 text-sm text-green-700">
                <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" />
                Loading stats…
              </div>
            <% @email_stats == :error -> %>
              <div class="flex items-center gap-2 text-sm text-amber-700">
                <.icon name="hero-exclamation-triangle" class="w-4 h-4 shrink-0" />
                Stats could not be loaded
              </div>
            <% true -> %>
              <div>
                <p class="text-[11px] font-medium uppercase tracking-wide text-green-600">
                  Unique opens
                </p>
                <p class="text-sm font-semibold text-green-900 mt-0.5">
                  {format_count(Map.get(@email_stats, "open", 0))}
                  <%= if (@edition.sent_count || 0) > 0 do %>
                    <span class="font-normal text-green-700">
                      ({Float.round(
                        Map.get(@email_stats, "open", 0) / @edition.sent_count *
                          100,
                        1
                      )}%)
                    </span>
                  <% end %>
                </p>
              </div>
              <div>
                <p class="text-[11px] font-medium uppercase tracking-wide text-green-600">
                  Unique clickers
                </p>
                <p class="text-sm font-semibold text-green-900 mt-0.5">
                  {format_count(Map.get(@email_stats, "click", 0))}
                  <%= if (@edition.sent_count || 0) > 0 do %>
                    <span class="font-normal text-green-700">
                      ({Float.round(
                        Map.get(@email_stats, "click", 0) / @edition.sent_count *
                          100,
                        1
                      )}%)
                    </span>
                  <% end %>
                </p>
              </div>
              <div>
                <p class="text-[11px] font-medium uppercase tracking-wide text-green-600">
                  Bounces
                </p>
                <p class="text-sm font-semibold text-green-900 mt-0.5">
                  {format_count(Map.get(@email_stats, "bounce", 0))}
                  <%= if (@edition.sent_count || 0) > 0 do %>
                    <span class="font-normal text-green-700">
                      ({Float.round(
                        Map.get(@email_stats, "bounce", 0) / @edition.sent_count *
                          100,
                        1
                      )}%)
                    </span>
                  <% end %>
                </p>
              </div>
          <% end %>
        </div>
        <%!-- Link click breakdown --%>
        <%= if is_list(@click_stats) and @click_stats != [] do %>
          <div class="border-t border-green-200 pt-4">
            <p class="text-[11px] font-medium uppercase tracking-wide text-green-600 mb-2">
              Clicks by link
            </p>
            <div class="space-y-2">
              <%= for %{url: url, clicks: clicks, title: title, type: type} <- @click_stats do %>
                <div class="flex items-start gap-3 text-sm">
                  <span class="font-semibold text-green-900 shrink-0 tabular-nums w-8 text-right pt-0.5">
                    {clicks}
                  </span>
                  <div class="min-w-0">
                    <%= if title do %>
                      <div class="flex items-center gap-1.5 flex-wrap">
                        <span class={[
                          "inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide shrink-0",
                          type == :event && "bg-purple-100 text-purple-800",
                          type == :post && "bg-sky-100 text-sky-700"
                        ]}>
                          {if(type == :event, do: "Event", else: "Post")}
                        </span>
                        <a
                          href={url}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="font-medium text-green-900 hover:underline truncate"
                          title={url}
                        >
                          {title}
                        </a>
                      </div>
                      <p
                        class="text-green-600 truncate text-xs mt-0.5 max-w-xs lg:max-w-lg"
                        title={url}
                      >
                        {url}
                      </p>
                    <% else %>
                      <a
                        href={url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="text-green-700 hover:text-green-900 hover:underline truncate block max-w-xs lg:max-w-lg"
                        title={url}
                      >
                        {url}
                      </a>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Mobile tab switcher (hidden on lg+) --%>
      <div class="flex lg:hidden bg-zinc-100 rounded-lg p-1 gap-1 mb-4">
        <button
          id="tab-editor-btn"
          type="button"
          phx-click={
            JS.show(to: "#editor-panel")
            |> JS.hide(to: "#preview-panel")
            |> JS.add_class("bg-white shadow-sm text-zinc-900",
              to: "#tab-editor-btn"
            )
            |> JS.remove_class("bg-white shadow-sm text-zinc-900",
              to: "#tab-preview-btn"
            )
          }
          class="flex-1 text-sm font-medium py-1.5 px-3 rounded text-zinc-900 bg-white shadow-sm transition"
        >
          Editor
        </button>
        <button
          id="tab-preview-btn"
          type="button"
          phx-click={
            JS.hide(to: "#editor-panel")
            |> JS.show(to: "#preview-panel")
            |> JS.add_class("bg-white shadow-sm text-zinc-900",
              to: "#tab-preview-btn"
            )
            |> JS.remove_class("bg-white shadow-sm text-zinc-900",
              to: "#tab-editor-btn"
            )
          }
          class="flex-1 text-sm font-medium py-1.5 px-3 rounded text-zinc-500 transition"
        >
          Preview
        </button>
      </div>

      <div
        class="grid grid-cols-1 lg:grid-cols-2 gap-8"
        phx-mounted={JS.push("load-picker-data")}
      >
        <%!-- Left: Editor --%>
        <div id="editor-panel" class="space-y-6 pb-24">
          <div
            :if={@loading_edition?}
            id="newsletter-editor-loading"
            class="flex items-center justify-center py-24 text-zinc-500 text-sm"
          >
            <.icon name="hero-arrow-path" class="w-6 h-6 animate-spin mr-2" />
            Loading newsletter…
          </div>
          <div :if={!@loading_edition?} class="space-y-6">
            <div class="border border-zinc-200 rounded-lg p-4 bg-white">
              <h2 class="text-lg font-semibold text-zinc-800 mb-4">Cover photo</h2>
              <div :if={@readonly?}>
                <%= if has_cover_image?(@preview_cover_image_id) do %>
                  <.live_component
                    module={YscWeb.Components.Image}
                    id="newsletter-cover-preview"
                    image_id={@preview_cover_image_id}
                    preferred_type={:optimized}
                  />
                <% else %>
                  <p class="text-sm text-zinc-400 italic">No cover photo</p>
                <% end %>
              </div>
              <div :if={!@readonly?}>
                <.live_component
                  module={YscWeb.MediaPickerComponent}
                  id={:newsletter_cover}
                  user_id={@current_user.id}
                  image_id={@preview_cover_image_id}
                />
              </div>
            </div>

            <.form
              for={@form}
              id="newsletter-editor-form"
              phx-change={if(!@readonly?, do: "validate")}
              phx-submit={if(!@readonly?, do: "save-draft")}
              class="space-y-6"
            >
              <%!-- Hidden field keeps cover_image_id in phx-change params so auto-save never clobbers it --%>
              <.input type="hidden" field={@form[:cover_image_id]} />
              <div class="border border-zinc-200 rounded-lg p-4 bg-white">
                <h2 class="text-lg font-semibold text-zinc-800 mb-4">
                  Headline & subject
                </h2>
                <div class="space-y-4">
                  <.input
                    field={@form[:title]}
                    type="text"
                    label="Title (e.g. Winter Update)"
                    phx-debounce="600"
                    disabled={@readonly?}
                  />
                  <div>
                    <.input
                      field={@form[:subject]}
                      type="text"
                      label="Email subject line"
                      phx-debounce="600"
                      disabled={@readonly?}
                    />
                    <% subject_len =
                      String.length(
                        to_string(
                          Phoenix.HTML.Form.input_value(@form, :subject) || ""
                        )
                      ) %>
                    <p class={[
                      "text-xs mt-1 text-right tabular-nums",
                      if(subject_len > 60,
                        do: "text-amber-500 font-medium",
                        else: "text-zinc-400"
                      )
                    ]}>
                      {subject_len} / 60 characters
                    </p>
                  </div>
                </div>
              </div>

              <div class="border border-zinc-200 rounded-lg overflow-hidden bg-white">
                <div class="px-4 pt-4 pb-3">
                  <h2 class="text-lg font-semibold text-zinc-800 mb-1">
                    Intro text
                  </h2>
                  <p class="text-sm text-zinc-500">
                    Opening section. Use the toolbar for bold, links, lists, and more.
                  </p>
                </div>
                <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none">
                  <.input
                    type="hidden"
                    id="edition_intro_text"
                    field={@form[:intro_text]}
                    phx-hook="TrixHook"
                    phx-debounce="800"
                  />
                  <.live_component
                    module={YscWeb.TrixImagePickerComponent}
                    id={:newsletter_intro_image_picker}
                    target_input_id="edition_intro_text"
                    disabled?={@readonly?}
                  />
                  <div
                    id="newsletter-intro-richtext"
                    class="relative"
                    phx-update="ignore"
                  >
                    <trix-editor
                      input="edition_intro_text"
                      class="trix-content block px-4 py-2 bg-white border-0 border-t border-zinc-200 focus:ring-1 focus:ring-blue-400 focus:border-blue-400 transition text-wrap min-h-[200px]"
                      placeholder="Write your opening section..."
                    >
                    </trix-editor>
                    <%!-- Transparent overlay prevents all interaction when readonly --%>
                    <div
                      :if={@readonly?}
                      class="absolute inset-0 z-10 cursor-not-allowed"
                      aria-hidden="true"
                    />
                  </div>
                </div>
              </div>

              <div class="border border-zinc-200 rounded-lg p-4 bg-white">
                <h2 class="text-lg font-semibold text-zinc-800 mb-2">
                  Latest news (posts)
                </h2>
                <p :if={!@readonly?} class="text-sm text-zinc-500 mb-3">
                  Click to select or deselect posts to feature. Selected order is preserved.
                </p>
                <div
                  :if={!@picker_data_loaded? && !@readonly?}
                  class="flex items-center justify-center py-12 text-zinc-500 text-sm"
                >
                  <.icon name="hero-arrow-path" class="w-6 h-6 animate-spin mr-2" />
                  Loading posts…
                </div>
                <div :if={@picker_data_loaded? && !@readonly?}>
                  <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-3">
                    <%= for post <- Enum.take(@post_results, @post_visible_count) do %>
                      <% selected? = to_string(post.id) in @selected_post_ids %>
                      <button
                        type="button"
                        phx-click="toggle-post"
                        phx-value-id={post.id}
                        class={[
                          "group text-left transition-all focus:outline-none rounded-xl",
                          if(selected?,
                            do: "ring-2 ring-blue-500 ring-offset-2",
                            else:
                              "hover:ring-2 hover:ring-zinc-300 hover:ring-offset-1"
                          )
                        ]}
                      >
                        <div class="relative aspect-square rounded-lg overflow-hidden bg-zinc-100">
                          <%= if post.featured_image do %>
                            <img
                              src={image_url(post.featured_image)}
                              alt=""
                              class="w-full h-full object-cover"
                            />
                          <% end %>
                          <div class={[
                            "absolute inset-0 transition-opacity duration-150",
                            if(selected?, do: "bg-blue-600/20", else: "opacity-0")
                          ]} />
                          <span
                            :if={selected_position(@selected_post_ids, post.id)}
                            class="absolute top-1.5 right-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-blue-600 text-[10px] font-bold text-white shadow-sm"
                          >
                            {selected_position(@selected_post_ids, post.id)}
                          </span>
                        </div>
                        <p class={[
                          "mt-1.5 px-0.5 text-[11px] leading-tight line-clamp-2",
                          if(selected?,
                            do: "font-semibold text-blue-700",
                            else: "font-medium text-zinc-600"
                          )
                        ]}>
                          {post.title}
                        </p>
                      </button>
                    <% end %>
                  </div>
                  <.admin_dashed_more_button
                    :if={length(@post_results) > @post_visible_count}
                    phx-click="show-more-posts"
                  >
                    Show more ({length(@post_results) - @post_visible_count} remaining)
                  </.admin_dashed_more_button>
                </div>
                <div
                  :if={@selected_post_ids != [] && @picker_data_loaded?}
                  class="mt-3 pt-3 border-t border-zinc-100 space-y-1.5"
                >
                  <p class="text-xs font-medium text-zinc-500 mb-1.5 uppercase tracking-wide">
                    Selected ({length(@selected_post_ids)})
                  </p>
                  <%= for {pos, post} <- selected_items_in_order(@post_results, @selected_post_ids) do %>
                    <div class="flex items-center gap-2 text-sm text-zinc-700">
                      <span class="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-blue-100 text-blue-600 text-xs font-bold tabular-nums">
                        {pos}
                      </span>
                      <span class="truncate">{post.title}</span>
                    </div>
                  <% end %>
                </div>
              </div>

              <div class="border border-zinc-200 rounded-lg p-4 bg-white">
                <h2 class="text-lg font-semibold text-zinc-800 mb-2">
                  Upcoming events
                </h2>
                <p :if={!@readonly?} class="text-sm text-zinc-500 mb-3">
                  Click to select or deselect events to feature. Selected order is preserved.
                </p>
                <div
                  :if={!@picker_data_loaded? && !@readonly?}
                  class="flex items-center justify-center py-12 text-zinc-500 text-sm"
                >
                  <.icon name="hero-arrow-path" class="w-6 h-6 animate-spin mr-2" />
                  Loading events…
                </div>
                <div :if={@picker_data_loaded? && !@readonly?}>
                  <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-3">
                    <%= for event <- Enum.take(@event_results, @event_visible_count) do %>
                      <% selected? = to_string(event.id) in @selected_event_ids %>
                      <button
                        type="button"
                        phx-click="toggle-event"
                        phx-value-id={event.id}
                        class={[
                          "group text-left transition-all focus:outline-none rounded-xl",
                          if(selected?,
                            do: "ring-2 ring-blue-500 ring-offset-2",
                            else:
                              "hover:ring-2 hover:ring-zinc-300 hover:ring-offset-1"
                          )
                        ]}
                      >
                        <div class="relative aspect-square rounded-lg overflow-hidden bg-zinc-100">
                          <%= if event.cover_image do %>
                            <img
                              src={event_image_url(event)}
                              alt=""
                              class="w-full h-full object-cover"
                            />
                          <% end %>
                          <div class={[
                            "absolute inset-0 transition-opacity duration-150",
                            if(selected?, do: "bg-blue-600/20", else: "opacity-0")
                          ]} />
                          <span
                            :if={selected_position(@selected_event_ids, event.id)}
                            class="absolute top-1.5 right-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-blue-600 text-[10px] font-bold text-white shadow-sm"
                          >
                            {selected_position(@selected_event_ids, event.id)}
                          </span>
                        </div>
                        <p class={[
                          "mt-1.5 px-0.5 text-[11px] leading-tight line-clamp-2",
                          if(selected?,
                            do: "font-semibold text-blue-700",
                            else: "font-medium text-zinc-600"
                          )
                        ]}>
                          {event.title}
                        </p>
                      </button>
                    <% end %>
                  </div>
                  <.admin_dashed_more_button
                    :if={length(@event_results) > @event_visible_count}
                    phx-click="show-more-events"
                  >
                    Show more ({length(@event_results) - @event_visible_count} remaining)
                  </.admin_dashed_more_button>
                </div>
                <div
                  :if={@selected_event_ids != [] && @picker_data_loaded?}
                  class="mt-3 pt-3 border-t border-zinc-100 space-y-1.5"
                >
                  <p class="text-xs font-medium text-zinc-500 mb-1.5 uppercase tracking-wide">
                    Selected ({length(@selected_event_ids)})
                  </p>
                  <%= for {pos, event} <- selected_items_in_order(@event_results, @selected_event_ids) do %>
                    <div class="flex items-center gap-2 text-sm text-zinc-700">
                      <span class="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-blue-100 text-blue-600 text-xs font-bold tabular-nums">
                        {pos}
                      </span>
                      <span class="truncate">{event.title}</span>
                    </div>
                  <% end %>
                </div>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Right: Full email preview — sticky, fills viewport minus top anchor (1.5rem) + bottom bar (3.5rem) --%>
        <div
          id="preview-panel"
          class="hidden lg:flex lg:flex-col lg:sticky lg:top-6"
          style="height: calc(100vh - 7.5rem);"
        >
          <div class="flex flex-col h-full rounded-xl border border-zinc-200 overflow-hidden shadow-sm">
            <div class="flex items-center justify-between px-4 py-3 border-b border-zinc-100 bg-zinc-50 shrink-0">
              <h3 class="text-sm font-semibold text-zinc-700">Email Preview</h3>
              <div class="flex items-center gap-3">
                <span class="text-xs text-zinc-400 italic">
                  Shown as: Subscriber
                </span>
                <button
                  :if={@edition}
                  type="button"
                  phx-click="send-test-email"
                  class="flex items-center gap-1.5 text-xs font-medium text-zinc-600 hover:text-zinc-900 bg-white border border-zinc-200 hover:border-zinc-300 rounded-md px-2.5 py-1.5 transition-colors"
                >
                  <.icon name="hero-envelope" class="w-3.5 h-3.5" /> Send test
                </button>
              </div>
            </div>
            <div
              id="preview-scroll-container"
              class="flex-1 overflow-y-auto bg-white"
              phx-update="ignore"
            >
              <iframe
                id="newsletter-email-preview-iframe"
                class="w-full border-0 block"
                style="height: 800px;"
                title="Email preview"
                phx-hook="EmailPreview"
              ></iframe>
            </div>
          </div>
        </div>
      </div>

      <%!-- Sticky bottom bar: autosave status + action buttons --%>
      <div class="sticky bottom-0 left-0 right-0 z-40 flex items-center justify-between gap-4 border-t border-zinc-200 bg-white/95 backdrop-blur-sm px-6 py-3">
        <%!-- Left: status badge + autosave indicator --%>
        <div class="flex items-center gap-3 min-w-0">
          <.badge
            :if={@edition}
            type={edition_status_badge_type(@edition.status)}
            class="hidden sm:inline-block shrink-0"
          >
            {edition_status_label(@edition.status)}
          </.badge>

          <%!-- Scheduled time indicator --%>
          <span
            :if={@edition && @edition.status == :scheduled && @edition.scheduled_at}
            class="hidden sm:flex items-center gap-1 text-xs text-sky-600 shrink-0"
          >
            <.icon name="hero-clock" class="w-3.5 h-3.5" />
            {Calendar.strftime(@edition.scheduled_at, "%b %-d at %-I:%M %p")} UTC
          </span>

          <%!-- Saving spinner (hidden when readonly) --%>
          <span
            :if={!@readonly?}
            class={[
              "flex items-center gap-1.5 text-xs text-zinc-400 transition-opacity duration-150 shrink-0",
              if(@saving?, do: "opacity-100", else: "opacity-0 pointer-events-none")
            ]}
          >
            <.icon name="hero-arrow-path" class="w-3.5 h-3.5 animate-spin" />
            Saving…
          </span>

          <%!-- Last saved confirmation (hidden when readonly) --%>
          <span
            :if={@last_saved_at && !@saving? && !@readonly?}
            class="flex items-center gap-1.5 text-xs text-zinc-400 shrink-0"
          >
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 shrink-0"></span>
            Saved {Calendar.strftime(@last_saved_at, "%I:%M %p")}
          </span>

          <%!-- Read-only lock indicator --%>
          <span
            :if={@readonly?}
            class="hidden sm:flex items-center gap-1.5 text-xs text-zinc-400 shrink-0"
          >
            <.icon name="hero-lock-closed" class="w-3.5 h-3.5" /> Read-only
          </span>
        </div>

        <%!-- Right: action buttons (hidden when readonly or loading) --%>
        <div
          :if={!@readonly? && !@loading_edition?}
          class="flex items-center gap-2 shrink-0"
        >
          <.button
            type="button"
            variant="outline"
            color="zinc"
            phx-click="open-send-modal"
          >
            <.icon name="hero-paper-airplane" class="w-4 h-4 -mt-0.5 mr-1" />
            Send now
          </.button>
          <.button type="button" color="blue" phx-click="open-schedule-modal">
            <.icon name="hero-clock" class="w-4 h-4 -mt-0.5 mr-1 opacity-80" />
            Schedule
          </.button>
        </div>
      </div>

      <%!-- Send confirmation modal --%>
      <.modal
        :if={@show_send_modal}
        id="send-newsletter-modal"
        show
        on_cancel={JS.push("close-send-modal")}
      >
        <.header>Send newsletter</.header>
        <p class="mt-2 text-zinc-600">
          Send this newsletter to all subscribers now? This cannot be undone.
        </p>
        <div class="mt-6 flex justify-end gap-2">
          <button
            type="button"
            class="rounded-lg px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-100"
            phx-click="close-send-modal"
          >
            Cancel
          </button>
          <button
            type="button"
            class="rounded-lg bg-green-600 text-white px-4 py-2 text-sm font-semibold hover:bg-green-700"
            phx-click="confirm-send"
          >
            Send now
          </button>
        </div>
      </.modal>

      <%!-- Schedule modal --%>
      <.modal
        :if={@show_schedule_modal}
        id="schedule-newsletter-modal"
        show
        on_cancel={JS.push("close-schedule-modal")}
      >
        <.header>Schedule newsletter</.header>
        <.form
          for={%{}}
          id="schedule-form"
          phx-submit="confirm-schedule"
          phx-hook="ScheduleTimezone"
          class="mt-4"
        >
          <input type="hidden" name="timezone" value="Etc/UTC" />
          <.input
            type="datetime-local"
            name="scheduled_at"
            value={@schedule_datetime}
            label="Send at"
            class="w-full"
          />
          <p class="mt-1 text-xs text-zinc-400">
            Timezone: <span data-tz-label>detecting…</span>
          </p>
          <div class="mt-6 flex justify-end gap-2">
            <button
              type="button"
              class="rounded-lg px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-100"
              phx-click="close-schedule-modal"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="rounded-lg bg-blue-600 text-white px-4 py-2 text-sm font-semibold hover:bg-blue-700"
            >
              Schedule
            </button>
          </div>
        </.form>
      </.modal>
    </.side_menu>
    """
  end

  defp image_url(%{optimized_image_path: nil} = img),
    do: img.raw_image_path || "/images/ysc_logo.webp"

  defp image_url(%{optimized_image_path: url}), do: url

  defp event_image_url(%{cover_image: img}), do: image_url(img)

  @impl true
  def handle_event(
        "validate",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("validate", %{"edition" => params}, socket) do
    params =
      params
      |> Map.put("post_ids", socket.assigns.selected_post_ids)
      |> Map.put("event_ids", socket.assigns.selected_event_ids)

    edition = socket.assigns.edition || %Edition{}
    changeset = Edition.changeset(edition, params)

    {:noreply,
     socket
     |> assign(form: to_form(changeset, as: "edition"))
     |> assign(:saving?, true)
     |> assign_preview_data()
     |> schedule_auto_save()}
  end

  # Upload component (and other nested forms) may fire "validate" without "edition" params
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "save-draft",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("save-draft", %{"edition" => params}, socket) do
    socket = assign(socket, :saving?, true)

    params =
      params
      |> Map.take(["title", "subject", "intro_text", "cover_image_id"])
      |> Map.put("post_ids", socket.assigns.selected_post_ids)
      |> Map.put("event_ids", socket.assigns.selected_event_ids)

    result =
      case socket.assigns.edition do
        nil ->
          Newsletter.create_edition_draft(params,
            created_by_id: socket.assigns.current_user.id
          )

        edition ->
          Newsletter.update_edition_draft(edition, params)
      end

    case result do
      {:ok, edition} ->
        {:noreply,
         socket
         |> assign(:edition, edition)
         |> assign_form_from_edition(edition)
         |> assign(:saving?, false)
         |> assign(:last_saved_at, DateTime.utc_now())
         |> assign_preview_data()
         |> then(fn s ->
           if is_nil(s.assigns[:edition]) || s.assigns.edition.id != edition.id do
             push_patch(s, to: ~p"/admin/newsletters/#{edition.id}/edit")
           else
             s
           end
         end)
         |> YscWeb.Flash.put_toast(:info, "Draft saved.", title: "Newsletter")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: "edition"))
         |> assign(:saving?, false)
         |> assign_preview_data()
         |> YscWeb.Flash.put_toast(:error, "Could not save. Check the form.")}
    end
  end

  def handle_event(
        "toggle-post",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("toggle-post", %{"id" => id}, socket) do
    ids =
      if id in socket.assigns.selected_post_ids do
        List.delete(socket.assigns.selected_post_ids, id)
      else
        Enum.uniq(socket.assigns.selected_post_ids ++ [id])
      end

    {:noreply,
     socket
     |> assign(:selected_post_ids, ids)
     |> assign_preview_data()
     |> schedule_auto_save()}
  end

  def handle_event(
        "toggle-event",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("toggle-event", %{"id" => id}, socket) do
    ids =
      if id in socket.assigns.selected_event_ids do
        List.delete(socket.assigns.selected_event_ids, id)
      else
        Enum.uniq(socket.assigns.selected_event_ids ++ [id])
      end

    {:noreply,
     socket
     |> assign(:selected_event_ids, ids)
     |> assign_preview_data()
     |> schedule_auto_save()}
  end

  def handle_event("show-more-posts", _params, socket) do
    {:noreply,
     assign(socket, :post_visible_count, socket.assigns.post_visible_count + 10)}
  end

  def handle_event("show-more-events", _params, socket) do
    {:noreply,
     assign(
       socket,
       :event_visible_count,
       socket.assigns.event_visible_count + 10
     )}
  end

  # Full page load: socket wasn't connected in apply_action; start load when client mounts
  def handle_event("load-picker-data", _params, socket) do
    if socket.assigns.picker_load_started? or socket.assigns.picker_data_loaded? do
      {:noreply, socket}
    else
      {:noreply,
       maybe_start_async_load_picker(
         assign(socket, :picker_load_started?, true)
       )}
    end
  end

  def handle_event(
        "editor-update",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event(
        "editor-update",
        %{"field" => "edition[intro_text]", "value" => value},
        socket
      ) do
    params =
      socket.assigns.form.params
      |> Map.put("intro_text", value)
      |> Map.put("post_ids", socket.assigns.selected_post_ids)
      |> Map.put("event_ids", socket.assigns.selected_event_ids)

    edition = socket.assigns.edition || %Edition{}
    changeset = Edition.changeset(edition, params)

    {:noreply,
     socket
     |> assign(form: to_form(changeset, as: "edition"))
     |> assign_preview_data()
     |> schedule_auto_save()}
  end

  def handle_event("clear-cover", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("send-test-email", _params, socket) do
    edition = socket.assigns.edition
    user = socket.assigns.current_user

    case Newsletter.send_test_email(edition, user) do
      :ok ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :info,
           "Test email sent to #{user.email}."
         )}

      {:error, _reason} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Could not send test email.")}
    end
  end

  def handle_event("open-send-modal", _params, socket) do
    {:noreply, assign(socket, :show_send_modal, true)}
  end

  def handle_event("close-send-modal", _params, socket) do
    {:noreply, assign(socket, :show_send_modal, false)}
  end

  def handle_event("open-schedule-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_schedule_modal, true)
     |> assign(:schedule_datetime, nil)}
  end

  def handle_event("close-schedule-modal", _params, socket) do
    {:noreply, assign(socket, :show_schedule_modal, false)}
  end

  def handle_event("confirm-send", _params, socket) do
    socket = assign(socket, :show_send_modal, false)
    # Ensure we have a saved edition
    case save_then_send(socket) do
      {:ok, socket} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "Sending newsletter…",
           title: "Newsletter"
         )
         |> push_navigate(to: ~p"/admin/newsletters")}

      {:error, socket} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Save the draft first, then send."
         )}
    end
  end

  def handle_event(
        "confirm-schedule",
        %{"scheduled_at" => raw} = params,
        socket
      ) do
    socket = assign(socket, :show_schedule_modal, false)
    tz = Map.get(params, "timezone", "Etc/UTC")

    case parse_schedule_datetime(raw, tz) do
      {:ok, dt} ->
        case save_then_schedule(socket, dt) do
          {:ok, socket} ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(:info, "Newsletter scheduled.",
               title: "Newsletter"
             )
             |> push_navigate(to: ~p"/admin/newsletters")}

          {:error, socket} ->
            {:noreply,
             YscWeb.Flash.put_toast(socket, :error, "Save the draft first.")}
        end

      :error ->
        {:noreply, YscWeb.Flash.put_toast(socket, :error, "Invalid date/time.")}
    end
  end

  defp save_then_send(socket) do
    case persist_edition(socket) do
      {:ok, edition, socket} ->
        case Newsletter.send_edition(edition) do
          {:ok, _} -> {:ok, socket}
          _ -> {:error, socket}
        end

      _ ->
        {:error, socket}
    end
  end

  defp save_then_schedule(socket, scheduled_at) do
    case persist_edition(socket) do
      {:ok, edition, socket} ->
        case Newsletter.schedule_edition(edition, scheduled_at) do
          {:ok, _} -> {:ok, socket}
          _ -> {:error, socket}
        end

      _ ->
        {:error, socket}
    end
  end

  defp persist_edition(socket) do
    params = edition_params_from_socket(socket)

    result =
      case socket.assigns.edition do
        nil ->
          Newsletter.create_edition(params,
            created_by_id: socket.assigns.current_user.id
          )

        edition ->
          Newsletter.update_edition(edition, params)
      end

    case result do
      {:ok, edition} -> {:ok, Newsletter.get_edition!(edition.id), socket}
      _ -> {:error, socket}
    end
  end

  defp edition_params_from_socket(socket, opts \\ []) do
    defaults = Keyword.get(opts, :defaults_for_new, false)
    p = socket.assigns.form.params

    title = p["title"]
    subject = p["subject"]

    {title, subject} =
      if defaults and socket.assigns.edition == nil do
        {title || "Untitled", subject || "Newsletter"}
      else
        {title, subject}
      end

    %{
      "title" => title,
      "subject" => subject,
      "intro_text" => p["intro_text"],
      "cover_image_id" => p["cover_image_id"],
      "post_ids" => socket.assigns.selected_post_ids,
      "event_ids" => socket.assigns.selected_event_ids
    }
  end

  defp schedule_auto_save(socket) do
    if ref = socket.assigns.auto_save_timer do
      Process.cancel_timer(ref)
    end

    ref = Process.send_after(self(), :auto_save, @auto_save_debounce_ms)
    assign(socket, :auto_save_timer, ref)
  end

  defp run_auto_save(socket) do
    socket = assign(socket, :auto_save_timer, nil)
    params = edition_params_from_socket(socket, defaults_for_new: true)

    result =
      case socket.assigns.edition do
        nil ->
          Newsletter.create_edition_draft(params,
            created_by_id: socket.assigns.current_user.id
          )

        edition ->
          Newsletter.update_edition_draft(edition, params)
      end

    case result do
      {:ok, edition} ->
        edition = Newsletter.get_edition!(edition.id)
        was_new = socket.assigns.edition == nil

        # Update edition and preview state but do NOT replace the form: the user may be
        # typing in Trix or other fields; replacing the form would overwrite the hidden
        # input and cause the editor to clear or the layout to glitch.
        socket =
          socket
          |> assign(:edition, edition)
          |> assign(:selected_post_ids, edition.post_ids || [])
          |> assign(:selected_event_ids, edition.event_ids || [])
          |> assign_preview_data()
          |> assign(:last_saved_at, DateTime.utc_now())
          |> assign(:saving?, false)

        if was_new do
          # New edition: redirect to edit URL; the new page load will set the form from the edition.
          {:noreply,
           push_patch(socket, to: ~p"/admin/newsletters/#{edition.id}/edit")}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, assign(socket, :saving?, false)}
    end
  end

  defp parse_schedule_datetime("", _tz), do: :error

  defp parse_schedule_datetime(str, tz) do
    timezone = if is_binary(tz) and tz != "", do: tz, else: "Etc/UTC"

    case NaiveDateTime.from_iso8601(str <> ":00") do
      {:ok, ndt} ->
        ndt
        |> Timex.to_datetime(timezone)
        |> case do
          %DateTime{} = dt ->
            {:ok, Timex.to_datetime(dt, "Etc/UTC")}

          %Timex.AmbiguousDateTime{before: dt} ->
            {:ok, Timex.to_datetime(dt, "Etc/UTC")}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  @impl true
  def handle_async(:load_edition, {:ok, edition}, socket) do
    {:noreply, apply_loaded_edition(socket, edition)}
  end

  def handle_async(:load_edition, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Newsletter edition not found.")
     |> push_navigate(to: ~p"/admin/newsletters")}
  end

  def handle_async(
        :load_picker_data,
        {:ok, %{posts: posts, events: events}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:post_results, posts)
     |> assign(:event_results, events)
     |> assign(:picker_data_loaded?, true)}
  end

  def handle_async(:load_picker_data, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:post_results, [])
     |> assign(:event_results, [])
     |> assign(:picker_data_loaded?, true)}
  end

  def handle_async(
        :load_email_stats,
        {:ok, %{by_type: by_type, by_link: by_link}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:email_stats, by_type)
     |> assign(:click_stats, by_link)}
  end

  def handle_async(:load_email_stats, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:email_stats, :error)
     |> assign(:click_stats, :error)}
  end

  defp normalize_upload_payload({:ok, id}) when is_binary(id), do: id
  defp normalize_upload_payload(id) when is_binary(id), do: id

  @impl true
  def handle_info(:auto_save, %{assigns: %{readonly?: true}} = socket),
    do: {:noreply, socket}

  def handle_info(:auto_save, socket) do
    run_auto_save(socket)
  end

  @impl true
  def handle_info(
        {YscWeb.MediaPickerComponent, _component_id, :cleared},
        socket
      ) do
    params =
      socket.assigns.form.params
      |> Map.put("cover_image_id", nil)

    edition = socket.assigns.edition || %Edition{}
    changeset = Edition.changeset(edition, params)

    {:noreply,
     socket
     |> assign(form: to_form(changeset, as: "edition"))
     |> assign(:preview_cover_image_id, nil)
     |> assign_preview_data()
     |> schedule_auto_save()}
  end

  def handle_info(
        {YscWeb.MediaPickerComponent, _component_id, image_id},
        socket
      ) do
    image_id = normalize_upload_payload(image_id)

    params =
      socket.assigns.form.params
      |> Map.put("cover_image_id", image_id)

    edition = socket.assigns.edition || %Edition{}
    changeset = Edition.changeset(edition, params)

    {:noreply,
     socket
     |> assign(form: to_form(changeset, as: "edition"))
     |> assign_preview_data()
     |> schedule_auto_save()}
  end

  def handle_info({YscWeb.TrixImagePickerComponent, _id, image}, socket) do
    url = Media.Image.display_path(image)

    {:noreply,
     push_event(socket, "insert-trix-image", %{
       url: url,
       href: "#{url}?content-disposition=attachment",
       alt: image.alt_text || image.title || "",
       target_input_id: "edition_intro_text"
     })}
  end
end
