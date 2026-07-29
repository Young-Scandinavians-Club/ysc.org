defmodule YscWeb.AdminNewsletterEditorLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents

  alias Ysc.Newsletter
  alias Ysc.Newsletter.Edition
  alias Ysc.Newsletter.Notice
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
    if connected?(socket), do: Newsletter.subscribe_to_edition_updates()

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
     |> assign(:_preview_html, nil)
     |> assign(:post_visible_count, 10)
     |> assign(:event_visible_count, 10)
     |> assign(:readonly?, false)
     |> assign(:email_stats, nil)
     |> assign(:click_stats, nil)
     |> assign(:unsubscribe_link_clicks, nil)
     |> assign(:confirmed_unsubscribes, nil)
     |> assign(:loading_edition?, false)
     |> assign(:saved_notices, [])
     |> assign(:show_notice_picker?, false)
     |> assign(:notice_picker_view, :list)
     |> assign(
       :new_notice_form,
       to_form(Notice.changeset(%Notice{}, %{}), as: :new_notice)
     )
     |> assign(:show_save_notice_modal?, false)
     |> assign(
       :save_notice_form,
       to_form(Notice.changeset(%Notice{}, %{}), as: :save_notice)
     )}
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
    |> maybe_load_saved_notices()
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
      |> maybe_load_saved_notices()
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

  defp maybe_load_saved_notices(socket) do
    if connected?(socket) do
      start_async(socket, :load_saved_notices, fn ->
        Newsletter.list_notices()
      end)
    else
      socket
    end
  end

  defp apply_loaded_edition(socket, edition) do
    socket
    |> assign(:loading_edition?, false)
    |> assign(:edition, edition)
    |> assign(:readonly?, edition_readonly?(edition))
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
          by_link: Newsletter.count_clicks_by_link(edition_id),
          unsubscribe_link_clicks:
            Newsletter.count_unsubscribe_link_clicks(edition_id),
          confirmed_unsubscribes:
            Newsletter.count_confirmed_unsubscribes(edition_id)
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

    edition_sent_at =
      case socket.assigns.edition do
        %{sent_at: sent_at} -> sent_at
        _ -> nil
      end

    preview_assigns =
      NewsletterEdition.build_preview_assigns(
        title,
        intro_text,
        cover_image_url,
        preview_posts,
        preview_events,
        edition_sent_at
      )

    preview_html =
      try do
        NewsletterEdition.render(preview_assigns)
      rescue
        _ ->
          "<p style=\"padding: 1rem; color: #71717a;\">Preview unavailable.</p>"
      end

    previous_hash = Map.get(socket.assigns, :_preview_hash)
    preview_hash = :erlang.phash2(preview_html)
    preview_already_ready? = socket.assigns.preview_ready?

    socket =
      if preview_already_ready? and preview_hash != previous_hash do
        push_event(socket, "preview-html", %{html: preview_html})
      else
        socket
      end

    socket
    |> assign(:_preview_hash, preview_hash)
    |> assign(:_preview_html, preview_html)
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

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :total, :integer, default: 0
  attr :id, :string, default: nil

  defp stat_with_percentage(assigns) do
    ~H"""
    <div id={@id}>
      <p class="text-[11px] font-medium uppercase tracking-wide text-green-600">
        {@label}
      </p>
      <p class="text-sm font-semibold text-green-900 mt-0.5">
        {format_count(@count)}
        <%= if (@total || 0) > 0 do %>
          <span class="font-normal text-green-700">
            ({Float.round(@count / @total * 100, 1)}%)
          </span>
        <% end %>
      </p>
    </div>
    """
  end

  defp newsletter_edition_status_label_with_progress(%Edition{
         status: :sending,
         sent_count: sent_count,
         recipient_count: recipient_count
       })
       when is_integer(recipient_count) do
    "Sending… #{format_count(sent_count || 0)} / #{format_count(recipient_count)}"
  end

  defp newsletter_edition_status_label_with_progress(%Edition{} = edition),
    do: newsletter_edition_status_label(edition.status)

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
        <%= if @edition && @edition.status == :sending do %>
          <span id="newsletter-sending-progress">
            <.admin_sending_badge label={
              newsletter_edition_status_label_with_progress(@edition)
            } />
          </span>
        <% else %>
          <.badge
            :if={@edition}
            type={newsletter_edition_status_badge_type(@edition.status)}
          >
            {newsletter_edition_status_label_with_progress(@edition)}
          </.badge>
        <% end %>
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
              <.stat_with_percentage
                label="Unique opens"
                count={Map.get(@email_stats, "open", 0)}
                total={@edition.sent_count}
              />
              <.stat_with_percentage
                label="Unique clickers"
                count={Map.get(@email_stats, "click", 0)}
                total={@edition.sent_count}
              />
              <.stat_with_percentage
                label="Bounces"
                count={Map.get(@email_stats, "bounce", 0)}
                total={@edition.sent_count}
              />
              <.stat_with_percentage
                id="edition-unsubscribe-link-clicks"
                label="Unsubscribe link clicks"
                count={@unsubscribe_link_clicks || 0}
                total={@edition.sent_count}
              />
              <.stat_with_percentage
                id="edition-confirmed-unsubscribes"
                label="Confirmed unsubscribes"
                count={@confirmed_unsubscribes || 0}
                total={@edition.sent_count}
              />
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
            class="space-y-6"
            role="status"
            aria-live="polite"
          >
            <span class="sr-only">Loading newsletter…</span>
            <div class="border border-zinc-200 rounded-lg p-4 bg-white space-y-3">
              <.skeleton_block class="h-5 w-32 rounded" />
              <.skeleton_block class="h-40 w-full rounded-lg" />
            </div>
            <div class="border border-zinc-200 rounded-lg p-4 bg-white space-y-3">
              <.skeleton_block class="h-5 w-24 rounded" />
              <.skeleton_block class="h-11 w-full rounded-lg" />
              <.skeleton_block class="h-24 w-full rounded-lg" />
            </div>
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
                    Insert a saved notice from the bookmark button, or select text and
                    save it as a notice with the document button.
                  </p>
                </div>
                <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none">
                  <.input
                    type="hidden"
                    id="edition_intro_text"
                    field={@form[:intro_text]}
                    phx-hook="TrixHook"
                    phx-debounce="800"
                    data-newsletter-notices={to_string(!@readonly?)}
                  />
                  <button
                    :if={!@readonly?}
                    type="button"
                    id="open-notice-picker-btn"
                    phx-click="open-notice-picker"
                    data-trix-notices-trigger="edition_intro_text"
                    class="hidden"
                  >
                    Insert saved notice
                  </button>
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
                  id="newsletter-posts-picker-loading"
                  role="status"
                  aria-live="polite"
                >
                  <span class="sr-only">Loading posts…</span>
                  <.thumbnail_grid_skeleton count={10} />
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
                  id="newsletter-events-picker-loading"
                  role="status"
                  aria-live="polite"
                >
                  <span class="sr-only">Loading events…</span>
                  <.thumbnail_grid_skeleton count={10} />
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
              :if={!@preview_ready?}
              id="preview-loading"
              class="flex-1 bg-white"
            >
            </div>
            <div
              :if={@preview_ready?}
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
                srcdoc={@_preview_html || ""}
              ></iframe>
            </div>
          </div>
        </div>
      </div>

      <%!-- Sticky bottom bar: autosave status + action buttons --%>
      <div class="sticky bottom-0 left-0 right-0 z-40 flex items-center justify-between gap-4 border-t border-zinc-200 bg-white/95 backdrop-blur-sm px-6 py-3">
        <%!-- Left: status badge + autosave indicator --%>
        <div class="flex items-center gap-3 min-w-0">
          <%= if @edition && @edition.status == :sending do %>
            <span class="hidden sm:inline-block shrink-0">
              <.admin_sending_badge label={
                newsletter_edition_status_label_with_progress(@edition)
              } />
            </span>
          <% else %>
            <.badge
              :if={@edition}
              type={newsletter_edition_status_badge_type(@edition.status)}
              class="hidden sm:inline-block shrink-0"
            >
              {newsletter_edition_status_label_with_progress(@edition)}
            </.badge>
          <% end %>

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

        <%!-- Right: action buttons --%>
        <div
          :if={!@loading_edition?}
          class="flex items-center gap-2 shrink-0"
        >
          <.button
            :if={@readonly? && @edition}
            type="button"
            variant="outline"
            color="zinc"
            id="duplicate-edition-btn"
            phx-click="duplicate-edition"
          >
            <.icon name="hero-document-duplicate" class="w-4 h-4" /> Duplicate
          </.button>
          <.button
            :if={!@readonly?}
            type="button"
            variant="outline"
            color="zinc"
            phx-click="open-send-modal"
          >
            <.icon name="hero-paper-airplane" class="w-4 h-4" /> Send now
          </.button>
          <.button
            :if={!@readonly?}
            type="button"
            color="blue"
            phx-click="open-schedule-modal"
          >
            <.icon name="hero-clock" class="w-4 h-4 opacity-80" /> Schedule
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
          <.button
            type="button"
            variant="outline"
            color="zinc"
            phx-click="close-send-modal"
          >
            Cancel
          </.button>
          <.button
            type="button"
            color="green"
            phx-click="confirm-send"
            phx-disable-with="Sending..."
          >
            Send now
          </.button>
        </div>
      </.modal>

      <.modal
        :if={@show_notice_picker?}
        id="insert-notice-picker-modal"
        show
        on_cancel={JS.push("close-notice-picker")}
      >
        <%= if @notice_picker_view == :new do %>
          <.header>New saved notice</.header>
          <p class="mt-2 text-sm text-zinc-500">
            Create a reusable notice, then insert it into the intro.
          </p>
          <.form
            for={@new_notice_form}
            id="new-notice-from-picker-form"
            phx-change="validate-new-notice"
            phx-submit="create-and-insert-notice"
            class="mt-4 space-y-4"
          >
            <.input
              field={@new_notice_form[:name]}
              type="text"
              label="Name"
              placeholder="e.g. Parking reminder"
              id="new-notice-picker-name"
            />
            <.input
              field={@new_notice_form[:body]}
              type="textarea"
              label="Body"
              placeholder="Write the notice…"
              id="new-notice-picker-body"
              rows="5"
            />
            <div class="flex justify-end gap-2 mt-6">
              <button
                type="button"
                id="new-notice-picker-back"
                class="rounded-lg px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-100"
                phx-click="notice-picker-show-list"
              >
                Back
              </button>
              <.button
                type="submit"
                id="create-and-insert-notice-btn"
                phx-disable-with="Saving..."
              >
                Save & insert
              </.button>
            </div>
          </.form>
        <% else %>
          <.header>Insert saved notice</.header>
          <p class="mt-2 text-sm text-zinc-500">
            Choose a notice to insert at the cursor, or create a new one.
          </p>

          <div class="mt-4 flex justify-end">
            <.button
              type="button"
              id="notice-picker-new-btn"
              variant="outline"
              color="zinc"
              phx-click="notice-picker-show-new"
            >
              <.icon name="hero-document-plus" class="w-4 h-4" /> New notice
            </.button>
          </div>

          <div
            :if={@saved_notices == []}
            id="notice-picker-empty"
            class="mt-4 rounded-lg border border-dashed border-zinc-200 px-4 py-8 text-center"
          >
            <p class="text-sm text-zinc-600">No saved notices yet.</p>
            <p class="mt-1 text-sm text-zinc-500">
              Create one here, or manage them under Newsletters → Saved notices.
            </p>
          </div>

          <ul
            :if={@saved_notices != []}
            id="notice-picker-list"
            class="mt-4 divide-y divide-zinc-100 rounded-lg border border-zinc-200 max-h-80 overflow-y-auto"
          >
            <li :for={notice <- @saved_notices}>
              <button
                type="button"
                id={"insert-notice-#{notice.id}"}
                phx-click="insert-notice"
                phx-value-notice_id={notice.id}
                class="flex w-full flex-col items-start gap-1 px-4 py-3 text-left hover:bg-zinc-50 transition"
              >
                <span class="text-sm font-semibold text-zinc-900">{notice.name}</span>
                <span class="text-xs text-zinc-500 line-clamp-2">
                  {notice_preview_text(notice.body)}
                </span>
              </button>
            </li>
          </ul>

          <div class="mt-6 flex justify-end">
            <button
              type="button"
              class="rounded-lg px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-100"
              phx-click="close-notice-picker"
            >
              Cancel
            </button>
          </div>
        <% end %>
      </.modal>

      <.modal
        :if={@show_save_notice_modal?}
        id="save-notice-modal"
        show
        on_cancel={JS.push("close-save-notice-modal")}
      >
        <.header>Save selection as notice</.header>
        <p class="mt-2 text-sm text-zinc-500">
          Name this notice so you can reuse it in future newsletters.
        </p>
        <.form
          for={@save_notice_form}
          id="save-notice-form"
          phx-change="validate-save-notice"
          phx-submit="confirm-save-notice"
          class="mt-4 space-y-4"
        >
          <.input
            field={@save_notice_form[:name]}
            type="text"
            label="Name"
            placeholder="e.g. Parking reminder"
            id="save-notice-name"
          />
          <.input type="hidden" field={@save_notice_form[:body]} />
          <div>
            <p class="block text-sm font-semibold leading-6 text-zinc-800 mb-1">
              Preview
            </p>
            <div
              id="save-notice-preview"
              class="rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm text-zinc-700 max-h-40 overflow-y-auto prose prose-sm prose-zinc max-w-none"
            >
              {scrub_intro_for_preview(@save_notice_form[:body].value || "")}
            </div>
          </div>
          <div class="flex justify-end gap-2 mt-6">
            <button
              type="button"
              class="rounded-lg px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-100"
              phx-click="close-save-notice-modal"
            >
              Cancel
            </button>
            <.button
              type="submit"
              id="confirm-save-notice-btn"
              phx-disable-with="Saving..."
            >
              Save notice
            </.button>
          </div>
        </.form>
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
            <.button
              type="button"
              variant="outline"
              color="zinc"
              phx-click="close-schedule-modal"
            >
              Cancel
            </.button>
            <.button type="submit" phx-disable-with="Scheduling...">
              Schedule
            </.button>
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

  # Compatibility for clients that loaded the former EmailPreview handshake.
  @impl true
  def handle_event("preview-ready", _params, socket), do: {:noreply, socket}

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

  def handle_event(
        "open-notice-picker",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("open-notice-picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_notice_picker?, true)
     |> assign(:notice_picker_view, :list)}
  end

  def handle_event("close-notice-picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_notice_picker?, false)
     |> assign(:notice_picker_view, :list)
     |> reset_new_notice_form()}
  end

  def handle_event("notice-picker-show-new", _params, socket) do
    {:noreply,
     socket
     |> assign(:notice_picker_view, :new)
     |> reset_new_notice_form()}
  end

  def handle_event("notice-picker-show-list", _params, socket) do
    {:noreply,
     socket
     |> assign(:notice_picker_view, :list)
     |> reset_new_notice_form()}
  end

  def handle_event("validate-new-notice", %{"new_notice" => params}, socket) do
    changeset =
      %Notice{}
      |> Notice.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket, :new_notice_form, to_form(changeset, as: :new_notice))}
  end

  def handle_event(
        "create-and-insert-notice",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event(
        "create-and-insert-notice",
        %{"new_notice" => params},
        socket
      ) do
    params = Map.update(params, "body", "", &wrap_plain_notice_body/1)

    case Newsletter.create_notice(params,
           created_by_id: socket.assigns.current_user.id
         ) do
      {:ok, notice} ->
        {:noreply,
         socket
         |> assign(:show_notice_picker?, false)
         |> assign(:notice_picker_view, :list)
         |> assign(:saved_notices, [notice | socket.assigns.saved_notices])
         |> reset_new_notice_form()
         |> push_event("insert-trix-html", %{
           html: notice.body,
           target_input_id: "edition_intro_text"
         })
         |> YscWeb.Flash.put_toast(:info, "Notice \"#{notice.name}\" saved.",
           title: "Newsletter"
         )}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :new_notice_form, to_form(changeset, as: :new_notice))}
    end
  end

  def handle_event(
        "save-selection-as-notice",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("save-selection-as-notice", %{"html" => html}, socket)
      when is_binary(html) do
    html = String.trim(html)

    if html == "" do
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "Select some text first, then save it as a notice."
       )}
    else
      changeset = Notice.changeset(%Notice{}, %{"body" => html, "name" => ""})

      {:noreply,
       socket
       |> assign(:show_save_notice_modal?, true)
       |> assign(:save_notice_form, to_form(changeset, as: :save_notice))}
    end
  end

  def handle_event("close-save-notice-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_save_notice_modal?, false)
     |> assign(
       :save_notice_form,
       to_form(Notice.changeset(%Notice{}, %{}), as: :save_notice)
     )}
  end

  def handle_event("validate-save-notice", %{"save_notice" => params}, socket) do
    changeset =
      %Notice{}
      |> Notice.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket, :save_notice_form, to_form(changeset, as: :save_notice))}
  end

  def handle_event(
        "confirm-save-notice",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("confirm-save-notice", %{"save_notice" => params}, socket) do
    case Newsletter.create_notice(params,
           created_by_id: socket.assigns.current_user.id
         ) do
      {:ok, notice} ->
        {:noreply,
         socket
         |> assign(:show_save_notice_modal?, false)
         |> assign(:saved_notices, [notice | socket.assigns.saved_notices])
         |> assign(
           :save_notice_form,
           to_form(Notice.changeset(%Notice{}, %{}), as: :save_notice)
         )
         |> YscWeb.Flash.put_toast(:info, "Notice \"#{notice.name}\" saved.",
           title: "Newsletter"
         )}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :save_notice_form, to_form(changeset, as: :save_notice))}
    end
  end

  def handle_event(
        "insert-notice",
        _params,
        %{assigns: %{readonly?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("insert-notice", %{"notice_id" => notice_id}, socket)
      when is_binary(notice_id) and notice_id != "" do
    notice =
      Enum.find(socket.assigns.saved_notices, &(to_string(&1.id) == notice_id))

    socket =
      if notice do
        socket
        |> assign(:show_notice_picker?, false)
        |> push_event("insert-trix-html", %{
          html: notice.body,
          target_input_id: "edition_intro_text"
        })
      else
        assign(socket, :show_notice_picker?, false)
      end

    {:noreply, socket}
  end

  def handle_event("duplicate-edition", _params, socket) do
    case socket.assigns.edition do
      %Edition{} = edition ->
        case Newsletter.duplicate_edition(edition,
               created_by_id: socket.assigns.current_user.id
             ) do
          {:ok, new_edition} ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(:info, "Newsletter duplicated.",
               title: "Newsletter"
             )
             |> push_navigate(to: ~p"/admin/newsletters/#{new_edition.id}/edit")}

          {:error, _} ->
            {:noreply,
             YscWeb.Flash.put_toast(
               socket,
               :error,
               "Could not duplicate newsletter."
             )}
        end

      _ ->
        {:noreply, socket}
    end
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
        {:ok,
         %{
           by_type: by_type,
           by_link: by_link,
           unsubscribe_link_clicks: unsubscribe_link_clicks,
           confirmed_unsubscribes: confirmed_unsubscribes
         }},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:email_stats, by_type)
     |> assign(:click_stats, by_link)
     |> assign(:unsubscribe_link_clicks, unsubscribe_link_clicks)
     |> assign(:confirmed_unsubscribes, confirmed_unsubscribes)}
  end

  def handle_async(:load_email_stats, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:email_stats, :error)
     |> assign(:click_stats, :error)
     |> assign(:unsubscribe_link_clicks, :error)
     |> assign(:confirmed_unsubscribes, :error)}
  end

  def handle_async(:load_saved_notices, {:ok, notices}, socket) do
    {:noreply, assign(socket, :saved_notices, notices)}
  end

  def handle_async(:load_saved_notices, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :saved_notices, [])}
  end

  defp normalize_upload_payload({:ok, id}) when is_binary(id), do: id
  defp normalize_upload_payload(id) when is_binary(id), do: id

  defp notice_preview_text(nil), do: ""

  defp notice_preview_text(body) when is_binary(body) do
    body
    |> HtmlSanitizeEx.strip_tags()
    |> String.trim()
    |> String.slice(0, 140)
  end

  defp reset_new_notice_form(socket) do
    assign(
      socket,
      :new_notice_form,
      to_form(Notice.changeset(%Notice{}, %{}), as: :new_notice)
    )
  end

  defp wrap_plain_notice_body(body) when is_binary(body) do
    trimmed = String.trim(body)

    cond do
      trimmed == "" ->
        trimmed

      String.contains?(trimmed, "<") ->
        trimmed

      true ->
        escaped =
          trimmed
          |> Phoenix.HTML.html_escape()
          |> Phoenix.HTML.safe_to_string()

        "<div>#{escaped}</div>"
    end
  end

  defp wrap_plain_notice_body(_), do: ""

  @impl true
  def handle_info(
        {:edition_delivery_progress,
         %Edition{id: edition_id} = updated_edition},
        %{assigns: %{edition: %Edition{id: edition_id} = edition}} = socket
      ) do
    updated_edition = merge_edition_delivery_progress(edition, updated_edition)

    {:noreply,
     assign(
       socket,
       edition: updated_edition,
       readonly?: edition_readonly?(updated_edition)
     )}
  end

  def handle_info({:edition_delivery_progress, %Edition{}}, socket),
    do: {:noreply, socket}

  def handle_info(
        {:edition_sent, %Edition{id: edition_id} = updated_edition},
        %{assigns: %{edition: %Edition{id: edition_id} = edition}} = socket
      ) do
    updated_edition = merge_edition_delivery_progress(edition, updated_edition)

    {:noreply,
     socket
     |> assign(:edition, updated_edition)
     |> assign(:readonly?, edition_readonly?(updated_edition))
     |> maybe_load_email_stats(updated_edition)}
  end

  def handle_info({:edition_sent, %Edition{}}, socket), do: {:noreply, socket}

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

  defp merge_edition_delivery_progress(edition, updated_edition) do
    %{
      edition
      | status: updated_edition.status,
        sent_at: updated_edition.sent_at,
        sent_count: updated_edition.sent_count,
        recipient_count: updated_edition.recipient_count
    }
  end

  defp edition_readonly?(%Edition{status: status}),
    do: status in [:sending, :sent]
end
