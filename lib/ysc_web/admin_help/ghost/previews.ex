defmodule YscWeb.AdminHelp.Ghost.Previews do
  @moduledoc false
  use Phoenix.Component

  import YscWeb.AdminComponents
  import YscWeb.AdminGhostComponents
  import YscWeb.CoreComponents

  attr :slug, :string, required: true

  def preview(assigns) do
    if String.starts_with?(assigns.slug, "public-") do
      ~H"""
      <YscWeb.AdminHelp.Ghost.PublicPreviews.preview slug={@slug} />
      """
    else
      admin_preview(assigns)
    end
  end

  defp admin_preview(assigns) do
    ~H"""
    <%= case @slug do %>
      <% "getting-started-login" -> %>
        <.getting_started_login />
      <% "getting-started-dashboard" -> %>
        <.getting_started_dashboard />
      <% "getting-started-sidebar" -> %>
        <.getting_started_sidebar />
      <% "posts-list" -> %>
        <.posts_list />
      <% "posts-editor" -> %>
        <.posts_editor />
      <% "posts-settings" -> %>
        <.posts_settings />
      <% "posts-publish" -> %>
        <.posts_publish />
      <% "newsletter-compose" -> %>
        <.newsletter_compose />
      <% "newsletter-subscribers" -> %>
        <.newsletter_subscribers />
      <% "events-list" -> %>
        <.events_list />
      <% "events-edit" -> %>
        <.events_edit />
      <% "events-tickets" -> %>
        <.events_tickets />
      <% "events-updates" -> %>
        <.events_updates />
      <% "media-gallery" -> %>
        <.media_gallery />
      <% "check-in-desk" -> %>
        <.check_in_desk />
      <% "scanner" -> %>
        <.scanner />
      <% _ -> %>
        <p class="text-zinc-500 p-6">Unknown preview.</p>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Getting started
  # ---------------------------------------------------------------------------

  defp getting_started_dashboard(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:dashboard}>
      <.admin_ghost_dashboard />
    </.ghost_admin_shell>
    """
  end

  defp getting_started_login(assigns) do
    ~H"""
    <div class="min-h-full bg-zinc-50">
      <header class="bg-white border-b border-zinc-200 px-6 py-4 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <.ysc_logo class="h-10 w-10" width={40} height={40} />
          <.admin_ghost_bar width="w-24" height="h-4" />
        </div>
        <div class="hidden sm:flex items-center gap-6">
          <.admin_ghost_bar :for={_ <- 1..4} width="w-14" height="h-2.5" />
        </div>
      </header>
      <div class="p-6 space-y-6">
        <.admin_ghost_image class="rounded-xl" ratio="aspect-[21/9]" />
        <div class="grid md:grid-cols-3 gap-4">
          <div
            :for={_ <- 1..3}
            class="bg-white rounded-xl border border-zinc-200 p-4 space-y-3"
          >
            <.admin_ghost_image ratio="aspect-video" class="rounded-lg" />
            <.admin_ghost_bar width="w-2/3" height="h-3.5" />
            <.admin_ghost_bar width="w-full" height="h-2.5" />
            <.admin_ghost_bar width="w-5/6" height="h-2.5" />
          </div>
        </div>
      </div>
      <div
        id="ghost-admin-fab"
        class="fixed bottom-6 right-6 z-10 flex items-center gap-2 rounded-full bg-blue-600 px-4 py-3 text-white shadow-lg"
      >
        <.icon name="hero-cog-6-tooth" class="w-5 h-5" />
        <span class="text-sm font-semibold">Admin</span>
      </div>
    </div>
    """
  end

  defp getting_started_sidebar(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:dashboard}>
      <.admin_page_title>Overview</.admin_page_title>
      <p class="mt-2 text-sm text-zinc-500">Welcome back</p>
      <div class="mt-8 grid md:grid-cols-3 gap-4">
        <div
          :for={_ <- 1..3}
          class="bg-white rounded-xl border border-zinc-200 p-5 space-y-3"
        >
          <.admin_ghost_bar width="w-24" height="h-2.5" />
          <.admin_ghost_bar width="w-16" height="h-6" />
        </div>
      </div>
      <div class="mt-6 bg-white rounded-xl border border-zinc-200 p-5 space-y-4">
        <.admin_ghost_bar width="w-32" height="h-3.5" />
        <div :for={_ <- 1..4} class="flex items-center gap-3">
          <.admin_ghost_avatar size="h-8 w-8" />
          <div class="flex-1 space-y-2">
            <.admin_ghost_bar width="w-2/3" height="h-3" />
            <.admin_ghost_bar width="w-1/3" height="h-2.5" />
          </div>
        </div>
      </div>
    </.ghost_admin_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Posts
  # ---------------------------------------------------------------------------

  defp posts_list(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:news}>
      <div class="flex justify-between items-center py-2">
        <.admin_page_title>Posts</.admin_page_title>
        <.button id="ghost-new-post">
          <.icon name="hero-document-plus" class="w-5 h-5 -mt-0.5" />
          <span class="ms-1">New Post</span>
        </.button>
      </div>
      <div class="mt-4">
        <.ghost_search placeholder="Search by post title..." />
      </div>
      <div class="mt-4 flex gap-2">
        <.ghost_filter_button />
      </div>
      <div class="mt-4">
        <.admin_ghost_posts_table />
      </div>
    </.ghost_admin_shell>
    """
  end

  defp posts_editor(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:news}>
      <.admin_ghost_post_editor />
    </.ghost_admin_shell>
    """
  end

  defp posts_settings(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:news}>
      <div class="max-w-xl mx-auto bg-white rounded-xl border border-zinc-200 p-6 space-y-6">
        <.admin_page_title level={2}>Post Settings</.admin_page_title>
        <div>
          <p class="text-sm font-semibold text-zinc-800 mb-2">Featured Image</p>
          <div class="border-2 border-dashed border-blue-300 bg-blue-50/50 rounded-xl p-8 flex flex-col items-center gap-3">
            <.icon name="hero-photo" class="w-10 h-10 text-blue-400" />
            <.button variant="outline" color="blue">Choose image</.button>
          </div>
        </div>
        <div class="space-y-2">
          <.admin_ghost_bar width="w-24" height="h-3" />
          <.admin_ghost_bar width="w-full" height="h-10" rounded="rounded-lg" />
        </div>
      </div>
    </.ghost_admin_shell>
    """
  end

  defp posts_publish(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:news}>
      <div class="flex items-center justify-between border-b border-zinc-200 pb-4 mb-6">
        <.admin_ghost_bar width="w-40" height="h-4" />
        <div class="flex items-center gap-2">
          <.button variant="outline" color="zinc">Preview</.button>
          <.button>Publish</.button>
        </div>
      </div>
      <div class="max-w-2xl mx-auto bg-white rounded-xl border border-zinc-200 overflow-hidden">
        <.admin_ghost_image ratio="aspect-[2/1]" />
        <div class="p-6 space-y-3">
          <.admin_ghost_bar width="w-3/4" height="h-5" />
          <.admin_ghost_bar width="w-1/4" height="h-3" />
          <.admin_ghost_editor_body class="p-0" />
        </div>
      </div>
    </.ghost_admin_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Newsletters
  # ---------------------------------------------------------------------------

  defp newsletter_compose(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:newsletters}>
      <div class="flex items-center gap-3 py-2 mb-2">
        <span class="text-sm text-zinc-600 flex items-center gap-1">
          <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to Newsletters
        </span>
        <span class="inline-flex items-center rounded-md bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-800 border border-amber-200">
          Draft
        </span>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 lg:gap-8 pb-16">
        <%!-- Left: editor (cover, fields, pickers) --%>
        <div id="ghost-newsletter-editor-panel" class="space-y-4">
          <div class="border border-zinc-200 rounded-lg p-4 bg-white">
            <h2 class="text-base font-semibold text-zinc-800 mb-3">Cover photo</h2>
            <.admin_ghost_image ratio="aspect-video" class="rounded-lg" />
          </div>

          <div class="border border-zinc-200 rounded-lg p-4 bg-white space-y-3">
            <h2 class="text-base font-semibold text-zinc-800">
              Headline & subject
            </h2>
            <div class="space-y-1">
              <p class="text-sm text-zinc-600">Title (e.g. Winter Update)</p>
              <.admin_ghost_bar width="w-full" height="h-10" rounded="rounded-lg" />
            </div>
            <div class="space-y-1">
              <p class="text-sm text-zinc-600">Email subject line</p>
              <.admin_ghost_bar width="w-full" height="h-10" rounded="rounded-lg" />
            </div>
          </div>

          <div class="border border-zinc-200 rounded-lg overflow-hidden bg-white">
            <div class="px-4 pt-4 pb-2">
              <h2 class="text-base font-semibold text-zinc-800">Intro text</h2>
              <p class="text-sm text-zinc-500 mt-1">
                Opening section. Use the toolbar for bold, links, lists, and more.
              </p>
            </div>
            <div class="flex gap-1 px-3 py-2 border-y border-zinc-100">
              <.admin_ghost_bar
                :for={_ <- 1..5}
                width="w-7"
                height="h-7"
                rounded="rounded-md"
              />
            </div>
            <.admin_ghost_editor_body class="min-h-[100px]" />
          </div>

          <div
            id="ghost-newsletter-post-picker"
            class="border border-zinc-200 rounded-lg p-4 bg-white"
          >
            <h2 class="text-base font-semibold text-zinc-800 mb-1">
              Latest news (posts)
            </h2>
            <p class="text-sm text-zinc-500 mb-3">
              Click to select or deselect posts to feature.
            </p>
            <div class="grid grid-cols-3 sm:grid-cols-4 gap-2">
              <.admin_ghost_newsletter_picker_tile selected position={1} />
              <.admin_ghost_newsletter_picker_tile selected position={2} />
              <.admin_ghost_newsletter_picker_tile />
              <.admin_ghost_newsletter_picker_tile />
              <.admin_ghost_newsletter_picker_tile />
            </div>
          </div>

          <div
            id="ghost-newsletter-event-picker"
            class="border border-zinc-200 rounded-lg p-4 bg-white"
          >
            <h2 class="text-base font-semibold text-zinc-800 mb-1">
              Upcoming events
            </h2>
            <p class="text-sm text-zinc-500 mb-3">
              Click to select or deselect events to feature.
            </p>
            <div class="grid grid-cols-3 sm:grid-cols-4 gap-2">
              <.admin_ghost_newsletter_picker_tile selected position={1} />
              <.admin_ghost_newsletter_picker_tile />
              <.admin_ghost_newsletter_picker_tile />
            </div>
          </div>
        </div>

        <%!-- Right: live email preview --%>
        <div id="ghost-newsletter-preview-panel" class="lg:sticky lg:top-4">
          <.admin_ghost_newsletter_email_preview />
        </div>
      </div>

      <div
        id="ghost-newsletter-action-bar"
        class="mt-4 flex items-center justify-between gap-4 border border-zinc-200 bg-white/95 rounded-lg px-4 py-3"
      >
        <div class="flex items-center gap-2 text-xs text-zinc-400">
          <span class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
          Saved 2:34 PM
        </div>
        <div class="flex items-center gap-2">
          <.button variant="outline" color="zinc" class="text-sm">
            <.icon name="hero-paper-airplane" class="w-4 h-4 -mt-0.5" /> Send now
          </.button>
          <.button color="blue" class="text-sm">
            <.icon name="hero-clock" class="w-4 h-4 -mt-0.5 opacity-80" /> Schedule
          </.button>
        </div>
      </div>
    </.ghost_admin_shell>
    """
  end

  defp newsletter_subscribers(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:newsletters}>
      <div class="py-2">
        <.admin_page_title>Newsletters</.admin_page_title>
        <p class="mt-0.5 text-sm text-zinc-500">1,248 subscribers</p>
      </div>

      <.admin_tabs id="ghost-newsletter-tabs" aria_label="Newsletter sections">
        <.admin_tab active={false}>Editions</.admin_tab>
        <.admin_tab active={true}>Subscribers</.admin_tab>
      </.admin_tabs>

      <div class="space-y-6">
        <div
          id="ghost-subscribers-toolbar"
          class="flex flex-col sm:flex-row sm:items-center gap-4 sm:gap-3"
        >
          <div id="ghost-subscribers-search" class="min-w-0 flex-1">
            <.ghost_search placeholder="Search by email..." />
          </div>
          <div
            id="ghost-subscribers-filters"
            class="flex items-center gap-2 flex-shrink-0 flex-wrap"
          >
            <span class="text-sm font-medium text-zinc-600 sr-only sm:not-sr-only">
              Status:
            </span>
            <span class="rounded px-3 py-1.5 text-sm font-medium bg-zinc-200 text-zinc-800">
              All
            </span>
            <span class="rounded px-3 py-1.5 text-sm font-medium bg-zinc-100 text-zinc-600">
              Active
            </span>
            <span class="rounded px-3 py-1.5 text-sm font-medium bg-zinc-100 text-zinc-600">
              Inactive
            </span>
            <.button id="ghost-add-subscriber" class="ms-0 sm:ms-2 text-sm">
              <.icon name="hero-user-plus" class="w-5 h-5 -mt-0.5" />
              <span class="ms-1.5">Add subscriber</span>
            </.button>
          </div>
        </div>

        <.admin_ghost_subscribers_table />
      </div>
    </.ghost_admin_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  defp events_list(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:events}>
      <div class="flex justify-between py-6">
        <.admin_page_title>Events</.admin_page_title>
        <div class="flex items-center gap-3">
          <.button>
            <.icon name="hero-qr-code" class="w-5 h-5 -mt-0.5" />
            <span class="ms-1">Check-in &amp; Scan</span>
          </.button>
          <.button id="ghost-new-event">
            <.icon name="hero-calendar" class="w-5 h-5 -mt-0.5" />
            <span class="ms-1">New Event</span>
          </.button>
        </div>
      </div>

      <div class="w-full pt-4">
        <div class="flex gap-6 border-b border-zinc-200 text-sm">
          <span class="font-semibold text-blue-600 border-b-2 border-blue-600 pb-3 -mb-px">
            Upcoming
          </span>
          <span class="text-zinc-500 pb-3">Drafts</span>
          <span class="text-zinc-500 pb-3">Past</span>
          <span class="text-zinc-500 pb-3">All</span>
        </div>

        <div class="pt-4">
          <.ghost_search placeholder="Search by event name..." />
        </div>

        <div class="py-6 w-full">
          <div class="pb-4 flex">
            <.ghost_filter_button />
          </div>
          <.admin_ghost_events_table />
        </div>
      </div>
    </.ghost_admin_shell>
    """
  end

  defp events_edit(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:events}>
      <.admin_ghost_event_editor_header active_tab={:details} state={:draft} />

      <div class="max-w-3xl space-y-6 pb-8">
        <.admin_ghost_event_section
          id="ghost-event-cover-section"
          title="Cover Image"
        >
          <.admin_ghost_image ratio="aspect-video" class="rounded-lg max-w-md" />
          <.button variant="outline" color="zinc" class="mt-1">
            <.icon name="hero-photo" class="w-5 h-5 -mt-0.5 me-1" /> Choose image
          </.button>
        </.admin_ghost_event_section>

        <.admin_ghost_event_section
          id="ghost-event-basics-section"
          title="Basics"
          subtitle="Give your event a nice title and summary to attract attendees."
        >
          <div class="space-y-3">
            <div class="space-y-1">
              <p class="text-sm font-semibold text-zinc-800">Event Title*</p>
              <.admin_ghost_bar width="w-full" height="h-10" rounded="rounded-lg" />
            </div>
            <div class="space-y-1">
              <p class="text-sm font-semibold text-zinc-800">Summary (142/200)*</p>
              <.admin_ghost_bar width="w-full" height="h-16" rounded="rounded-lg" />
            </div>
            <div class="space-y-1">
              <p class="text-sm font-semibold text-zinc-800">
                Partiful Link (Optional)
              </p>
              <.admin_ghost_bar width="w-full" height="h-10" rounded="rounded-lg" />
            </div>
          </div>
        </.admin_ghost_event_section>

        <.admin_ghost_event_section
          id="ghost-event-date-section"
          title="Date and Location"
        >
          <h3 class="text-base font-medium text-zinc-800">Date and Time</h3>
          <div class="flex flex-wrap gap-3">
            <.admin_ghost_bar width="w-36" height="h-10" rounded="rounded-lg" />
            <.admin_ghost_bar width="w-28" height="h-10" rounded="rounded-lg" />
            <.admin_ghost_bar width="w-28" height="h-10" rounded="rounded-lg" />
          </div>
          <h3 class="text-base font-medium text-zinc-800 pt-2">Location</h3>
          <.admin_ghost_bar width="w-full" height="h-10" rounded="rounded-lg" />
          <.admin_ghost_bar width="w-full" height="h-10" rounded="rounded-lg" />
          <.admin_ghost_image ratio="aspect-[2/1]" class="rounded-lg" />
          <p class="text-sm text-zinc-600">
            Click on the map to set marker location.
          </p>
        </.admin_ghost_event_section>

        <.admin_ghost_event_section
          id="ghost-event-overview-section"
          title="Overview"
          subtitle="Add more details about the event to help attendees understand what to expect."
        >
          <.admin_ghost_trix_editor id="ghost-event-overview-editor" />
        </.admin_ghost_event_section>

        <.admin_ghost_event_section
          id="ghost-event-hosts-section"
          title="Hosts"
          subtitle="Search and add members who will be listed as hosts of this event."
        >
          <div class="flex flex-wrap gap-2">
            <span class="inline-flex items-center gap-2 rounded-full bg-zinc-100 pl-1 pr-3 py-1">
              <.admin_ghost_avatar size="h-7 w-7" />
              <span class="text-sm font-medium text-zinc-800">Alex Volunteer</span>
            </span>
          </div>
          <.ghost_search placeholder="Search members by name or email..." />
        </.admin_ghost_event_section>

        <.admin_ghost_event_section
          id="ghost-event-agenda-section"
          title="Agenda"
          subtitle="Add schedules or itineraries to help attendees plan their day."
        >
          <.button id="ghost-add-agenda-button">
            <.icon name="hero-plus" class="-mt-0.5" /> Add Agenda
          </.button>
          <div class="flex gap-3 overflow-x-auto pb-1">
            <.admin_ghost_agenda_panel />
          </div>
        </.admin_ghost_event_section>
      </div>
    </.ghost_admin_shell>
    """
  end

  defp events_tickets(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:events}>
      <.admin_ghost_event_editor_header active_tab={:tickets} state={:draft} />

      <div class="max-w-3xl space-y-6 pb-8">
        <.admin_ghost_event_section
          id="ghost-event-capacity-section"
          title="Event Capacity"
          subtitle="Set the maximum number of attendees for this event. This limit applies across all ticket tiers."
        >
          <label class="flex items-center gap-2 text-sm text-zinc-700">
            <input
              type="checkbox"
              class="rounded border-zinc-300 text-blue-600"
              disabled
            /> Unlimited capacity
          </label>
          <div class="space-y-1 max-w-xs">
            <p class="text-sm font-semibold text-zinc-800">Maximum Attendees</p>
            <.admin_ghost_bar width="w-full" height="h-10" rounded="rounded-lg" />
          </div>
        </.admin_ghost_event_section>

        <div
          id="ghost-event-ticket-tiers-section"
          class="border border-zinc-200 rounded-lg p-4 sm:p-6 bg-white space-y-4"
        >
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <h3 class="text-lg font-semibold text-zinc-900">Ticket Tiers</h3>
            <.button id="ghost-add-ticket-tier">
              <.icon name="hero-plus" class="w-4 h-4 me-1" /> Add Ticket Tier
            </.button>
          </div>
          <div class="space-y-3">
            <.admin_ghost_ticket_tier_card
              name="Member"
              type_label="Free"
              price="Free"
            />
            <.admin_ghost_ticket_tier_card
              name="Guest"
              type_label="Paid"
              price="$20.00"
            />
          </div>
        </div>
      </div>
    </.ghost_admin_shell>
    """
  end

  defp events_updates(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:events}>
      <.admin_ghost_event_editor_header active_tab={:updates} state={:published} />

      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 pb-8">
        <div class="lg:col-span-7 space-y-6">
          <.admin_ghost_event_section
            id="ghost-event-photo-upload"
            title="Event photo uploads"
            subtitle="Share this link with attendees so they can contribute photos after the event."
          >
            <div class="flex flex-col sm:flex-row gap-2">
              <.admin_ghost_bar
                width="w-full"
                height="h-10"
                rounded="rounded-lg"
                class="flex-1"
              />
              <.button variant="outline" color="zinc" class="shrink-0">
                <.icon name="hero-clipboard" class="w-5 h-5" /> Copy link
              </.button>
            </div>
          </.admin_ghost_event_section>

          <.admin_ghost_event_section
            id="ghost-event-update-composer"
            title="Send Update to Attendees"
            subtitle="Send a branded email notification to everyone who has a ticket for this event."
          >
            <p class="text-sm font-medium text-blue-600 -mt-2">
              48 recipient(s) will receive this update
            </p>
            <div class="space-y-3">
              <div class="space-y-1">
                <p class="text-sm font-semibold text-zinc-800">Title (optional)</p>
                <.admin_ghost_bar width="w-full" height="h-10" rounded="rounded-lg" />
              </div>
              <div class="space-y-1">
                <p class="text-sm font-semibold text-zinc-800">Message</p>
                <div class="border border-zinc-200 rounded-lg overflow-hidden min-h-[140px]">
                  <.admin_ghost_editor_body />
                </div>
              </div>
              <label class="flex items-center gap-2 text-sm text-zinc-700">
                <input
                  type="checkbox"
                  checked
                  class="rounded border-zinc-300 text-blue-600"
                  disabled
                /> Also show this update on the public event page
              </label>
              <div class="flex flex-wrap gap-3 pt-1">
                <.button color="blue">
                  <.icon name="hero-paper-airplane" class="w-5 h-5 -mt-0.5 me-1" />
                  Send Update
                </.button>
                <.button variant="outline" color="zinc">
                  <.icon name="hero-eye" class="w-5 h-5 -mt-0.5 me-1" /> Preview
                </.button>
              </div>
            </div>
          </.admin_ghost_event_section>
        </div>

        <aside id="ghost-event-communication-timeline" class="lg:col-span-5">
          <div class="rounded-xl border border-zinc-200 bg-white p-4 space-y-4">
            <h3 class="text-sm font-semibold text-zinc-800">
              Communication timeline
            </h3>
            <div :for={idx <- 1..2} class="flex gap-3">
              <span class={[
                "mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full",
                idx == 1 && "bg-blue-600",
                idx != 1 && "bg-zinc-300"
              ]}>
              </span>
              <div class="flex-1 space-y-1.5 pb-3 border-b border-zinc-100 last:border-0">
                <.admin_ghost_bar width="w-40" height="h-3" />
                <.admin_ghost_bar width="w-full" height="h-2.5" />
                <p class="text-xs text-zinc-500">Jun 1 · Emailed 48 attendees</p>
              </div>
            </div>
          </div>
        </aside>
      </div>
    </.ghost_admin_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Media, check-in, scanner
  # ---------------------------------------------------------------------------

  defp media_gallery(assigns) do
    ~H"""
    <.ghost_admin_shell active_page={:media}>
      <div class="flex justify-between items-center">
        <.admin_page_title>Media</.admin_page_title>
        <.button>
          <.icon name="hero-arrow-up-tray" class="w-5 h-5 -mt-0.5" />
          <span class="ms-1">Upload new images</span>
        </.button>
      </div>
      <div class="mt-4">
        <.ghost_search placeholder="Search by filename, title, or alt text..." />
      </div>
      <div class="mt-6 grid grid-cols-3 md:grid-cols-4 gap-3">
        <.admin_ghost_image
          :for={_ <- 1..8}
          class="rounded-lg"
          ratio="aspect-square"
        />
        <div class="aspect-square rounded-lg border-2 border-dashed border-blue-300 bg-blue-50/40 flex items-center justify-center">
          <.icon name="hero-arrow-up-tray" class="w-8 h-8 text-blue-400" />
        </div>
      </div>
    </.ghost_admin_shell>
    """
  end

  defp check_in_desk(assigns) do
    ~H"""
    <.admin_ghost_event_check_in_desk />
    """
  end

  defp scanner(assigns) do
    ~H"""
    <.admin_ghost_scanner />
    """
  end

  # ---------------------------------------------------------------------------
  # Shared shells
  # ---------------------------------------------------------------------------

  attr :active_page, :atom, required: true
  slot :inner_block, required: true

  defp ghost_admin_shell(assigns) do
    ~H"""
    <div class="admin-help-ghost-content py-4 px-4 lg:px-8">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :placeholder, :string, required: true
  attr :class, :string, default: nil

  defp ghost_search(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <.icon
        name="hero-magnifying-glass"
        class="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-zinc-500 pointer-events-none"
      />
      <input
        type="search"
        readonly
        tabindex="-1"
        placeholder={@placeholder}
        class="block w-full pt-3 pb-3 ps-10 text-sm text-zinc-800 border border-zinc-200 rounded bg-zinc-50 pointer-events-none"
      />
    </div>
    """
  end

  defp ghost_filter_button(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-zinc-700 border border-zinc-200 rounded-lg bg-white">
      <.icon name="hero-funnel" class="w-4 h-4" /> Filters
    </span>
    """
  end
end
