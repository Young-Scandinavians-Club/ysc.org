defmodule YscWeb.NewsletterArchiveLive do
  @moduledoc """
  Public newsletter archive: lists all sent editions and renders each one
  as it appeared in subscribers' email clients.

  - Guest users: shown a subscribe form (with Turnstile + rate limiting).
  - Authenticated users: shown their subscription status with a toggle.

  Both `:index` and `:show` use async loading: the initial static HTML is
  delivered immediately and the DB queries run only after the WebSocket
  connects so the server never blocks on rendering.
  """
  use YscWeb, :live_view

  require Ysc.Logging

  import YscWeb.Live.AsyncHelpers

  alias Ysc.Newsletter
  alias YscWeb.NewsletterSubscribe

  # ---------------------------------------------------------------------------
  # Render — :index
  # ---------------------------------------------------------------------------

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="py-6 md:py-12">
      <div class="max-w-screen-xl mx-auto px-4 mb-12">
        <.page_masthead
          size={:large}
          title="Newsletters"
          subtitle="Browse our past newsletters. Subscribe to receive future newsletters in your inbox."
        />
      </div>

      <%!-- Subscription widget --%>
      <div class="max-w-screen-lg mx-auto px-4 mb-12">
        <%= if @current_user do %>
          <%= if @async_data_loaded do %>
            <.newsletter_member_status
              id="newsletter-member-status"
              subscribed={@user_subscribed}
              event="toggle_subscription"
            />
          <% else %>
            <.subscription_widget_skeleton />
          <% end %>
        <% else %>
          <div class="rounded-xl border border-zinc-200 bg-zinc-50 px-6 py-8 text-center">
            <.icon name="hero-envelope" class="w-8 h-8 mx-auto mb-3 text-blue-600" />
            <h2 class="text-lg font-bold text-zinc-900 mb-1">Stay in the loop</h2>
            <p class="text-sm text-zinc-500 mb-6">
              Sign up to receive future newsletters directly in your inbox.
            </p>
            <.newsletter_subscribe_form
              id="newsletter-subscribe-form"
              email={@newsletter_email}
              submitted={@newsletter_submitted}
              error={@newsletter_error}
              class="max-w-md mx-auto"
            />
          </div>
        <% end %>
      </div>

      <div class="max-w-screen-lg mx-auto px-4">
        <%!-- Loading skeletons --%>
        <div :if={!@async_data_loaded} class="divide-y divide-zinc-100">
          <div :for={_ <- 1..5} class="py-8 animate-pulse">
            <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
              <div class="flex-1 space-y-3">
                <div class="h-3 w-24 bg-zinc-200 rounded"></div>
                <div class="h-5 w-2/3 bg-zinc-200 rounded"></div>
                <div class="h-4 w-full bg-zinc-100 rounded"></div>
              </div>
              <div class="h-4 w-12 bg-zinc-200 rounded shrink-0 mt-1"></div>
            </div>
          </div>
        </div>

        <%!-- Empty state — only shown once loaded --%>
        <p
          :if={@async_data_loaded && @editions_empty?}
          class="text-center text-zinc-400 py-24 text-lg"
        >
          No newsletters have been sent yet.
        </p>

        <div id="editions" phx-update="stream" class="divide-y divide-zinc-100">
          <article
            :for={{id, edition} <- @streams.editions}
            id={id}
            class="py-8 group"
          >
            <.link
              navigate={~p"/newsletters/#{edition.id}"}
              class="block hover:no-underline"
            >
              <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                <div class="flex-1 min-w-0">
                  <p class="text-xs font-bold text-blue-600 uppercase tracking-widest mb-2">
                    {format_sent_date(edition.sent_at)}
                  </p>
                  <h2 class="text-xl font-bold text-zinc-900 group-hover:text-blue-600 transition-colors leading-snug">
                    {edition.title}
                  </h2>
                  <p
                    :if={edition_excerpt(edition) != ""}
                    class="mt-2 text-sm text-zinc-500 line-clamp-2"
                  >
                    {edition_excerpt(edition)}
                  </p>
                </div>
                <div class="shrink-0 mt-1">
                  <span class="inline-flex items-center gap-1 text-sm font-medium text-blue-600 group-hover:gap-2 transition-all">
                    Read <.icon name="hero-arrow-right" class="w-4 h-4" />
                  </span>
                </div>
              </div>
            </.link>
          </article>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Render — :show
  # ---------------------------------------------------------------------------

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="py-6 md:py-10">
      <div class="max-w-screen-lg mx-auto px-4 mb-6">
        <div class="flex items-center justify-between">
          <.link
            navigate={~p"/newsletters"}
            class="inline-flex items-center gap-1 text-sm text-zinc-500 hover:text-zinc-900 transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> All newsletters
          </.link>

          <.button
            :if={@async_data_loaded && @edition && @edition.archived_html}
            id="newsletter-archive-save-pdf"
            type="button"
            phx-click={JS.dispatch("newsletter:print", to: "#newsletter-frame")}
            variant="outline"
            color="zinc"
            class="!min-h-0 !border-0 !bg-transparent !shadow-none px-3 py-2 text-sm font-medium !text-zinc-600 hover:!bg-zinc-100 hover:!text-zinc-900 transition-colors"
            title="Print or save as PDF"
          >
            <.icon name="hero-printer" class="w-4 h-4 shrink-0" /> Save as PDF
          </.button>
        </div>

        <%!-- Title skeleton --%>
        <div :if={!@async_data_loaded} class="mt-6 mb-2 animate-pulse space-y-3">
          <div class="h-3 w-28 bg-zinc-200 rounded"></div>
          <div class="h-8 w-3/4 bg-zinc-200 rounded"></div>
        </div>

        <div :if={@async_data_loaded && @edition} class="mt-6 mb-2">
          <p class="text-xs font-bold text-blue-600 uppercase tracking-widest mb-2">
            {format_sent_date(@edition.sent_at)}
          </p>
          <h1 class="text-3xl md:text-4xl font-black text-zinc-900 tracking-tight">
            {@edition.title}
          </h1>
        </div>
      </div>

      <%!-- Newsletter iframe skeleton --%>
      <div :if={!@async_data_loaded} class="max-w-screen-lg mx-auto px-4">
        <div
          class="rounded-xl border border-zinc-200 bg-zinc-50 animate-pulse"
          style="min-height:600px"
        >
        </div>
      </div>

      <%!-- Archived HTML via srcdoc so the email renders faithfully in isolation --%>
      <div
        :if={@async_data_loaded && @edition && @edition.archived_html}
        class="max-w-screen-lg mx-auto px-4"
      >
        <div class="rounded-xl border border-zinc-200 shadow-sm">
          <iframe
            id="newsletter-frame"
            srcdoc={@edition.archived_html}
            sandbox=""
            class="w-full border-0 rounded-xl"
            style="min-height:1400px"
            phx-hook="AutoResizeIframe"
            phx-update="ignore"
            title={"Newsletter: #{@edition.title}"}
          ></iframe>
        </div>
      </div>

      <div
        :if={@async_data_loaded && @edition && !@edition.archived_html}
        class="max-w-screen-lg mx-auto px-4"
      >
        <div class="rounded-xl border border-zinc-200 p-12 text-center text-zinc-400">
          <.icon name="hero-envelope" class="w-10 h-10 mx-auto mb-4 text-zinc-300" />
          <p class="text-base">
            The rendered version of this newsletter is not available.
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Sub-components
  # ---------------------------------------------------------------------------

  defp subscription_widget_skeleton(assigns) do
    ~H"""
    <div class="rounded-xl border border-zinc-200 bg-zinc-50 px-6 py-6 animate-pulse">
      <div class="flex items-center gap-3">
        <div class="w-10 h-10 rounded-full bg-zinc-200 shrink-0"></div>
        <div class="space-y-2 flex-1">
          <div class="h-4 w-32 bg-zinc-200 rounded"></div>
          <div class="h-3 w-56 bg-zinc-100 rounded"></div>
        </div>
        <div class="h-9 w-24 bg-zinc-200 rounded shrink-0"></div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    remote_ip =
      case get_connect_info(socket, :peer_data) do
        %{address: address} -> address
        _ -> nil
      end

    {:ok,
     socket
     |> assign(
       remote_ip: remote_ip,
       async_data_loaded: false,
       editions_empty?: false,
       user_subscribed: false,
       edition: nil,
       newsletter_email: "",
       newsletter_submitted: false,
       newsletter_error: nil
     )
     |> stream(:editions, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket =
      socket
      |> assign(:page_title, "Newsletters")
      |> assign(
        :meta_description,
        "Browse past newsletters from the Young Scandinavians Club."
      )

    if connected?(socket) do
      current_user = socket.assigns.current_user

      start_async(socket, :load_index_data, fn ->
        allow_sandbox_access()

        %{
          editions: Newsletter.list_sent_editions(),
          user_subscribed: NewsletterSubscribe.subscribed?(current_user)
        }
      end)
    else
      socket
    end
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket = assign(socket, :page_title, "Newsletter")

    if connected?(socket) do
      start_async(socket, :load_show_data, fn ->
        allow_sandbox_access()
        Newsletter.get_sent_edition(id)
      end)
    else
      socket
    end
  end

  # ---------------------------------------------------------------------------
  # Async handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_async(
        :load_index_data,
        {:ok, %{editions: editions, user_subscribed: user_subscribed}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:async_data_loaded, true)
     |> assign(:editions_empty?, editions == [])
     |> assign(:user_subscribed, user_subscribed)
     |> stream(:editions, editions)}
  end

  def handle_async(:load_index_data, {:exit, reason}, socket) do
    Ysc.Logging.error("NewsletterArchiveLive: failed to load index data",
      error: reason
    )

    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  def handle_async(:load_show_data, {:ok, nil}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Newsletter not found.")
     |> push_navigate(to: ~p"/newsletters")}
  end

  def handle_async(:load_show_data, {:ok, edition}, socket) do
    {:noreply,
     socket
     |> assign(:async_data_loaded, true)
     |> assign(:page_title, edition.title)
     |> assign(:meta_description, edition_excerpt(edition))
     |> assign(:edition, edition)}
  end

  def handle_async(:load_show_data, {:exit, reason}, socket) do
    Ysc.Logging.error("NewsletterArchiveLive: failed to load edition",
      error: reason
    )

    {:noreply,
     socket
     |> put_flash(
       :error,
       "We couldn't load this newsletter. Please try again, or email info@ysc.org if the problem continues."
     )
     |> push_navigate(to: ~p"/newsletters")}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("subscribe_newsletter", params, socket) do
    {:noreply, NewsletterSubscribe.request_guest(socket, params)}
  end

  def handle_event("toggle_subscription", _params, socket) do
    {:noreply,
     NewsletterSubscribe.toggle_member(socket,
       source: "newsletters_page",
       assign: :user_subscribed
     )}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_sent_date(nil), do: "Sent"

  defp format_sent_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %-d, %Y")
  end

  defp edition_excerpt(%{intro_text: nil}), do: ""
  defp edition_excerpt(%{intro_text: ""}), do: ""

  defp edition_excerpt(%{intro_text: html}) do
    html
    |> HtmlSanitizeEx.strip_tags()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 200)
  end
end
