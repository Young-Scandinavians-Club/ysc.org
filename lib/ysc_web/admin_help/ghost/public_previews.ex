defmodule YscWeb.AdminHelp.Ghost.PublicPreviews do
  @moduledoc false
  use Phoenix.Component

  import YscWeb.AdminGhostComponents
  import YscWeb.CoreComponents

  attr :slug, :string, required: true

  def preview(assigns) do
    ~H"""
    <%= case @slug do %>
      <% "public-news-list" -> %>
        <.public_news_list />
      <% "public-news-pinned" -> %>
        <.public_news_pinned />
      <% "public-news-article" -> %>
        <.public_news_article />
      <% "public-events-list" -> %>
        <.public_events_list />
      <% "public-event-page" -> %>
        <.public_event_page />
      <% "public-event-agenda" -> %>
        <.public_event_agenda />
      <% "public-event-tickets" -> %>
        <.public_event_tickets />
      <% "public-event-ticket-tiers" -> %>
        <.public_event_ticket_tiers />
      <% "public-event-tickets-tbd" -> %>
        <.public_event_tickets_tbd />
      <% "public-event-updates" -> %>
        <.public_event_updates />
      <% "public-newsletter-archive" -> %>
        <.public_newsletter_archive />
      <% "public-newsletter-edition" -> %>
        <.public_newsletter_edition />
      <% _ -> %>
        <p class="text-zinc-500 p-6">Unknown public preview.</p>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Club News (/news, /posts/:slug)
  # ---------------------------------------------------------------------------

  defp public_news_list(assigns) do
    ~H"""
    <.public_page_shell label="Club News">
      <div class="mb-10 rounded-xl overflow-hidden border border-zinc-100 bg-white">
        <.admin_ghost_image ratio="aspect-[16/10]" class="rounded-none" />
        <div class="p-5 space-y-3 sm:hidden">
          <.admin_ghost_bar width="w-3/4" height="h-5" />
          <.admin_ghost_bar width="w-full" height="h-3" />
        </div>
      </div>
      <div class="grid md:grid-cols-2 gap-6">
        <div
          id="ghost-new-post-card"
          class="rounded-xl border-2 border-blue-400 bg-white p-2 shadow-sm ring-2 ring-blue-100"
        >
          <.admin_ghost_image class="rounded-lg mb-4" ratio="aspect-[16/10]" />
          <div class="px-3 pb-4 space-y-2">
            <p class="text-xs font-black text-blue-600 uppercase tracking-widest">
              New
            </p>
            <.admin_ghost_bar width="w-4/5" height="h-4" />
            <.admin_ghost_bar width="w-full" height="h-3" />
          </div>
        </div>
        <div :for={_ <- 1..2} class="rounded-xl border border-zinc-100 bg-white p-2">
          <.admin_ghost_image class="rounded-lg mb-4" ratio="aspect-[16/10]" />
          <div class="px-3 pb-4 space-y-2">
            <.admin_ghost_bar width="w-2/3" height="h-4" />
            <.admin_ghost_bar width="w-full" height="h-3" />
          </div>
        </div>
      </div>
    </.public_page_shell>
    """
  end

  defp public_news_pinned(assigns) do
    ~H"""
    <.public_page_shell label="Club News">
      <div
        id="ghost-pinned-hero"
        class="relative rounded-xl overflow-hidden border-2 border-amber-300 ring-2 ring-amber-100"
      >
        <.admin_ghost_image ratio="aspect-[16/10]" class="rounded-none" />
        <div class="absolute inset-0 bg-gradient-to-t from-zinc-900/80 via-zinc-900/30 to-transparent">
        </div>
        <div class="absolute bottom-0 left-0 right-0 p-6 lg:p-10 space-y-3">
          <span class="inline-flex items-center gap-1 rounded bg-amber-50/90 px-2.5 py-1 text-xs font-black uppercase tracking-widest text-amber-700 border border-amber-200">
            <.icon name="hero-star-solid" class="w-3 h-3" /> Pinned News
          </span>
          <.admin_ghost_bar width="w-2/3" height="h-6" class="!bg-zinc-300/80" />
          <.admin_ghost_bar width="w-1/2" height="h-3" class="!bg-zinc-400/60" />
        </div>
      </div>
      <div class="mt-8 grid md:grid-cols-2 gap-6 opacity-60">
        <div :for={_ <- 1..2} class="rounded-xl border border-zinc-100 bg-white p-2">
          <.admin_ghost_image class="rounded-lg mb-4" ratio="aspect-[16/10]" />
          <div class="px-3 pb-4">
            <.admin_ghost_bar width="w-2/3" height="h-4" />
          </div>
        </div>
      </div>
    </.public_page_shell>
    """
  end

  defp public_news_article(assigns) do
    ~H"""
    <.public_page_shell label="Club News">
      <div class="max-w-2xl mx-auto text-center mb-8 space-y-4">
        <p class="text-xs font-black text-blue-600 uppercase tracking-[0.3em]">
          Club News
        </p>
        <.admin_ghost_bar width="w-4/5" height="h-8" class="mx-auto" />
        <div class="flex items-center justify-center gap-3 py-4 border-y border-zinc-100">
          <.admin_ghost_avatar size="h-10 w-10" />
          <.admin_ghost_bar width="w-32" height="h-3" />
        </div>
      </div>
      <div
        id="ghost-article-hero"
        class="max-w-4xl mx-auto rounded-xl overflow-hidden border border-zinc-100 mb-8"
      >
        <.admin_ghost_image ratio="aspect-video" class="rounded-none" />
      </div>
      <div class="max-w-2xl mx-auto space-y-3">
        <.admin_ghost_bar width="w-full" height="h-3" />
        <.admin_ghost_bar width="w-full" height="h-3" />
        <.admin_ghost_bar width="w-5/6" height="h-3" />
        <.admin_ghost_bar width="w-2/5" height="h-5" class="mt-4" />
        <.admin_ghost_bar width="w-full" height="h-3" />
        <.admin_ghost_bar width="w-[92%]" height="h-3" />
      </div>
    </.public_page_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Events (/events, /events/:id)
  # ---------------------------------------------------------------------------

  defp public_events_list(assigns) do
    ~H"""
    <.public_page_shell label="Events" subtitle="What's Next">
      <div class="grid lg:grid-cols-12 gap-6">
        <div class="lg:col-span-9 space-y-6">
          <div class="rounded-2xl overflow-hidden border border-zinc-100 bg-white">
            <.admin_ghost_image ratio="aspect-[16/10]" class="rounded-none" />
          </div>
          <div class="grid md:grid-cols-2 gap-4">
            <div
              id="ghost-new-event-card"
              class="rounded-xl border-2 border-blue-400 bg-white p-2 ring-2 ring-blue-100"
            >
              <.admin_ghost_image class="rounded-lg mb-3" ratio="aspect-[16/10]" />
              <.admin_ghost_bar width="w-4/5" height="h-4" />
              <.admin_ghost_bar width="w-1/2" height="h-2.5" class="mt-2" />
            </div>
            <div class="rounded-xl border border-zinc-100 bg-white p-2">
              <.admin_ghost_image class="rounded-lg mb-3" ratio="aspect-[16/10]" />
              <.admin_ghost_bar width="w-3/4" height="h-4" />
            </div>
          </div>
        </div>
        <aside class="lg:col-span-3 hidden lg:block">
          <div class="rounded-xl border border-zinc-100 bg-zinc-50 p-5 space-y-2">
            <p class="text-xs font-black text-zinc-500 uppercase tracking-widest">
              Upcoming Events
            </p>
            <.admin_ghost_bar width="w-full" height="h-3" />
            <.admin_ghost_bar width="w-5/6" height="h-3" />
          </div>
        </aside>
      </div>
    </.public_page_shell>
    """
  end

  defp public_event_page(assigns) do
    ~H"""
    <.public_page_shell show_header?={false} wide?={true}>
      <div class="relative mb-16 lg:mb-24">
        <div class="rounded-2xl overflow-hidden">
          <.admin_ghost_image ratio="aspect-[21/9]" class="rounded-2xl" />
        </div>
        <div class="relative -mt-12 mx-2 lg:-mt-16 lg:mx-4 z-10">
          <div class="bg-white rounded-xl shadow-md border border-zinc-100 p-6 lg:p-8 space-y-3">
            <p class="text-xs font-black text-blue-600 uppercase tracking-[0.2em]">
              Sat, Jun 21 · 5:00 PM
            </p>
            <h2 class="text-2xl lg:text-3xl font-black text-zinc-900 tracking-tight">
              Summer Cabin Weekend
            </h2>
            <div class="flex items-center gap-2 text-sm text-zinc-500">
              <.icon name="hero-map-pin" class="w-4 h-4 shrink-0" />
              <span>Clear Lake Clubhouse</span>
            </div>
          </div>
        </div>
      </div>

      <div class="max-w-screen-xl mx-auto px-2 grid lg:grid-cols-12 gap-6 -mt-6">
        <div class="lg:col-span-8 max-w-3xl space-y-10 pt-4">
          <.admin_ghost_public_agenda_timeline />

          <section id="ghost-public-event-details" class="space-y-3">
            <h3 class="text-xl font-black text-zinc-900 flex items-center gap-3">
              <span class="w-8 h-px bg-zinc-200"></span> Details
            </h3>
            <.admin_ghost_bar width="w-full" height="h-3" />
            <.admin_ghost_bar width="w-full" height="h-3" />
            <.admin_ghost_bar width="w-4/5" height="h-3" />
          </section>

          <.admin_ghost_public_attendees_section />
        </div>
        <div class="lg:col-span-4">
          <.admin_ghost_public_ticket_sidebar pricing_text="From $20" />
        </div>
      </div>
    </.public_page_shell>
    """
  end

  defp public_event_tickets(assigns) do
    ~H"""
    <div class="admin-help-ghost-public min-h-full bg-white py-6 px-4">
      <div class="max-w-screen-xl mx-auto">
        <div class="mb-4">
          <.admin_ghost_bar width="w-1/2" height="h-5" class="max-w-md" />
          <p class="text-sm text-zinc-500 mt-2">
            Sidebar pricing updates when you add or change tiers in admin
          </p>
        </div>
        <div class="grid lg:grid-cols-12 gap-6 items-start">
          <div class="lg:col-span-8 space-y-4">
            <.admin_ghost_image ratio="aspect-[21/9]" class="rounded-2xl" />
            <.admin_ghost_bar width="w-2/3" height="h-4" />
            <.admin_ghost_bar width="w-full" height="h-3" />
          </div>
          <div class="lg:col-span-4">
            <.admin_ghost_public_ticket_sidebar
              pricing_text="From $20"
              spots_available={48}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp public_event_ticket_tiers(assigns) do
    ~H"""
    <div class="admin-help-ghost-public min-h-full bg-zinc-100/80 py-6 px-4">
      <div class="max-w-5xl mx-auto space-y-3">
        <p class="text-sm text-zinc-600 text-center">
          After <strong class="text-zinc-800">Get Tickets</strong>, members pick a tier and quantity
        </p>
        <.admin_ghost_public_ticket_modal />
      </div>
    </div>
    """
  end

  defp public_event_tickets_tbd(assigns) do
    ~H"""
    <div class="admin-help-ghost-public min-h-full bg-white py-6 px-4">
      <div class="max-w-lg mx-auto">
        <p class="text-sm text-zinc-500 text-center mb-4">
          Published with <strong class="text-zinc-700">Tickets TBD</strong> enabled
        </p>
        <.admin_ghost_public_ticket_sidebar
          tickets_tbd?={true}
          pricing_text="Tickets coming soon"
        />
      </div>
    </div>
    """
  end

  defp public_event_agenda(assigns) do
    ~H"""
    <.public_page_shell show_header?={false} wide?={true}>
      <div class="max-w-3xl mx-auto mb-6">
        <.admin_ghost_bar width="w-2/3" height="h-5" class="mb-2" />
        <p class="text-sm text-zinc-500">
          Members see timed items on the event page
        </p>
      </div>
      <div class="max-w-3xl mx-auto">
        <.admin_ghost_public_agenda_timeline />
      </div>
    </.public_page_shell>
    """
  end

  defp public_event_updates(assigns) do
    ~H"""
    <.public_page_shell show_header?={false} wide?={true}>
      <div class="relative mb-12 lg:mb-20">
        <div class="rounded-2xl overflow-hidden">
          <.admin_ghost_image ratio="aspect-[21/9]" class="rounded-2xl" />
        </div>
        <div class="relative -mt-10 mx-2 lg:-mt-14 lg:mx-4 z-10">
          <div class="bg-white rounded-xl shadow-md border border-zinc-100 p-5 lg:p-7 space-y-2">
            <p class="text-xs font-black text-blue-600 uppercase tracking-[0.2em]">
              Sat, Jun 21 · 5:00 PM
            </p>
            <h2 class="text-xl lg:text-2xl font-black text-zinc-900 tracking-tight">
              Summer Cabin Weekend
            </h2>
            <div class="flex items-center gap-2 text-sm text-zinc-500">
              <.icon name="hero-map-pin" class="w-4 h-4 shrink-0" />
              <span>Clear Lake Clubhouse</span>
            </div>
          </div>
        </div>
      </div>

      <div class="max-w-screen-xl mx-auto px-2 grid lg:grid-cols-12 gap-6 -mt-4">
        <div class="lg:col-span-8 max-w-3xl space-y-10 pt-2">
          <.admin_ghost_public_agenda_timeline class="space-y-6" />

          <.admin_ghost_public_event_updates_section />

          <section class="space-y-3 opacity-60">
            <h3 class="text-2xl font-black text-zinc-900 tracking-tight flex items-center gap-3">
              <span class="w-8 h-px bg-zinc-200"></span> Details
            </h3>
            <.admin_ghost_bar width="w-full" height="h-3" />
            <.admin_ghost_bar width="w-11/12" height="h-3" />
          </section>
        </div>
        <div class="lg:col-span-4">
          <.admin_ghost_public_ticket_sidebar pricing_text="From $20" />
        </div>
      </div>
    </.public_page_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Newsletters (/newsletters)
  # ---------------------------------------------------------------------------

  defp public_newsletter_archive(assigns) do
    ~H"""
    <.public_page_shell
      label="Newsletters"
      subtitle="Browse our past newsletters"
    >
      <div class="divide-y divide-zinc-100">
        <article
          id="ghost-new-newsletter-edition"
          class="py-6 border-l-4 border-blue-500 pl-4 -ml-4"
        >
          <p class="text-xs font-bold text-blue-600 uppercase tracking-widest mb-2">
            Just sent
          </p>
          <.admin_ghost_bar width="w-2/3" height="h-5" />
          <.admin_ghost_bar width="w-full" height="h-3" class="mt-2" />
          <span class="inline-flex items-center gap-1 text-sm font-medium text-blue-600 mt-3">
            Read <.icon name="hero-arrow-right" class="w-4 h-4" />
          </span>
        </article>
        <article :for={_ <- 1..2} class="py-6">
          <.admin_ghost_bar width="w-20" height="h-2.5" class="mb-2" />
          <.admin_ghost_bar width="w-1/2" height="h-4" />
          <.admin_ghost_bar width="w-full" height="h-3" class="mt-2" />
        </article>
      </div>
    </.public_page_shell>
    """
  end

  defp public_newsletter_edition(assigns) do
    ~H"""
    <.public_page_shell label="Newsletter">
      <div class="max-w-2xl mx-auto mb-6">
        <p class="text-xs font-bold text-blue-600 uppercase tracking-widest mb-2">
          Jun 9, 2026
        </p>
        <.admin_ghost_bar width="w-3/4" height="h-6" />
      </div>
      <div class="max-w-2xl mx-auto rounded-xl border border-zinc-200 bg-white overflow-hidden shadow-sm">
        <.admin_ghost_image ratio="aspect-video" class="rounded-none" />
        <div class="p-6 space-y-4">
          <.admin_ghost_bar width="w-full" height="h-3" />
          <.admin_ghost_bar width="w-[92%]" height="h-3" />
          <div class="border-t border-zinc-100 pt-4 space-y-3">
            <p class="text-xs font-black text-zinc-500 uppercase tracking-widest">
              From the club
            </p>
            <div
              :for={_ <- 1..2}
              class="flex gap-3 p-3 rounded-lg border border-zinc-100"
            >
              <.admin_ghost_image
                class="w-20 shrink-0 rounded"
                ratio="aspect-square"
              />
              <div class="flex-1 space-y-2">
                <.admin_ghost_bar width="w-full" height="h-3" />
                <.admin_ghost_bar width="w-2/3" height="h-2.5" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </.public_page_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared public chrome
  # ---------------------------------------------------------------------------

  attr :label, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :show_header?, :boolean, default: true
  attr :wide?, :boolean, default: false
  slot :inner_block, required: true

  defp public_page_shell(assigns) do
    assigns =
      assign(
        assigns,
        :content_width,
        if(assigns.wide?, do: "max-w-screen-xl", else: "max-w-4xl")
      )

    ~H"""
    <div class={[
      "admin-help-ghost-public min-h-full bg-white px-4",
      @show_header? && "py-6",
      !@show_header? && "pt-8 pb-6"
    ]}>
      <header
        :if={@show_header? && @label}
        class="max-w-4xl mx-auto mb-8 text-center border-y border-zinc-200 py-8"
      >
        <p
          :if={@subtitle}
          class="text-sm font-black text-blue-600 uppercase tracking-[0.2em] mb-2"
        >
          {@subtitle}
        </p>
        <h1 class="text-4xl md:text-5xl font-black text-zinc-900 tracking-tighter">
          {@label}
        </h1>
      </header>
      <div class={[@content_width, "mx-auto"]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
