defmodule YscWeb.EventDetailsLive do
  use YscWeb, :live_view

  import YscWeb.Live.AsyncHelpers

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Repo

  alias Ysc.Agendas

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <%!-- Split-Header: Event Cover Image with Floating Card --%>
      <div class="max-w-screen-xl mx-auto px-4 pt-8">
        <div class="relative mb-4 lg:mb-24">
          <%!-- Image with rounded corners and gradient overlay --%>
          <div class={[
            "rounded-2xl overflow-hidden relative",
            if(@event.state == :cancelled, do: "opacity-50 grayscale")
          ]}>
            <.live_component
              id={"event-cover-#{@event.id}"}
              module={YscWeb.Components.Image}
              image_id={@event.image_id}
              preferred_type={:optimized}
              class="w-full h-[50vh] lg:h-[60vh] object-cover"
            />
            <%!-- Gradient overlay for better text readability --%>
            <div class="absolute inset-0 bg-gradient-to-t from-zinc-900/90 via-zinc-900/40 to-transparent pointer-events-none">
            </div>
            <%!-- Additional red overlay for cancelled events --%>
            <%= if @event.state == :cancelled do %>
              <div class="absolute inset-0 bg-red-900/30 pointer-events-none"></div>
            <% end %>
          </div>

          <%!-- Floating Card with Title/Date/Location - Overlaps bottom of image --%>
          <div class={[
            "relative -mt-16 mx-4 z-10 transition-all duration-500 ease-in-out",
            "lg:absolute lg:bottom-0 lg:left-0 lg:right-0 lg:translate-y-1/2 lg:mx-0 lg:px-8 lg:mt-0"
          ]}>
            <div class={[
              "bg-white rounded-xl shadow-2xl border p-6 lg:p-10 transform transition-transform duration-500",
              if(@event.state == :cancelled,
                do: "border-red-300",
                else: "border-zinc-100"
              )
            ]}>
              <div class="space-y-4">
                <%= if @event.state == :cancelled do %>
                  <div class="mb-4 p-4 bg-red-600 text-white rounded-lg shadow-lg">
                    <div class="flex items-center justify-center gap-3">
                      <.icon name="hero-x-circle-solid" class="w-5 h-5" />
                      <p class="font-black text-base uppercase tracking-widest">
                        This Event Has Been Cancelled
                      </p>
                      <.icon name="hero-x-circle-solid" class="w-5 h-5" />
                    </div>
                  </div>
                <% end %>

                <div :if={
                  @event.state != :cancelled && @async_data_loaded &&
                    @event_at_capacity
                }>
                  <.badge type="red">SOLD OUT</.badge>
                </div>

                <div
                  :if={
                    @event.start_date != nil && @event.start_date != "" &&
                      @event.state != :cancelled
                  }
                  class="flex items-center gap-3 mb-4"
                >
                  <p class="text-xs font-black text-blue-600 uppercase tracking-[0.2em]">
                    <%= format_start_date(@event.start_date) %>
                  </p>
                  <%= if @event_selling_fast do %>
                    <span class="h-3 w-px bg-zinc-200"></span>
                    <span class="text-[9px] font-black text-orange-600 bg-orange-50 px-2 py-0.5 rounded uppercase tracking-widest">
                      Going Fast!
                    </span>
                  <% end %>
                </div>

                <h1
                  :if={@event.title != nil && @event.title != ""}
                  class="text-2xl md:text-4xl lg:text-5xl font-black text-zinc-900 tracking-tighter leading-tight transition-all"
                >
                  <%= @event.title %>
                </h1>

                <p
                  :if={@event.description != nil && @event.description != ""}
                  class="hidden sm:block text-lg text-zinc-600 font-light leading-relaxed"
                >
                  <%= @event.description %>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Main Content Grid --%>
      <div class={[
        "max-w-screen-xl mx-auto px-4 pt-8 pb-12 lg:py-16",
        if(@event.state == :cancelled, do: "opacity-50 pointer-events-none")
      ]}>
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-16">
          <%!-- Left Column: Event Details (8/12 width on desktop) --%>
          <div class="lg:col-span-8 space-y-16">
            <%!-- User's Existing Tickets - Member Pass Style --%>
            <div
              :if={@current_user != nil && length(@user_tickets) > 0}
              class="mb-12 space-y-6"
            >
              <%= for {order_id, order_tickets} <- group_tickets_by_order(@user_tickets) do %>
                <% first_ticket = List.first(order_tickets) %>
                <% ticket_order = first_ticket.ticket_order %>
                <% order_label =
                  if ticket_order && ticket_order.reference_id do
                    ticket_order.reference_id
                  else
                    "Order ##{String.slice(order_id, 0, 8)}"
                  end %>
                <% purchase_date =
                  if ticket_order && ticket_order.completed_at do
                    Timex.format!(ticket_order.completed_at, "{Mshort} {D}, {YYYY}")
                  else
                    if first_ticket.inserted_at do
                      Timex.format!(
                        first_ticket.inserted_at,
                        "{Mshort} {D}, {YYYY}"
                      )
                    else
                      nil
                    end
                  end %>
                <%!-- Load all tickets for this order (including cancelled/refunded) from preloaded data --%>
                <% all_order_tickets = Map.get(@all_tickets_by_order, order_id, []) %>
                <% confirmed_tickets =
                  Enum.filter(all_order_tickets, &(&1.status == :confirmed)) %>
                <% refunded_tickets =
                  Enum.filter(all_order_tickets, &(&1.status == :cancelled)) %>
                <% all_refunded =
                  length(confirmed_tickets) == 0 && length(refunded_tickets) > 0 %>
                <% partial_refund =
                  length(confirmed_tickets) > 0 && length(refunded_tickets) > 0 %>
                <%!-- Group all tickets by tier (original counts) and confirmed tickets by tier (new counts) --%>
                <% all_tiers_by_name = group_tickets_by_tier(all_order_tickets) %>
                <% confirmed_tiers_by_name =
                  if length(confirmed_tickets) > 0,
                    do: group_tickets_by_tier(confirmed_tickets),
                    else: [] %>
                <div class={[
                  "rounded-xl p-10 shadow-2xl relative overflow-hidden border",
                  if(all_refunded,
                    do: "bg-red-900/90 border-red-800/50",
                    else: "bg-zinc-900 border-white/5"
                  )
                ]}>
                  <div class="relative z-10">
                    <%!-- Order Label Badge --%>
                    <div class="flex items-center justify-between mb-6">
                      <div class="flex items-center gap-2">
                        <span class={[
                          "px-3 py-1 text-[10px] font-black uppercase tracking-widest rounded-lg border",
                          if(all_refunded,
                            do: "bg-red-500/20 text-red-400 border-red-500/30",
                            else:
                              "bg-emerald-500/20 text-emerald-400 border-emerald-500/30"
                          )
                        ]}>
                          <%= order_label %>
                        </span>
                        <%= if purchase_date do %>
                          <span class={[
                            "text-[10px] uppercase tracking-widest",
                            if(all_refunded,
                              do: "text-red-300/70",
                              else: "text-zinc-500"
                            )
                          ]}>
                            • <%= purchase_date %>
                          </span>
                        <% end %>
                        <%= if all_refunded do %>
                          <span class="px-3 py-1 bg-red-500/20 text-red-300 text-[10px] font-black uppercase tracking-widest rounded-lg border border-red-500/30">
                            Fully Refunded
                          </span>
                        <% else %>
                          <%= if partial_refund do %>
                            <span class="px-3 py-1 bg-amber-500/20 text-amber-300 text-[10px] font-black uppercase tracking-widest rounded-lg border border-amber-500/30">
                              Partially Refunded
                            </span>
                          <% end %>
                        <% end %>
                      </div>
                    </div>

                    <div class="flex flex-col md:flex-row md:items-center justify-between gap-8">
                      <div class="flex items-center gap-5">
                        <div class={[
                          "w-14 h-14 rounded-2xl flex items-center justify-center ring-1",
                          if(all_refunded,
                            do: "bg-red-500/10 ring-red-500/50",
                            else: "bg-emerald-500/10 ring-emerald-500/50"
                          )
                        ]}>
                          <.icon
                            name={
                              if(all_refunded,
                                do: "hero-x-circle-solid",
                                else: "hero-check-badge-solid"
                              )
                            }
                            class={[
                              "w-8 h-8",
                              if(all_refunded,
                                do: "text-red-500",
                                else: "text-emerald-500"
                              )
                            ]}
                          />
                        </div>
                        <div>
                          <h3 class={[
                            "text-2xl font-black tracking-tight leading-none",
                            if(all_refunded, do: "text-red-100", else: "text-white")
                          ]}>
                            <%= if all_refunded do %>
                              Order Refunded
                            <% else %>
                              Your Tickets
                            <% end %>
                          </h3>
                          <%= if all_refunded do %>
                            <p class="text-sm text-red-200/80 mt-2">
                              All tickets in this order have been refunded and returned to stock.
                            </p>
                          <% else %>
                            <div class="mt-2 space-y-1">
                              <%= if partial_refund do %>
                                <p class="text-xs text-amber-300/90 uppercase tracking-widest font-bold mb-2">
                                  <%= length(confirmed_tickets) %> of <%= length(
                                    all_order_tickets
                                  ) %> tickets confirmed
                                </p>
                              <% end %>
                              <%= for {tier_name, confirmed_tier_tickets} <- confirmed_tiers_by_name do %>
                                <% original_count =
                                  case Enum.find(all_tiers_by_name, fn {name, _} ->
                                         name == tier_name
                                       end) do
                                    {_, original_tickets} ->
                                      length(original_tickets)

                                    nil ->
                                      length(confirmed_tier_tickets)
                                  end %>
                                <% new_count = length(confirmed_tier_tickets) %>
                                <% has_refunded_tickets = original_count > new_count %>
                                <p class={[
                                  "text-xs uppercase tracking-widest font-bold",
                                  if(all_refunded,
                                    do: "text-red-300/70",
                                    else: "text-zinc-500"
                                  )
                                ]}>
                                  <%= if partial_refund && has_refunded_tickets do %>
                                    <span class="line-through opacity-60">
                                      <%= original_count %>x
                                    </span>
                                    <span class="ml-1">
                                      <%= new_count %>x <%= tier_name %>
                                    </span>
                                  <% else %>
                                    <%= new_count %>x <%= tier_name %>
                                  <% end %>
                                </p>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      </div>
                      <.link
                        navigate={~p"/orders/#{order_id}/confirmation"}
                        class={[
                          "px-6 py-3 backdrop-blur-md rounded text-xs font-black uppercase tracking-widest transition-all",
                          if(all_refunded,
                            do:
                              "bg-red-500/20 hover:bg-red-500/30 text-red-200 border border-red-500/30",
                            else: "bg-white/10 hover:bg-white/20 text-white"
                          )
                        ]}
                      >
                        View Order
                      </.link>
                    </div>
                  </div>
                  <div class={[
                    "absolute -right-12 -top-12 w-40 h-40 blur-[80px] rounded-full",
                    if(all_refunded, do: "bg-red-500/10", else: "bg-emerald-500/10")
                  ]}>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Meta Info Row - Magazine Style --%>
            <% has_duration = @event.start_time != nil && @event.end_time != nil %>
            <div class={[
              "grid gap-0 border border-zinc-100 rounded-xl overflow-hidden bg-white shadow-sm mb-12",
              if has_duration do
                "grid-cols-1 md:grid-cols-3"
              else
                "grid-cols-1 md:grid-cols-2"
              end
            ]}>
              <div class={[
                "p-8 border-b",
                if has_duration do
                  "md:border-b-0 md:border-r md:border-dashed border-zinc-200"
                else
                  "md:border-b-0 md:border-r md:border-dashed border-zinc-200"
                end
              ]}>
                <p class="text-xs font-black text-blue-600 uppercase tracking-[0.2em] mb-2">
                  When
                </p>
                <p class="font-black text-xl text-zinc-900 tracking-tighter leading-none">
                  <%= if @event.start_date != nil do %>
                    <%= Timex.format!(@event.start_date, "{Mshort} {D}") %>
                  <% else %>
                    TBD
                  <% end %>
                </p>
                <p class="text-sm text-zinc-500 mt-2 font-medium">
                  <%= if @event.start_time != nil do %>
                    Starts at <%= case format_time(@event.start_time) do
                      %Time{} = time -> Timex.format!(time, "{h12}:{m} {AM}")
                      _ -> ""
                    end %>
                  <% else %>
                    Time TBD
                  <% end %>
                </p>
                <%= if !event_in_past?(@event) && @event.state != :cancelled do %>
                  <div class="mt-3 inline-flex items-center gap-2 bg-blue-50 px-2 py-1 rounded-full">
                    <span class="w-1.5 h-1.5 rounded-full bg-blue-500 animate-pulse">
                    </span>
                    <span class="text-[10px] font-black text-blue-600 uppercase tracking-widest">
                      Upcoming
                    </span>
                  </div>
                <% end %>
              </div>
              <div class={[
                "p-8 border-b",
                if has_duration do
                  "md:border-b-0 md:border-r md:border-dashed border-zinc-200"
                else
                  "md:border-b-0"
                end
              ]}>
                <p class="text-xs font-black text-blue-600 uppercase tracking-[0.2em] mb-2">
                  Where
                </p>
                <p class="font-black text-xl text-zinc-900 tracking-tighter leading-none">
                  <%= if @event.location_name != nil && @event.location_name != "" do %>
                    <%= @event.location_name %>
                  <% else %>
                    TBD
                  <% end %>
                </p>
                <p class="text-sm text-zinc-500 mt-2 font-medium">
                  <%= if @event.address != nil && @event.address != "" do %>
                    <%= @event.address %>
                  <% else %>
                    Location TBD
                  <% end %>
                </p>
              </div>
              <%= if has_duration do %>
                <div class="p-8 bg-zinc-50/30">
                  <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
                    Duration
                  </p>
                  <p class="font-black text-xl text-zinc-900 tracking-tighter leading-none">
                    <%= case {format_time(@event.start_time),
                              format_time(@event.end_time)} do
                      {%Time{} = start_time, %Time{} = end_time} ->
                        duration_minutes = Time.diff(end_time, start_time, :minute)
                        hours = div(duration_minutes, 60)
                        minutes = rem(duration_minutes, 60)

                        cond do
                          hours > 0 && minutes > 0 ->
                            "#{hours}h #{minutes}m"

                          hours > 0 ->
                            "#{hours} Hour#{if hours > 1, do: "s", else: ""}"

                          minutes > 0 ->
                            "#{minutes} Minute#{if minutes > 1, do: "s", else: ""}"

                          true ->
                            "TBD"
                        end

                      _ ->
                        "TBD"
                    end %>
                  </p>
                </div>
              <% end %>
            </div>

            <%!-- Location Details --%>
            <div
              :if={
                (@event.location_name != "" && @event.location_name != nil) ||
                  (@event.address != nil && @event.address != "")
              }
              class="space-y-4"
            >
              <div class="flex items-start gap-2">
                <.icon name="hero-map-pin" class="w-5 h-5 text-zinc-500 mt-1" />
                <div>
                  <p
                    :if={@event.location_name != nil && @event.location_name != ""}
                    class="font-semibold text-zinc-900"
                  >
                    <%= @event.location_name %>
                  </p>
                  <p
                    :if={@event.address != nil && @event.address != ""}
                    class="text-zinc-600"
                  >
                    <%= @event.address %>
                  </p>
                </div>
              </div>

              <div
                :if={
                  @event.latitude != nil && @event.longitude != nil &&
                    @event.latitude != "" &&
                    @event.longitude != ""
                }
                class="space-y-4"
              >
                <button
                  class="transition duration-200 ease-in-out hover:text-blue-800 text-blue-600 font-semibold"
                  phx-click={
                    JS.toggle_class("hidden",
                      to: "#event-map"
                    )
                    |> JS.toggle_class("rotate-180",
                      to: "#map-chevron"
                    )
                    |> JS.push("toggle-map")
                  }
                >
                  <span id="map-button-text">Show Map</span>
                  <.icon
                    name="hero-chevron-down"
                    id="map-chevron"
                    class="ms-1 w-5 h-5 transition-transform duration-200 -mt-0.5"
                  />
                </button>

                <div
                  id="event-map"
                  class="hidden bg-zinc-50 rounded-2xl border border-zinc-200 overflow-hidden"
                >
                  <.live_component
                    id={"#{@event.id}-map"}
                    module={YscWeb.Components.MapComponent}
                    event_id={@event.id}
                    latitude={@event.latitude}
                    longitude={@event.longitude}
                    locked={true}
                    class="max-w-screen-lg"
                  />

                  <div class="p-3">
                    <YscWeb.Components.MapNavigationButtons.map_navigation_buttons
                      latitude={@event.latitude}
                      longitude={@event.longitude}
                    />
                  </div>
                </div>
              </div>
            </div>

            <%!-- Agenda --%>
            <section :if={length(@agendas) > 0} class="space-y-6">
              <h3 class="text-2xl font-black text-zinc-900 tracking-tight mb-12 flex items-center gap-3">
                <span class="w-8 h-px bg-zinc-200"></span> Agenda
              </h3>

              <div :if={length(@agendas) > 1} class="py-2 mb-8">
                <ul class="flex flex-wrap gap-2 text-sm font-medium text-zinc-600">
                  <%= for agenda <- @agendas do %>
                    <li id={"agenda-selector-#{agenda.id}"}>
                      <button
                        phx-click="set-active-agenda"
                        phx-value-id={agenda.id}
                        class={[
                          "inline-flex items-center px-4 py-2 rounded-lg transition-colors",
                          agenda.id == @active_agenda && "text-white bg-blue-600",
                          agenda.id != @active_agenda &&
                            "text-zinc-600 bg-zinc-100 hover:bg-zinc-200 hover:text-zinc-800"
                        ]}
                      >
                        <%= agenda.title %>
                      </button>
                    </li>
                  <% end %>
                </ul>
              </div>

              <%= for agenda <- @agendas do %>
                <div
                  :if={agenda.id == @active_agenda}
                  class="relative pl-8 space-y-12"
                >
                  <%!-- Vertical Timeline Line --%>
                  <div class="absolute left-3 top-2 bottom-2 w-px bg-zinc-100">
                  </div>

                  <%= for agenda_item <- agenda.agenda_items do %>
                    <% is_current = agenda_item_current?(agenda_item, @event) %>
                    <div class="relative group">
                      <div class={[
                        "absolute -left-[25px] w-4 h-4 rounded-full border-4 border-white transition-all shadow-sm z-10 mt-1.5",
                        if is_current do
                          "bg-blue-600 animate-pulse"
                        else
                          "bg-zinc-200 group-hover:bg-blue-600 group-hover:scale-125"
                        end
                      ]}>
                      </div>
                      <div class="flex flex-col md:flex-row md:items-baseline gap-2 md:gap-8">
                        <div class="w-36 flex-shrink-0">
                          <span class="text-xs font-black text-blue-600 bg-blue-50 px-2.5 py-1 rounded-lg uppercase tracking-widest whitespace-nowrap group-hover:bg-blue-600 group-hover:text-white transition-colors">
                            <%= format_start_end(
                              agenda_item.start_time,
                              agenda_item.end_time
                            ) %>
                          </span>
                        </div>
                        <div class="flex-1 min-w-0">
                          <h4 class="text-lg font-black text-zinc-900 tracking-tight leading-none group-hover:text-blue-600 transition-colors">
                            <%= agenda_item.title %>
                          </h4>
                          <p
                            :if={agenda_item.description != nil}
                            class="text-sm text-zinc-500 font-light mt-2 leading-relaxed"
                          >
                            <%= agenda_item.description %>
                          </p>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </section>

            <%!-- Details --%>
            <section class="space-y-6">
              <h3 class="text-2xl font-black text-zinc-900 tracking-tight mb-6 flex items-center gap-3">
                <span class="w-8 h-px bg-zinc-200"></span> Details
              </h3>
              <article class="prose prose-zinc prose-lg max-w-none text-zinc-600 font-light leading-relaxed">
                <div id="article-body" class="post-render">
                  <%= raw(event_body(@event)) %>
                </div>
              </article>
            </section>
          </div>

          <%!-- Right Column: Sticky Ticket Sidebar (4/12 width on desktop) --%>
          <aside class="lg:col-span-4">
            <%!-- Spacer for mobile bottom bar --%>
            <div class="h-36 lg:hidden"></div>

            <%!-- Desktop: Sticky sidebar --%>
            <div
              :if={@event.state != :cancelled}
              class="hidden lg:block sticky top-24 space-y-8"
            >
              <div class="bg-white rounded-xl shadow-2xl border border-zinc-100 overflow-hidden">
                <%= if event_in_past?(@event) do %>
                  <div class="p-8 text-center bg-zinc-50/50">
                    <div class="text-red-500 mb-4">
                      <.icon name="hero-clock" class="w-10 h-10 mx-auto" />
                    </div>
                    <p class="text-red-700 font-semibold">Event has ended</p>
                    <p class="text-red-500 text-sm mt-1">
                      Tickets are no longer available
                    </p>
                  </div>
                <% else %>
                  <div class="p-8 text-center bg-zinc-50/50 shadow-[inset_0_-10px_20px_-15px_rgba(0,0,0,0.1)]">
                    <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.3em] mb-2">
                      Admission
                    </p>
                    <p class={[
                      "text-4xl font-black text-zinc-900 tracking-tighter",
                      if @event_at_capacity do
                        "line-through"
                      else
                        ""
                      end
                    ]}>
                      <%= @event.pricing_info.display_text %>
                    </p>
                    <p
                      :if={@event.start_date != nil}
                      class="text-sm text-zinc-500 mt-2"
                    >
                      <%= format_start_date(@event.start_date) %>
                    </p>
                  </div>
                <% end %>

                <%= if event_in_past?(@event) do %>
                  <!-- No additional content for past events -->
                <% else %>
                  <%!-- Ticket Perforation Line with Notch Cutouts --%>
                  <div class="relative h-px border-t-2 border-dashed border-zinc-200 mx-4">
                    <div class="absolute -left-11 -top-3 w-6 h-6 bg-white rounded-full border-r border-zinc-100 shadow-inner">
                    </div>
                    <div class="absolute -right-11 -top-3 w-6 h-6 bg-white rounded-full border-l border-zinc-100 shadow-inner">
                    </div>
                  </div>

                  <div class="p-8 space-y-6 shadow-[inset_0_10px_20px_-15px_rgba(0,0,0,0.05)]">
                    <%= if (@event_selling_fast || (@sold_percentage != nil && @sold_percentage >= 85)) && !@event_at_capacity do %>
                      <% available_capacity = @available_capacity %>
                      <% sold_percentage = @sold_percentage %>
                      <div class="p-4 bg-orange-50 rounded-xl border border-orange-100 space-y-3">
                        <div class="flex items-center gap-3">
                          <div class="flex-shrink-0 w-8 h-8 bg-orange-500 rounded-full flex items-center justify-center">
                            <.icon
                              name="hero-fire-solid"
                              class="w-4 h-4 text-white"
                            />
                          </div>
                          <p class="text-[11px] font-black text-orange-800 uppercase tracking-tight">
                            Demand is High
                          </p>
                        </div>
                        <%= if sold_percentage != nil do %>
                          <div class="space-y-2">
                            <div class="flex justify-between items-end">
                              <p class="text-[10px] font-black text-orange-600 uppercase tracking-widest">
                                Limited Availability
                              </p>
                              <p class="text-[10px] font-mono text-zinc-400">
                                <%= sold_percentage %>% Booked
                              </p>
                            </div>
                            <div class="w-full bg-zinc-100 h-1.5 rounded-full overflow-hidden">
                              <div
                                class="bg-orange-500 h-full transition-all duration-1000 animate-pulse"
                                style={"width: #{sold_percentage}%"}
                              >
                              </div>
                            </div>
                          </div>
                        <% else %>
                          <p class="text-[11px] text-orange-700 font-medium">
                            <%= if available_capacity != :unlimited &&
                                     available_capacity <= 10 do
                              "Less than #{available_capacity} spot#{if available_capacity == 1, do: "", else: "s"} remaining"
                            else
                              "Going Fast"
                            end %>
                          </p>
                        <% end %>
                      </div>
                    <% end %>

                    <div class="space-y-3">
                      <%= if @has_ticket_tiers do %>
                        <%!-- Loading skeleton for availability --%>
                        <div
                          :if={!@async_data_loaded}
                          class="flex items-center gap-3 text-sm text-zinc-400 font-medium animate-pulse"
                        >
                          <div class="w-5 h-5 bg-zinc-200 rounded"></div>
                          <div class="h-4 bg-zinc-200 rounded w-32"></div>
                        </div>
                        <div
                          :if={
                            @async_data_loaded && @available_capacity != :unlimited &&
                              !@event_at_capacity
                          }
                          class="flex items-center gap-3 text-sm text-zinc-600 font-medium"
                        >
                          <.icon name="hero-users" class="w-5 h-5 text-blue-500" />
                          <%= @available_capacity %> Spots Available
                        </div>
                        <%= if @async_data_loaded && @active_membership? && @attendees_count != nil && @attendees_count >= 5 && @attendees_list != nil && length(@attendees_list) > 0 do %>
                          <% attendees_to_show = Enum.take(@attendees_list, 5) %>
                          <% remaining_count =
                            length(@attendees_list) - length(attendees_to_show) %>
                          <% names_to_show = Enum.take(@attendees_list, 3) %>
                          <% names_remaining =
                            length(@attendees_list) - length(names_to_show) %>
                          <button
                            phx-click="show-attendees-modal"
                            class="flex items-center gap-3 text-sm text-zinc-600 font-medium hover:text-zinc-900 transition-colors cursor-pointer w-full text-left"
                          >
                            <%!-- Stack of profile pictures (max 5) --%>
                            <div class="flex -space-x-2 flex-shrink-0">
                              <%= for {attendee, index} <- Enum.with_index(attendees_to_show) do %>
                                <div class={[
                                  "relative w-8 h-8 rounded-full border-2 border-white overflow-hidden",
                                  if(index > 0, do: "-ml-2")
                                ]}>
                                  <.user_avatar_image
                                    email={attendee.email || ""}
                                    user_id={to_string(attendee.id)}
                                    country={
                                      attendee.most_connected_country || "SE"
                                    }
                                    class="w-full h-full object-cover"
                                  />
                                </div>
                              <% end %>
                              <%= if remaining_count > 0 do %>
                                <div class="relative w-8 h-8 rounded-full border-2 border-white bg-zinc-100 flex items-center justify-center -ml-2">
                                  <span class="text-xs font-semibold text-zinc-600">
                                    +<%= remaining_count %>
                                  </span>
                                </div>
                              <% end %>
                            </div>
                            <span class="flex-1 min-w-0">
                              <%= names_to_show
                              |> Enum.map(fn attendee ->
                                attendee_name =
                                  "#{attendee.first_name || ""} #{attendee.last_name || ""}"
                                  |> String.trim()

                                if attendee_name != "",
                                  do: attendee_name,
                                  else: attendee.email || "Someone"
                              end)
                              |> Enum.join(", ") %>
                              <%= if names_remaining > 0 do %>
                                +<%= names_remaining %> <%= if names_remaining == 1,
                                  do: "more is",
                                  else: "more are" %> going
                              <% else %>
                                <%= if length(@attendees_list) == 1,
                                  do: "is",
                                  else: "are" %> going
                              <% end %>
                            </span>
                          </button>
                        <% end %>
                      <% end %>
                    </div>

                    <div
                      :if={@current_user == nil && @has_ticket_tiers}
                      class="w-full space-y-4"
                    >
                      <div class="text-sm text-orange-700 px-3 py-2 bg-orange-50 rounded-lg border border-orange-200 text-center">
                        <.icon
                          name="hero-exclamation-circle"
                          class="text-orange-500 w-5 h-5 me-1 -mt-0.5"
                        />
                        You need to be signed in and have an active membership to purchase tickets
                      </div>
                      <.button
                        class="w-full py-4 uppercase tracking-widest"
                        phx-click={
                          JS.navigate(
                            ~p"/users/log-in?redirect_to=#{~p"/events/#{@event.id}"}"
                          )
                        }
                      >
                        <.icon name="hero-ticket" class="w-5 h-5 me-2 -mt-0.5" />Sign In to Continue
                      </.button>
                    </div>

                    <div
                      :if={
                        @current_user != nil && !@active_membership? &&
                          @has_ticket_tiers
                      }
                      class="w-full"
                    >
                      <div class="text-sm text-orange-700 px-3 py-2 bg-orange-50 rounded-lg border border-orange-200 text-center">
                        <.icon
                          name="hero-exclamation-circle"
                          class="text-orange-500 w-5 h-5 me-1 -mt-0.5"
                        /> Active membership required to purchase tickets
                      </div>
                    </div>

                    <%= if @has_ticket_tiers do %>
                      <%= if @event_at_capacity do %>
                        <div class="w-full">
                          <.tooltip tooltip_text="This event is sold out">
                            <.button
                              :if={@current_user != nil && @active_membership?}
                              class="w-full py-4 uppercase tracking-widest"
                              disabled
                            >
                              <.icon name="hero-ticket" class="me-2 -mt-0.5" />Sold Out
                            </.button>
                          </.tooltip>
                        </div>
                      <% else %>
                        <.button
                          :if={@current_user != nil && @active_membership?}
                          class="w-full py-4 uppercase tracking-widest"
                          phx-click="open-ticket-modal"
                        >
                          <.icon name="hero-ticket" class="me-2 -mt-0.5" />Get Tickets
                        </.button>
                      <% end %>
                    <% else %>
                      <div class="w-full text-center py-2">
                        <p class="font-bold text-green-700 text-sm">
                          No registration required
                        </p>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <%!-- Add to Calendar --%>
              <div
                :if={!event_in_past?(@event)}
                class="p-6 rounded-xl border border-zinc-100 flex items-center justify-between"
              >
                <span class="text-sm font-bold text-zinc-900">Don't forget.</span>
                <add-to-calendar-button
                  name={@event.title}
                  startDate={date_for_add_to_cal(@event.start_date)}
                  {if get_end_date_for_calendar(@event), do: [endDate: date_for_add_to_cal(get_end_date_for_calendar(@event))], else: []}
                  options="'Apple','Google','iCal','Outlook.com','Yahoo'"
                  startTime={@event.start_time}
                  {if get_end_time_for_calendar(@event), do: [endTime: get_end_time_for_calendar(@event)], else: []}
                  timeZone="America/Los_Angeles"
                  location={@event.location_name}
                  size="4"
                  lightMode="bodyScheme"
                >
                </add-to-calendar-button>
              </div>
            </div>

            <%!-- Mobile: Fixed bottom bar --%>
            <div
              :if={@event.state != :cancelled}
              class={[
                "lg:hidden fixed bottom-0 left-0 right-0 z-50",
                if(@event.state == :cancelled, do: "opacity-50 pointer-events-none")
              ]}
            >
              <div class="h-8 bg-gradient-to-t from-white to-transparent"></div>

              <div class="bg-white/95 backdrop-blur-md border-t border-zinc-100 px-6 py-5 shadow-[0_-10px_40px_-15px_rgba(0,0,0,0.1)]">
                <div class="max-w-screen-md mx-auto flex items-center justify-between gap-6">
                  <%= if event_in_past?(@event) do %>
                    <div class="flex-1 text-center">
                      <div class="text-red-700 font-black text-base">
                        Event Ended
                      </div>
                      <div class="text-red-500 text-xs mt-1">
                        Tickets are no longer available
                      </div>
                    </div>
                  <% else %>
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2 mb-0.5">
                        <p class={[
                          "font-black text-2xl text-zinc-900 tracking-tighter leading-none",
                          if @event_at_capacity do
                            "line-through"
                          else
                            ""
                          end
                        ]}>
                          <%= @event.pricing_info.display_text %>
                        </p>
                        <%= if @event_selling_fast && !@event_at_capacity do %>
                          <span class="text-[9px] font-black text-orange-600 uppercase tracking-widest bg-orange-50 px-1.5 py-0.5 rounded">
                            Going Fast
                          </span>
                        <% else %>
                          <%= if event_live?(@event) do %>
                            <span class="text-[9px] font-black text-blue-600 uppercase tracking-widest bg-blue-50 px-1.5 py-0.5 rounded">
                              Live
                            </span>
                          <% end %>
                        <% end %>
                      </div>
                      <p
                        :if={@event.start_date != nil}
                        class="text-[10px] font-bold text-zinc-400 uppercase tracking-widest truncate"
                      >
                        <%= format_start_date(@event.start_date) %>
                        <%= if @event.start_time != nil do %>
                          • <%= case format_time(@event.start_time) do
                            %Time{} = time -> Timex.format!(time, "{h12}:{m} {AM}")
                            _ -> ""
                          end %>
                        <% end %>
                      </p>
                    </div>
                  <% end %>

                  <%= if event_in_past?(@event) do %>
                    <!-- No action button for past events -->
                  <% else %>
                    <%= if @current_user == nil && @has_ticket_tiers do %>
                      <.button
                        class="flex-shrink-0 px-8 py-3.5 uppercase tracking-widest"
                        phx-click={
                          JS.navigate(
                            ~p"/users/log-in?redirect_to=#{~p"/events/#{@event.id}"}"
                          )
                        }
                      >
                        <.icon name="hero-ticket" class="w-5 h-5 me-2 -mt-0.5" />Sign In to Continue
                      </.button>
                    <% else %>
                      <%= if @has_ticket_tiers do %>
                        <%= if @event_at_capacity do %>
                          <div class="text-red-700 font-black text-sm text-center">
                            Sold Out
                          </div>
                        <% else %>
                          <%= if @active_membership? do %>
                            <.button
                              class="flex-shrink-0 px-8 py-3.5 uppercase tracking-widest"
                              phx-click="open-ticket-modal"
                            >
                              <.icon
                                name="hero-ticket"
                                class="w-5 h-5 me-2 -mt-0.5"
                              />Get Tickets
                            </.button>
                          <% else %>
                            <div class="text-orange-700 font-black text-sm text-center">
                              Membership Required
                            </div>
                          <% end %>
                        <% end %>
                      <% else %>
                        <span class="text-xs font-black text-green-700 uppercase tracking-widest">
                          No registration required
                        </span>
                      <% end %>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          </aside>
        </div>
      </div>
    </div>
    <!-- Ticket Selection Modal -->
    <.modal
      :if={@show_ticket_modal}
      id="ticket-modal"
      show
      on_cancel={JS.push("close-ticket-modal")}
      max_width="max-w-6xl"
    >
      <div class="flex flex-col lg:flex-row gap-8 min-h-[600px]">
        <!-- Left Panel: Ticket Tiers -->
        <div class="lg:w-2/3 space-y-8">
          <div class="w-full border-b border-zinc-200 pb-4">
            <h2 class="text-2xl font-semibold"><%= @event.title %></h2>
            <p :if={@event.start_date != nil} class="text-sm text-zinc-600">
              <%= format_start_date(@event.start_date) %>
            </p>
          </div>

          <div class="space-y-4 h-full lg:overflow-y-auto lg:max-h-[600px] lg:px-4">
            <%= for ticket_tier <- @ticket_tiers do %>
              <% is_donation =
                ticket_tier.type == "donation" || ticket_tier.type == :donation %>
              <% available = get_available_quantity(ticket_tier) %>
              <% is_event_at_capacity = @event_at_capacity %>
              <% is_sold_out =
                if is_donation,
                  do: false,
                  else: available == 0 || is_event_at_capacity %>
              <% is_on_sale =
                if is_donation, do: true, else: tier_on_sale?(ticket_tier) %>
              <% is_sale_ended =
                if is_donation, do: false, else: tier_sale_ended?(ticket_tier) %>
              <% days_until_sale =
                if is_donation, do: nil, else: days_until_sale_starts(ticket_tier) %>
              <% is_pre_sale =
                if is_donation, do: false, else: not is_on_sale && !is_sale_ended %>
              <% has_selected_tickets =
                get_ticket_quantity(@selected_tickets, ticket_tier.id) > 0 %>
              <% reserved_quantity =
                Map.get(@reservations_by_tier, ticket_tier.id, 0) %>
              <% has_reservation = reserved_quantity > 0 %>
              <% reservation_info =
                get_reservation_discount_info(
                  ticket_tier.id,
                  reserved_quantity,
                  @reservations_by_tier,
                  @user_reservations,
                  ticket_tier.price
                ) %>
              <% has_discount =
                reservation_info.discount_percentage != nil &&
                  reservation_info.discount_percentage > 0 %>
              <div class={[
                "border rounded-lg p-6 transition-all duration-200",
                cond do
                  is_sold_out -> "border-zinc-200 bg-zinc-50 opacity-60"
                  is_sale_ended -> "border-zinc-200 bg-zinc-50 opacity-60"
                  is_pre_sale -> "border-zinc-200 bg-zinc-50 opacity-70"
                  has_selected_tickets -> "border-blue-500 bg-blue-50"
                  true -> "border-zinc-200 bg-white"
                end
              ]}>
                <div class="flex justify-between items-start mb-4">
                  <div>
                    <div class="flex items-center gap-2">
                      <h4 class="font-semibold text-lg text-zinc-900">
                        <%= ticket_tier.name %>
                      </h4>
                      <%= if has_reservation do %>
                        <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700 border border-blue-200">
                          <.icon name="hero-ticket" class="w-3 h-3" />
                          <%= reserved_quantity %> reserved
                        </span>
                      <% end %>
                    </div>
                    <p
                      :if={ticket_tier.description}
                      class="text-base text-zinc-600 mt-2"
                    >
                      <%= ticket_tier.description %>
                    </p>
                    <%= if has_reservation do %>
                      <div class="mt-1 space-y-1">
                        <p class="text-sm text-blue-600 font-medium">
                          You have <%= reserved_quantity %> <%= if reserved_quantity ==
                                                                     1,
                                                                   do: "ticket",
                                                                   else: "tickets" %> reserved for this tier
                          <%= if has_discount do %>
                            <.badge
                              type="green"
                              class="inline-flex items-center gap-1 ml-2 py-0.5 rounded-full border border-green-200 text-green-700 me-0"
                            >
                              <.icon name="hero-tag" class="w-3 h-3" />
                              <%= reservation_info.discount_percentage
                              |> Float.round(2) %>% off
                            </.badge>
                          <% end %>
                        </p>
                        <%= if has_discount && Money.positive?(reservation_info.discount_savings) do %>
                          <p class="text-xs text-green-600">
                            You'll save <%= format_price(
                              reservation_info.discount_savings
                            ) %> with your reserved tickets
                          </p>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  <div class="text-right">
                    <p
                      :if={
                        ticket_tier.type != "donation" &&
                          ticket_tier.type != :donation
                      }
                      class={[
                        "font-semibold text-xl",
                        if is_event_at_capacity do
                          "line-through"
                        else
                          ""
                        end
                      ]}
                    >
                      <%= case ticket_tier.type do %>
                        <% "free" -> %>
                          Free
                        <% _ -> %>
                          <%= format_price(ticket_tier.price) %>
                      <% end %>
                    </p>
                    <p
                      :if={
                        ticket_tier.type != "donation" &&
                          ticket_tier.type != :donation
                      }
                      id={"tier-availability-#{ticket_tier.id}"}
                      class={[
                        "text-base text-sm transition-colors duration-200",
                        cond do
                          is_sold_out -> "text-red-500 font-semibold"
                          is_sale_ended -> "text-red-500 font-semibold"
                          is_pre_sale -> "text-blue-500 font-semibold"
                          true -> "text-zinc-500"
                        end
                      ]}
                    >
                      <%= cond do %>
                        <% is_sale_ended -> %>
                          Sale ended
                        <% is_pre_sale -> %>
                          Sale starts in <%= days_until_sale %> <%= if days_until_sale ==
                                                                         1,
                                                                       do: "day",
                                                                       else: "days" %>
                        <% is_event_at_capacity -> %>
                          Sold Out (Event at capacity)
                        <% available == :unlimited -> %>
                          Unlimited
                        <% available == 0 -> %>
                          Sold Out
                        <% true -> %>
                          <%= "#{available} remaining" %>
                      <% end %>
                    </p>
                  </div>
                </div>

                <%= if ticket_tier.type == "donation" || ticket_tier.type == :donation do %>
                  <!-- Donation Amount Input -->
                  <div class="flex flex-col space-y-3 mt-4">
                    <div class="flex items-center justify-end">
                      <div class="flex items-center space-x-3 w-full sm:w-auto">
                        <label class="text font-semibold text-zinc-700 whitespace-nowrap">
                          Donation Amount:
                        </label>
                        <div class="flex items-center border border-zinc-300 rounded-lg px-3 py-1 flex-1 sm:flex-initial bg-white">
                          <span class="text-zinc-800">$</span>
                          <input
                            type="text"
                            id={"donation-amount-#{ticket_tier.id}"}
                            name={"donation_amount_#{ticket_tier.id}"}
                            phx-hook="MoneyInput"
                            data-tier-id={ticket_tier.id}
                            value={
                              format_donation_amount(
                                @selected_tickets,
                                ticket_tier.id
                              )
                            }
                            placeholder="0.00"
                            disabled={false}
                            class="w-full sm:w-32 border-0 focus:ring-0 focus:outline-none font-medium text-zinc-900"
                          />
                        </div>
                      </div>
                    </div>
                    <!-- Quick Amount Buttons -->
                    <div class="flex items-center justify-end gap-2">
                      <button
                        type="button"
                        phx-click="set-donation-amount"
                        phx-value-tier-id={ticket_tier.id}
                        phx-value-amount="1000"
                        class="px-3 py-1.5 text-sm font-medium rounded-md border transition-colors border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50 hover:border-zinc-400"
                      >
                        $10
                      </button>
                      <button
                        type="button"
                        phx-click="set-donation-amount"
                        phx-value-tier-id={ticket_tier.id}
                        phx-value-amount="2500"
                        class="px-3 py-1.5 text-sm font-medium rounded-md border transition-colors border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50 hover:border-zinc-400"
                      >
                        $25
                      </button>
                      <button
                        type="button"
                        phx-click="set-donation-amount"
                        phx-value-tier-id={ticket_tier.id}
                        phx-value-amount="5000"
                        class="px-3 py-1.5 text-sm font-medium rounded-md border transition-colors border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50 hover:border-zinc-400"
                      >
                        $50
                      </button>
                    </div>
                  </div>
                  <!-- Donation Disclaimer -->
                  <div class="mt-2 items-center bg-zinc-50 px-3 py-2 rounded-md w-full flex flex-row border border-zinc-200">
                    <.icon
                      name="hero-exclamation-circle"
                      class="text-zinc-600 w-5 h-5 me-1"
                    />
                    <p class="text-sm text-zinc-600">
                      A donation is not a ticket to the event
                    </p>
                  </div>
                <% else %>
                  <!-- Regular Quantity Selector -->
                  <div class="flex items-center justify-end mt-4">
                    <div class="flex items-center space-x-3">
                      <button
                        phx-click="decrease-ticket-quantity"
                        phx-value-tier-id={ticket_tier.id}
                        phx-debounce="150"
                        class={[
                          "w-10 h-10 rounded-full border flex items-center justify-center transition-colors",
                          if(
                            is_sold_out or is_sale_ended or is_pre_sale or
                              get_ticket_quantity(@selected_tickets, ticket_tier.id) ==
                                0
                          ) do
                            "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed"
                          else
                            "border-zinc-300 hover:bg-zinc-50 text-zinc-700"
                          end
                        ]}
                        disabled={
                          is_sold_out or is_sale_ended or is_pre_sale or
                            get_ticket_quantity(@selected_tickets, ticket_tier.id) ==
                              0
                        }
                      >
                        <.icon name="hero-minus" class="w-5 h-5" />
                      </button>
                      <span class={[
                        "w-12 text-center font-medium text-lg",
                        if(is_sold_out or is_sale_ended or is_pre_sale,
                          do: "text-zinc-400",
                          else: "text-zinc-900"
                        )
                      ]}>
                        <%= get_ticket_quantity(@selected_tickets, ticket_tier.id) %>
                      </span>
                      <% current_qty =
                        get_ticket_quantity(@selected_tickets, ticket_tier.id) %>
                      <% can_increase =
                        can_increase_quantity_cached?(
                          ticket_tier,
                          current_qty,
                          @selected_tickets,
                          @event,
                          @availability_data,
                          @ticket_tiers,
                          @current_user && @current_user.id
                        ) %>
                      <button
                        phx-click="increase-ticket-quantity"
                        phx-value-tier-id={ticket_tier.id}
                        phx-debounce="150"
                        class={[
                          "w-10 h-10 rounded-full border-2 flex items-center justify-center transition-all duration-200 font-semibold",
                          if(
                            is_sold_out or is_sale_ended or is_pre_sale or
                              !can_increase
                          ) do
                            "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed"
                          else
                            "border-blue-700 bg-blue-700 hover:bg-blue-800 hover:border-blue-800 text-white"
                          end
                        ]}
                        disabled={
                          is_sold_out or is_sale_ended or is_pre_sale or
                            !can_increase
                        }
                      >
                        <.icon name="hero-plus" class="w-5 h-5" />
                      </button>
                    </div>
                  </div>
                <% end %>
                <!-- Show message for different tier states (exclude donation tiers) -->
                <div :if={!is_donation && is_pre_sale} class="mt-2">
                  <p class="text-sm text-blue-600 bg-blue-50 px-3 py-2 rounded-md border border-blue-200">
                    <.icon name="hero-clock" class="w-4 h-4 inline me-1" />
                    Sale starts <%= Timex.format!(
                      ticket_tier.start_date,
                      "{Mshort} {D}, {YYYY}"
                    ) %>
                  </p>
                </div>

                <div :if={!is_donation && is_sale_ended} class="mt-2">
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-x-circle" class="w-4 h-4 inline me-1" />
                    Sale ended on <%= Timex.format!(
                      ticket_tier.end_date,
                      "{Mshort} {D}, {YYYY}"
                    ) %>
                  </p>
                </div>

                <div :if={!is_donation && is_sold_out} class="mt-2">
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-x-circle" class="w-4 h-4 inline me-1" />
                    This ticket tier is sold out
                  </p>
                </div>

                <div
                  :if={
                    !is_donation && !is_sold_out && !is_pre_sale && !is_sale_ended &&
                      available != :unlimited &&
                      get_ticket_quantity(@selected_tickets, ticket_tier.id) >=
                        available
                  }
                  class="mt-2"
                >
                  <p class="text-sm text-amber-600 bg-amber-50 px-3 py-2 rounded-md border border-amber-200">
                    <.icon
                      name="hero-exclamation-triangle"
                      class="w-4 h-4 inline me-1"
                    /> Maximum available tickets selected
                  </p>
                </div>

                <% available_capacity = @available_capacity %>
                <div
                  :if={
                    !is_donation && !is_sold_out && !is_pre_sale && !is_sale_ended &&
                      @event.max_attendees &&
                      available_capacity != :unlimited &&
                      calculate_total_selected_tickets(
                        @selected_tickets,
                        @event.id,
                        @ticket_tiers
                      ) >=
                        available_capacity
                  }
                  class="mt-2"
                >
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-users" class="w-4 h-4 inline me-1" />
                    Event capacity reached. No more tickets available.
                  </p>
                </div>

                <div :if={!is_donation && is_event_at_capacity} class="mt-2">
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-users" class="w-4 h-4 inline me-1" />
                    Event is at capacity (<%= @event.max_attendees %> attendees). All tickets are sold out.
                  </p>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Right Panel: Price Breakdown -->
        <div class="lg:w-1/3 space-y-4 justify-between flex flex-col">
          <div class="space-y-4">
            <div class="w-full hidden lg:block">
              <.live_component
                id={"event-checkout-#{@event.id}"}
                module={YscWeb.Components.Image}
                image_id={@event.image_id}
                preferred_type={:optimized}
              />
            </div>

            <div>
              <h2 class="text-lg font-semibold mb-6 hidden lg:block">
                <%= @event.title %>
              </h2>
              <h3 class="font-semibold mb-2">Order Summary</h3>
            </div>

            <div class="bg-zinc-50 rounded-lg p-6 space-y-4 flex flex-col justify-between">
              <%= if has_any_tickets_selected?(@selected_tickets) do %>
                <% pricing =
                  calculate_pricing_with_discounts(
                    @selected_tickets,
                    @event.id,
                    @ticket_tiers,
                    @reservations_by_tier,
                    @current_user,
                    @user_reservations
                  ) %>
                <%= for breakdown <- pricing.tier_breakdowns do %>
                  <div class="space-y-1">
                    <div class="flex justify-between text-base">
                      <span>
                        <%= breakdown.tier_name %>
                        <%= if breakdown.quantity > 1 do %>
                          × <%= breakdown.quantity %>
                        <% end %>
                      </span>
                      <span class={[
                        "font-medium",
                        if @event_at_capacity do
                          "line-through"
                        else
                          ""
                        end
                      ]}>
                        <%= if Money.positive?(breakdown.original_price) && Money.positive?(breakdown.discount_amount) do %>
                          <span class="text-zinc-400 line-through mr-2">
                            <%= format_price(breakdown.original_price) %>
                          </span>
                        <% end %>
                        <%= format_price(breakdown.final_price) %>
                      </span>
                    </div>
                    <%= if breakdown.discount_percentage && breakdown.discount_percentage > 0 do %>
                      <div class="flex justify-between text-sm text-green-600">
                        <span>
                          Reserved discount (<%= breakdown.discount_percentage
                          |> Float.round(2) %>%)
                        </span>
                        <span class="font-medium">
                          -<%= format_price(breakdown.discount_amount) %>
                        </span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              <% else %>
                <div class="text-center py-4">
                  <div class="text-zinc-400 mb-2">
                    <.icon name="hero-shopping-cart" class="w-8 h-8 mx-auto" />
                  </div>
                  <p class="text-zinc-500 text-sm">No tickets selected</p>
                  <p class="hidden lg:block text-zinc-400 text-sm mt-1">
                    Select tickets from the left to see your order
                  </p>
                </div>
              <% end %>

              <%= if has_any_tickets_selected?(@selected_tickets) do %>
                <% pricing =
                  calculate_pricing_with_discounts(
                    @selected_tickets,
                    @event.id,
                    @ticket_tiers,
                    @reservations_by_tier,
                    @current_user,
                    @user_reservations
                  ) %>
                <div class="border-t border-zinc-200 pt-4 space-y-2">
                  <%= if Money.positive?(pricing.discount_amount) do %>
                    <div class="flex justify-between text-sm text-zinc-600">
                      <span>Subtotal:</span>
                      <span><%= format_price(pricing.subtotal) %></span>
                    </div>
                    <div class="flex justify-between text-sm text-green-600 font-medium">
                      <span>Discount:</span>
                      <span>-<%= format_price(pricing.discount_amount) %></span>
                    </div>
                  <% end %>
                  <div class="flex justify-between font-semibold text-lg">
                    <span>Total:</span>
                    <span class={[
                      if @event_at_capacity do
                        "line-through"
                      else
                        ""
                      end
                    ]}>
                      <%= format_price(pricing.total) %>
                    </span>
                  </div>
                </div>
              <% else %>
                <div class="border-t border-zinc-200 pt-4">
                  <div class="flex justify-between font-semibold text-lg">
                    <span>Total:</span>
                    <span class={[
                      if @event_at_capacity do
                        "line-through"
                      else
                        ""
                      end
                    ]}>
                      <%= calculate_total_price(
                        @selected_tickets,
                        @event.id,
                        @ticket_tiers,
                        @reservations_by_tier,
                        @current_user,
                        @user_reservations
                      ) %>
                    </span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <div class="mt-8 space-y-4">
            <.button
              class="w-full text-lg py-3"
              phx-click="proceed-to-checkout"
              disabled={!has_any_tickets_selected?(@selected_tickets)}
            >
              <.icon name="hero-shopping-cart" class="me-2 -mt-1" />Proceed to Checkout
            </.button>
          </div>
        </div>
      </div>
    </.modal>
    <!-- Payment Modal -->
    <.modal
      :if={@show_payment_modal}
      id="payment-modal"
      show
      on_cancel={JS.push("close-payment-modal")}
      max_width="max-w-6xl"
    >
      <%= if @checkout_expired do %>
        <!-- Checkout Expired State -->
        <div class="flex flex-col items-center justify-center py-16 space-y-6">
          <div class="text-center">
            <div class="text-red-500 mb-4">
              <.icon name="hero-clock" class="w-16 h-16 mx-auto" />
            </div>
            <h2 class="text-2xl font-semibold text-red-700 mb-2">
              Checkout Session Expired
            </h2>
            <p class="text-zinc-600 max-w-md">
              Your checkout session has expired. The tickets you selected may no longer be available.
              Please start over to select your tickets again.
            </p>
          </div>

          <div class="flex space-x-4">
            <.button
              class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-3"
              phx-click="retry-checkout"
            >
              <.icon name="hero-arrow-path" class="w-5 h-5 me-2" /> Try Again
            </.button>
            <.button
              class="bg-zinc-200 text-zinc-800 hover:bg-zinc-300 px-6 py-3"
              phx-click="close-payment-modal"
            >
              Close
            </.button>
          </div>
        </div>
      <% else %>
        <!-- Normal Payment Flow -->
        <!-- Sticky Timer Banner at Top -->
        <div class="sticky top-0 z-10 bg-blue-50 border-b border-blue-200 -mx-6 -mt-2 px-6 pt-3 pb-3 mb-6">
          <div class="flex items-center justify-center space-x-2">
            <.icon name="hero-clock" class="w-5 h-5 text-blue-600" />
            <span class="text-sm font-medium text-blue-800">
              Time remaining to complete purchase:
            </span>
            <div
              id="checkout-timer"
              class="font-bold text-blue-900"
              phx-hook="CheckoutTimer"
              data-expires-at={@ticket_order.expires_at}
            >
              <!-- Timer will be populated by JavaScript -->
            </div>
          </div>
        </div>

        <div class="flex flex-col lg:flex-row gap-8 min-h-[600px]">
          <!-- Left Panel: Payment Details -->
          <div class="lg:w-2/3 space-y-6">
            <div class="text-center">
              <h2 class="text-2xl font-semibold">Complete Your Purchase</h2>
              <p class="text-zinc-600 mt-2">
                Order: <%= @ticket_order.reference_id %>
              </p>
            </div>

            <%!-- Registration Section - Show if tickets require registration --%>
            <% tickets_requiring_registration =
              get_tickets_requiring_registration(@ticket_order.tickets || []) %>
            <%= if Enum.any?(tickets_requiring_registration) do %>
              <div class="space-y-4 border-b border-zinc-200 pb-6">
                <div class="flex items-center justify-between">
                  <div>
                    <% all_registrations_complete_for_step1 =
                      if Enum.any?(tickets_requiring_registration) do
                        tickets_requiring_registration
                        |> Enum.all?(fn ticket ->
                          tickets_for_me = @tickets_for_me || %{}

                          is_for_me =
                            Map.get(tickets_for_me, ticket.id, false) ||
                              Map.get(tickets_for_me, to_string(ticket.id), false)

                          selected_family_members = @selected_family_members || %{}

                          selected_family_member_id =
                            Map.get(selected_family_members, ticket.id) ||
                              Map.get(selected_family_members, to_string(ticket.id))

                          family_members = @family_members || []

                          selected_family_member =
                            if selected_family_member_id,
                              do:
                                Enum.find(family_members, fn u ->
                                  u.id == selected_family_member_id ||
                                    to_string(u.id) ==
                                      to_string(selected_family_member_id)
                                end),
                              else: nil

                          has_selected_family_member =
                            not is_nil(selected_family_member)

                          ticket_id_str = to_string(ticket.id)

                          cond do
                            is_for_me ->
                              @current_user.first_name &&
                                @current_user.first_name != "" &&
                                (@current_user.last_name &&
                                   @current_user.last_name != "") &&
                                (@current_user.email && @current_user.email != "")

                            has_selected_family_member ->
                              selected_family_member.first_name &&
                                selected_family_member.first_name != "" &&
                                (selected_family_member.last_name &&
                                   selected_family_member.last_name != "") &&
                                (selected_family_member.email &&
                                   selected_family_member.email != "")

                            true ->
                              form_map =
                                Map.get(@ticket_details_form, ticket_id_str) ||
                                  Map.get(@ticket_details_form, ticket.id) || %{}

                              first_name =
                                Map.get(form_map, :first_name) ||
                                  Map.get(form_map, "first_name") ||
                                  ""

                              last_name =
                                Map.get(form_map, :last_name) ||
                                  Map.get(form_map, "last_name") || ""

                              email =
                                Map.get(form_map, :email) ||
                                  Map.get(form_map, "email") || ""

                              first_name != "" && last_name != "" && email != "" &&
                                String.contains?(email, "@")
                          end
                        end)
                      else
                        true
                      end %>
                    <div class="flex items-center gap-2 mb-1">
                      <span class={[
                        "flex items-center justify-center w-6 h-6 rounded-full text-sm font-semibold",
                        if(all_registrations_complete_for_step1,
                          do: "bg-green-600 text-white",
                          else: "bg-blue-600 text-white"
                        )
                      ]}>
                        <%= if all_registrations_complete_for_step1 do %>
                          <.icon name="hero-check" class="w-4 h-4" />
                        <% else %>
                          1
                        <% end %>
                      </span>
                      <h3 class="font-semibold text-lg">Who's going?</h3>
                    </div>
                    <p class="text-sm text-zinc-600 ml-8">
                      Please provide details for each ticket that requires registration.
                    </p>
                  </div>
                </div>

                <%= for {ticket, index} <- Enum.with_index(tickets_requiring_registration) do %>
                  <% tickets_for_me = @tickets_for_me || %{} %>
                  <% is_for_me =
                    Map.get(tickets_for_me, ticket.id, false) ||
                      Map.get(tickets_for_me, to_string(ticket.id), false) %>

                  <%!-- Check if "Me" is already selected for any other ticket --%>
                  <% me_already_selected_for_other_ticket =
                    tickets_requiring_registration
                    |> Enum.any?(fn other_ticket ->
                      other_ticket.id != ticket.id &&
                        (Map.get(tickets_for_me, other_ticket.id, false) ||
                           Map.get(
                             tickets_for_me,
                             to_string(other_ticket.id),
                             false
                           ))
                    end) %>

                  <% selected_family_members = @selected_family_members || %{} %>
                  <% selected_family_member_id =
                    Map.get(selected_family_members, ticket.id) ||
                      Map.get(selected_family_members, to_string(ticket.id)) %>
                  <% family_members = @family_members || [] %>
                  <% selected_family_member =
                    if selected_family_member_id,
                      do:
                        Enum.find(family_members, fn u ->
                          u.id == selected_family_member_id ||
                            to_string(u.id) == to_string(selected_family_member_id)
                        end),
                      else: nil %>
                  <% has_selected_family_member = not is_nil(selected_family_member) %>
                  <% ticket_id_str = to_string(ticket.id)

                  # Check if this ticket registration is complete
                  is_registration_complete =
                    cond do
                      is_for_me ->
                        # "Me" is selected - check if user has required fields
                        @current_user.first_name && @current_user.first_name != "" &&
                          (@current_user.last_name && @current_user.last_name != "") &&
                          (@current_user.email && @current_user.email != "")

                      has_selected_family_member ->
                        # Family member is selected - check if they have required fields
                        selected_family_member.first_name &&
                          selected_family_member.first_name != "" &&
                          (selected_family_member.last_name &&
                             selected_family_member.last_name != "") &&
                          (selected_family_member.email &&
                             selected_family_member.email != "")

                      true ->
                        # Manual entry - check if all fields are filled
                        form_map =
                          Map.get(@ticket_details_form, ticket_id_str) ||
                            Map.get(@ticket_details_form, ticket.id) || %{}

                        first_name =
                          Map.get(form_map, :first_name) ||
                            Map.get(form_map, "first_name") || ""

                        last_name =
                          Map.get(form_map, :last_name) ||
                            Map.get(form_map, "last_name") || ""

                        email =
                          Map.get(form_map, :email) || Map.get(form_map, "email") ||
                            ""

                        first_name != "" && last_name != "" && email != "" &&
                          String.contains?(email, "@")
                    end

                  form_data =
                    cond do
                      is_for_me ->
                        # Auto-fill with current user's details
                        %{
                          first_name: @current_user.first_name || "",
                          last_name: @current_user.last_name || "",
                          email: @current_user.email || ""
                        }

                      has_selected_family_member ->
                        # Use selected family member's details
                        %{
                          first_name: selected_family_member.first_name || "",
                          last_name: selected_family_member.last_name || "",
                          email: selected_family_member.email || ""
                        }

                      true ->
                        # Use form data from @ticket_details_form (in-memory state only)
                        # Don't query database on every render - form data is managed in memory
                        case Map.get(@ticket_details_form, ticket_id_str) ||
                               Map.get(@ticket_details_form, ticket.id) do
                          nil ->
                            # No form data yet, use empty values
                            %{
                              first_name: "",
                              last_name: "",
                              email: ""
                            }

                          form_map ->
                            # Use form data, but ensure all fields exist (fill missing ones with empty string)
                            %{
                              first_name:
                                Map.get(form_map, :first_name) ||
                                  Map.get(form_map, "first_name") ||
                                  "",
                              last_name:
                                Map.get(form_map, :last_name) ||
                                  Map.get(form_map, "last_name") || "",
                              email:
                                Map.get(form_map, :email) ||
                                  Map.get(form_map, "email") || ""
                            }
                        end
                    end %>
                  <div class={[
                    "rounded-lg p-4 space-y-4 transition-all duration-200",
                    if(is_registration_complete,
                      do: "border-2 border-green-500 bg-green-50/30",
                      else: "border border-zinc-200"
                    )
                  ]}>
                    <div class="flex items-center justify-between mb-4">
                      <div class="flex items-center gap-3">
                        <div>
                          <h4 class="text-base font-semibold text-zinc-900">
                            Ticket <%= index + 1 %> of <%= length(
                              tickets_requiring_registration
                            ) %>
                          </h4>
                          <p class="text-xs text-zinc-600">
                            <%= ticket.ticket_tier.name %>
                          </p>
                        </div>
                        <%= if is_registration_complete do %>
                          <div class="flex-shrink-0">
                            <.icon
                              name="hero-check-circle"
                              class="w-6 h-6 text-green-600"
                            />
                          </div>
                        <% end %>
                      </div>
                    </div>

                    <% other_family_members =
                      Enum.reject(family_members, fn member ->
                        member.id == @current_user.id
                      end) %>

                    <%!-- Streamlined Dropdown for "Who is this ticket for?" --%>
                    <form phx-change="select-ticket-attendee" phx-debounce="100">
                      <input
                        type="hidden"
                        name="ticket_id"
                        value={to_string(ticket.id)}
                      />
                      <div class="mb-4">
                        <label
                          for={"ticket_#{ticket.id}_attendee_select"}
                          class="block text-sm font-medium text-zinc-700 mb-2"
                        >
                          Who is this ticket for?
                        </label>
                        <select
                          id={"ticket_#{ticket.id}_attendee_select"}
                          name={"ticket_#{ticket.id}_attendee_select"}
                          value={
                            cond do
                              is_for_me ->
                                "me"

                              has_selected_family_member ->
                                "family_#{selected_family_member.id}"

                              true ->
                                "other"
                            end
                          }
                          class="block w-full rounded-md border-zinc-300 py-2.5 pl-3 pr-10 text-sm focus:border-blue-500 focus:outline-none focus:ring-blue-500"
                        >
                          <option
                            value="me"
                            disabled={
                              me_already_selected_for_other_ticket && !is_for_me
                            }
                          >
                            Me (<%= @current_user.first_name || @current_user.email %>)
                            <%= if me_already_selected_for_other_ticket && !is_for_me do %>
                              (Already selected for another ticket)
                            <% end %>
                          </option>
                          <%= if length(other_family_members) > 0 do %>
                            <optgroup label="Family Members">
                              <%= for family_member <- other_family_members do %>
                                <option value={"family_#{family_member.id}"}>
                                  <%= family_member.first_name %> <%= family_member.last_name %>
                                </option>
                              <% end %>
                            </optgroup>
                          <% end %>
                          <option
                            value="other"
                            selected={!is_for_me && !has_selected_family_member}
                          >
                            Someone else (Enter details)
                          </option>
                        </select>
                      </div>
                    </form>

                    <%!-- Manual Entry Form (shown when "Someone else" is selected) --%>
                    <form phx-change="update-registration-field" phx-debounce="500">
                      <div
                        id={"ticket_#{ticket.id}_registration_fields"}
                        class={[
                          !is_for_me && !has_selected_family_member && "block",
                          (is_for_me || has_selected_family_member) && "hidden"
                        ]}
                      >
                        <div class="space-y-4">
                          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                            <div>
                              <label
                                for={"ticket_#{ticket.id}_first_name"}
                                class="block text-sm font-medium text-zinc-700"
                              >
                                First Name
                              </label>
                              <input
                                type="text"
                                id={"ticket_#{ticket.id}_first_name"}
                                name={"ticket_#{ticket.id}_first_name"}
                                value={form_data.first_name}
                                required={!is_for_me && !has_selected_family_member}
                                disabled={is_for_me || has_selected_family_member}
                                phx-value-ticket-id={ticket.id}
                                phx-value-field="first_name"
                                enterkeyhint="next"
                                class="mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400"
                              />
                            </div>
                            <div>
                              <label
                                for={"ticket_#{ticket.id}_last_name"}
                                class="block text-sm font-medium text-zinc-700"
                              >
                                Last Name
                              </label>
                              <input
                                type="text"
                                id={"ticket_#{ticket.id}_last_name"}
                                name={"ticket_#{ticket.id}_last_name"}
                                value={form_data.last_name}
                                required={!is_for_me && !has_selected_family_member}
                                disabled={is_for_me || has_selected_family_member}
                                phx-value-ticket-id={ticket.id}
                                phx-value-field="last_name"
                                enterkeyhint="next"
                                class="mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400"
                              />
                            </div>
                          </div>
                          <div>
                            <label
                              for={"ticket_#{ticket.id}_email"}
                              class="block text-sm font-medium text-zinc-700"
                            >
                              Email
                            </label>
                            <input
                              type="email"
                              id={"ticket_#{ticket.id}_email"}
                              name={"ticket_#{ticket.id}_email"}
                              value={form_data.email}
                              required={!is_for_me && !has_selected_family_member}
                              disabled={is_for_me || has_selected_family_member}
                              autocomplete="email"
                              enterkeyhint="done"
                              phx-value-ticket-id={ticket.id}
                              phx-value-field="email"
                              class="mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400"
                            />
                          </div>
                        </div>
                      </div>
                    </form>

                    <%!-- Summary Display (shown when "Me" or "Family Member" is selected) --%>
                    <div class={[
                      (is_for_me || has_selected_family_member) && "block",
                      !is_for_me && !has_selected_family_member && "hidden"
                    ]}>
                      <div class="bg-blue-50 border border-blue-200 rounded-lg p-3">
                        <p class="text-sm text-blue-800">
                          <strong>
                            <%= form_data.first_name %> <%= form_data.last_name %>
                          </strong>
                          <br />
                          <span class="text-blue-600"><%= form_data.email %></span>
                        </p>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
            <!-- Stripe Elements Payment Form -->
            <% all_registrations_complete =
              if Enum.any?(tickets_requiring_registration) do
                tickets_requiring_registration
                |> Enum.all?(fn ticket ->
                  tickets_for_me = @tickets_for_me || %{}

                  is_for_me =
                    Map.get(tickets_for_me, ticket.id, false) ||
                      Map.get(tickets_for_me, to_string(ticket.id), false)

                  selected_family_members = @selected_family_members || %{}

                  selected_family_member_id =
                    Map.get(selected_family_members, ticket.id) ||
                      Map.get(selected_family_members, to_string(ticket.id))

                  family_members = @family_members || []

                  selected_family_member =
                    if selected_family_member_id,
                      do:
                        Enum.find(family_members, fn u ->
                          u.id == selected_family_member_id ||
                            to_string(u.id) == to_string(selected_family_member_id)
                        end),
                      else: nil

                  has_selected_family_member = not is_nil(selected_family_member)
                  ticket_id_str = to_string(ticket.id)

                  cond do
                    is_for_me ->
                      @current_user.first_name && @current_user.first_name != "" &&
                        (@current_user.last_name && @current_user.last_name != "") &&
                        (@current_user.email && @current_user.email != "")

                    has_selected_family_member ->
                      selected_family_member.first_name &&
                        selected_family_member.first_name != "" &&
                        (selected_family_member.last_name &&
                           selected_family_member.last_name != "") &&
                        (selected_family_member.email &&
                           selected_family_member.email != "")

                    true ->
                      form_map =
                        Map.get(@ticket_details_form, ticket_id_str) ||
                          Map.get(@ticket_details_form, ticket.id) || %{}

                      first_name =
                        Map.get(form_map, :first_name) ||
                          Map.get(form_map, "first_name") || ""

                      last_name =
                        Map.get(form_map, :last_name) ||
                          Map.get(form_map, "last_name") || ""

                      email =
                        Map.get(form_map, :email) || Map.get(form_map, "email") ||
                          ""

                      first_name != "" && last_name != "" && email != "" &&
                        String.contains?(email, "@")
                  end
                end)
              else
                true
              end %>
            <div class={[
              "space-y-4 transition-opacity duration-300",
              if(all_registrations_complete,
                do: "opacity-100",
                else: "opacity-40 pointer-events-none"
              )
            ]}>
              <div class="flex items-center gap-2 mb-2">
                <span class={[
                  "flex items-center justify-center w-6 h-6 rounded-full text-sm font-semibold",
                  if(all_registrations_complete,
                    do: "bg-green-600 text-white",
                    else: "bg-blue-600 text-white"
                  )
                ]}>
                  <%= if all_registrations_complete do %>
                    <.icon name="hero-check" class="w-4 h-4" />
                  <% else %>
                    2
                  <% end %>
                </span>
                <h3 class="font-semibold text-lg">Payment Information</h3>
              </div>
              <div
                id="payment-element"
                phx-hook="StripeElements"
                phx-update="ignore"
                data-publicKey={@public_key}
                data-public-key={@public_key}
                data-client-secret={@payment_intent.client_secret}
                data-clientSecret={@payment_intent.client_secret}
                data-ticket-order-id={@ticket_order.id}
              >
                <!-- Stripe Elements will be mounted here -->
              </div>
              <div id="payment-message" class="hidden text-sm"></div>
            </div>
            <!-- Checkout Zone: Payment Action Area -->
            <div class="mt-8 bg-zinc-50 -mx-6 px-6 py-6 border-t-4 border-blue-600 shadow-lg">
              <div class="max-w-md mx-auto space-y-4">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-zinc-600">Amount due:</span>
                  <span class="text-2xl font-bold text-zinc-900">
                    <%= calculate_total_price(
                      @selected_tickets,
                      @event.id,
                      @ticket_tiers,
                      @reservations_by_tier,
                      @current_user,
                      @user_reservations
                    ) %>
                  </span>
                </div>
                <div class="flex flex-col sm:flex-row gap-3">
                  <.button
                    class="sm:flex-[2] w-full sm:w-auto py-4 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-bold shadow-md active:scale-[0.98] transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                    id="submit-payment"
                    disabled={!all_registrations_complete}
                  >
                    Confirm and Pay <%= calculate_total_price(
                      @selected_tickets,
                      @event.id,
                      @ticket_tiers,
                      @reservations_by_tier,
                      @current_user,
                      @user_reservations
                    ) %>
                  </.button>
                  <.button
                    class="sm:flex-1 w-full sm:w-auto bg-transparent text-zinc-500 hover:text-zinc-700 py-4 rounded-lg font-medium transition-colors"
                    phx-click="close-payment-modal"
                  >
                    Cancel
                  </.button>
                </div>
                <p class="text-center text-xs text-zinc-400 flex items-center justify-center gap-1">
                  <.icon name="hero-lock-closed" class="w-3 h-3" />
                  Encrypted SSL Secure Payment
                </p>
              </div>
            </div>
          </div>
          <!-- Right Panel: Order Summary (Sticky on large screens) -->
          <div class="lg:w-1/3 space-y-4 lg:sticky lg:top-6 lg:self-start lg:max-h-[calc(100vh-6rem)] lg:overflow-y-auto">
            <div class="space-y-4">
              <div class="w-full hidden lg:block max-h-32 overflow-hidden rounded-lg">
                <.live_component
                  id={"event-checkout-#{@event.id}"}
                  module={YscWeb.Components.Image}
                  image_id={@event.image_id}
                />
              </div>

              <div>
                <h2 class="text-lg font-semibold mb-6"><%= @event.title %></h2>
                <h3 class="font-semibold mb-2">Order Summary</h3>
              </div>

              <div class="bg-zinc-50 rounded-lg p-6 space-y-4">
                <%= if has_any_tickets_selected?(@selected_tickets) do %>
                  <% pricing =
                    calculate_pricing_with_discounts(
                      @selected_tickets,
                      @event.id,
                      @ticket_tiers,
                      @reservations_by_tier,
                      @current_user,
                      @user_reservations
                    ) %>
                  <%= for breakdown <- pricing.tier_breakdowns do %>
                    <div class="space-y-1">
                      <div class="flex justify-between text-base">
                        <span>
                          <%= breakdown.tier_name %>
                          <%= if breakdown.quantity > 1 do %>
                            × <%= breakdown.quantity %>
                          <% end %>
                        </span>
                        <span class="font-medium">
                          <%= if Money.positive?(breakdown.original_price) && Money.positive?(breakdown.discount_amount) do %>
                            <span class="text-zinc-400 line-through mr-2">
                              <%= format_price(breakdown.original_price) %>
                            </span>
                          <% end %>
                          <%= format_price(breakdown.final_price) %>
                        </span>
                      </div>
                      <%= if breakdown.discount_percentage && breakdown.discount_percentage > 0 do %>
                        <div class="flex justify-between text-sm text-green-600">
                          <span>
                            Reserved discount (<%= breakdown.discount_percentage
                            |> Float.round(2) %>%)
                          </span>
                          <span class="font-medium">
                            -<%= format_price(breakdown.discount_amount) %>
                          </span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                <% else %>
                  <div class="text-center py-8">
                    <div class="text-zinc-400 mb-2">
                      <.icon name="hero-shopping-cart" class="w-8 h-8 mx-auto" />
                    </div>
                    <p class="text-zinc-500 text-sm">No tickets selected</p>
                  </div>
                <% end %>

                <%= if has_any_tickets_selected?(@selected_tickets) do %>
                  <% pricing =
                    calculate_pricing_with_discounts(
                      @selected_tickets,
                      @event.id,
                      @ticket_tiers,
                      @reservations_by_tier,
                      @current_user,
                      @user_reservations
                    ) %>
                  <div class="border-t border-zinc-200 pt-4 space-y-2">
                    <%= if Money.positive?(pricing.discount_amount) do %>
                      <div class="flex justify-between text-sm text-zinc-600">
                        <span>Subtotal:</span>
                        <span><%= format_price(pricing.subtotal) %></span>
                      </div>
                      <div class="flex justify-between text-sm text-green-600 font-medium">
                        <span>Discount:</span>
                        <span>-<%= format_price(pricing.discount_amount) %></span>
                      </div>
                    <% end %>
                    <div class="flex justify-between font-semibold text-lg">
                      <span>Total:</span>
                      <span>
                        <%= format_price(pricing.total) %>
                      </span>
                    </div>
                  </div>
                <% else %>
                  <div class="border-t border-zinc-200 pt-4">
                    <div class="flex justify-between font-semibold text-lg">
                      <span>Total:</span>
                      <span>
                        <%= calculate_total_price(
                          @selected_tickets,
                          @event.id,
                          @ticket_tiers,
                          @reservations_by_tier,
                          @current_user,
                          @user_reservations
                        ) %>
                      </span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </.modal>
    <!-- Registration Modal -->
    <.modal
      :if={@show_registration_modal}
      id="registration-modal"
      show
      on_cancel={JS.push("close-registration-modal")}
      max_width="max-w-4xl"
    >
      <div class="flex flex-col space-y-6">
        <div class="text-center">
          <h2 class="text-2xl font-semibold text-zinc-900 mb-2">
            Ticket Registration
          </h2>
          <p class="text-zinc-600">
            Please provide details for each ticket that requires registration.
          </p>
        </div>

        <form phx-submit="submit-registration" class="space-y-6">
          <%= for ticket <- @tickets_requiring_registration do %>
            <% ticket_id_str = to_string(ticket.id)
            ticket_detail = Ysc.Events.get_registration_for_ticket(ticket.id)

            ticket_detail_data =
              Map.get(@ticket_details_form, ticket_id_str, %{}) ||
                Map.get(@ticket_details_form, ticket.id, %{
                  first_name: "",
                  last_name: "",
                  email: ""
                })

            form_values = %{
              first_name:
                Map.get(
                  ticket_detail_data,
                  :first_name,
                  (ticket_detail && ticket_detail.first_name) || ""
                ),
              last_name:
                Map.get(
                  ticket_detail_data,
                  :last_name,
                  (ticket_detail && ticket_detail.last_name) || ""
                ),
              email:
                Map.get(
                  ticket_detail_data,
                  :email,
                  (ticket_detail && ticket_detail.email) || ""
                )
            } %>
            <div class="border border-zinc-200 rounded-lg p-6 space-y-4">
              <div class="flex items-center justify-between mb-4">
                <div>
                  <h3 class="text-lg font-semibold text-zinc-900">
                    Ticket #<%= ticket.reference_id %>
                  </h3>
                  <p class="text-sm text-zinc-600">
                    <%= ticket.ticket_tier.name %>
                  </p>
                </div>
              </div>

              <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <div>
                  <.input
                    type="text"
                    label="First Name"
                    name={"ticket_#{ticket.id}_first_name"}
                    value={form_values.first_name}
                    required
                    phx-change="update-registration-field"
                    phx-debounce="500"
                    phx-value-ticket-id={ticket.id}
                    phx-value-field="first_name"
                  />
                </div>
                <div>
                  <.input
                    type="text"
                    label="Last Name"
                    name={"ticket_#{ticket.id}_last_name"}
                    value={form_values.last_name}
                    required
                    phx-change="update-registration-field"
                    phx-debounce="500"
                    phx-value-ticket-id={ticket.id}
                    phx-value-field="last_name"
                  />
                </div>
              </div>
              <div>
                <.input
                  type="email"
                  label="Email"
                  name={"ticket_#{ticket.id}_email"}
                  value={form_values.email}
                  required
                  phx-change="update-registration-field"
                  phx-debounce="500"
                  phx-value-ticket-id={ticket.id}
                  phx-value-field="email"
                />
              </div>
            </div>
          <% end %>

          <div class="flex space-x-4 pt-4">
            <.button
              type="button"
              class="flex-1 bg-zinc-200 text-zinc-800 hover:bg-zinc-300"
              phx-click="close-registration-modal"
            >
              Cancel
            </.button>
            <.button type="submit" phx-disable-with="Processing..." class="flex-1">
              <%= if Money.zero?(@ticket_order.total_amount) do %>
                Continue to Confirmation
              <% else %>
                Continue to Payment
              <% end %>
            </.button>
          </div>
        </form>
      </div>
    </.modal>
    <!-- Free Ticket Confirmation Modal -->
    <.modal
      :if={@show_free_ticket_confirmation}
      id="free-ticket-confirmation-modal"
      show
      on_cancel={JS.push("close-free-ticket-confirmation")}
      max_width="max-w-4xl"
    >
      <div class="flex flex-col space-y-6">
        <div class="text-center">
          <div class="text-green-500 mb-4">
            <.icon name="hero-ticket" class="w-16 h-16 mx-auto" />
          </div>
          <h2 class="text-2xl font-semibold text-zinc-900 mb-2">
            Confirm Your Free Tickets
          </h2>
          <p class="text-zinc-600 mb-6">
            You've selected free tickets for this event. No payment is required.
          </p>
        </div>

        <%!-- Compact Order Summary (receipt-style) --%>
        <div class="w-full bg-zinc-50 rounded-lg p-4 border border-zinc-200">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-semibold text-zinc-700 uppercase tracking-wide">
              Order Summary
            </h3>
            <p class="text-sm font-bold text-green-600">Free</p>
          </div>
          <div class="space-y-2 text-sm">
            <%= for {tier_id, quantity} <- @selected_tickets do %>
              <% tier = Enum.find(@event.ticket_tiers, &(&1.id == tier_id)) %>
              <div class="flex justify-between items-center text-zinc-600">
                <span><%= tier.name %> × <%= quantity %></span>
                <span class="text-zinc-500">Free</span>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Registration Section - Show if tickets require registration --%>
        <% tickets_requiring_registration =
          get_tickets_requiring_registration(@ticket_order.tickets || []) %>
        <%= if Enum.any?(tickets_requiring_registration) do %>
          <div class="space-y-3 border-t border-zinc-200 pt-6">
            <h3 class="font-semibold text-lg mb-1">Ticket Registration</h3>
            <p class="text-sm text-zinc-600 mb-4">
              Please provide details for each ticket that requires registration.
            </p>

            <%= for {ticket, index} <- Enum.with_index(tickets_requiring_registration) do %>
              <% _total_tickets = length(tickets_requiring_registration) %>
              <% tickets_for_me = @tickets_for_me || %{} %>
              <% is_for_me =
                Map.get(tickets_for_me, ticket.id, false) ||
                  Map.get(tickets_for_me, to_string(ticket.id), false) %>

              <%!-- Check if "Me" is already selected for any other ticket --%>
              <% me_already_selected_for_other_ticket =
                tickets_requiring_registration
                |> Enum.any?(fn other_ticket ->
                  other_ticket.id != ticket.id &&
                    (Map.get(tickets_for_me, other_ticket.id, false) ||
                       Map.get(tickets_for_me, to_string(other_ticket.id), false))
                end) %>

              <% selected_family_members = @selected_family_members || %{} %>
              <% selected_family_member_id =
                Map.get(selected_family_members, ticket.id) ||
                  Map.get(selected_family_members, to_string(ticket.id)) %>
              <% family_members = @family_members || [] %>
              <% selected_family_member =
                if selected_family_member_id,
                  do:
                    Enum.find(family_members, fn u ->
                      u.id == selected_family_member_id ||
                        to_string(u.id) == to_string(selected_family_member_id)
                    end),
                  else: nil %>
              <% has_selected_family_member = not is_nil(selected_family_member) %>
              <% ticket_id_str = to_string(ticket.id)

              form_data =
                cond do
                  is_for_me ->
                    # Auto-fill with current user's details
                    %{
                      first_name: @current_user.first_name || "",
                      last_name: @current_user.last_name || "",
                      email: @current_user.email || ""
                    }

                  has_selected_family_member ->
                    # Use selected family member's details
                    %{
                      first_name: selected_family_member.first_name || "",
                      last_name: selected_family_member.last_name || "",
                      email: selected_family_member.email || ""
                    }

                  true ->
                    # Use form data from @ticket_details_form (in-memory state only)
                    # Don't query database on every render - form data is managed in memory
                    case Map.get(@ticket_details_form, ticket_id_str) ||
                           Map.get(@ticket_details_form, ticket.id) do
                      nil ->
                        # No form data yet, use empty values
                        %{
                          first_name: "",
                          last_name: "",
                          email: ""
                        }

                      form_map ->
                        # Use form data, but ensure all fields exist (fill missing ones with empty string)
                        %{
                          first_name:
                            Map.get(form_map, :first_name) ||
                              Map.get(form_map, "first_name") || "",
                          last_name:
                            Map.get(form_map, :last_name) ||
                              Map.get(form_map, "last_name") || "",
                          email:
                            Map.get(form_map, :email) || Map.get(form_map, "email") ||
                              ""
                        }
                    end
                end %>

              <div class="border border-zinc-200 rounded-lg p-4 space-y-4">
                <div class="flex items-center justify-between mb-2">
                  <div>
                    <h4 class="text-sm font-semibold text-zinc-900">
                      Ticket <%= index + 1 %> of <%= length(
                        tickets_requiring_registration
                      ) %>
                    </h4>
                    <p class="text-xs text-zinc-600">
                      <%= ticket.ticket_tier.name %>
                    </p>
                  </div>
                </div>

                <% other_family_members =
                  Enum.reject(family_members, fn member ->
                    member.id == @current_user.id
                  end) %>

                <%!-- Streamlined Dropdown for "Who is this ticket for?" --%>
                <form phx-change="select-ticket-attendee" phx-debounce="100">
                  <input
                    type="hidden"
                    name="ticket_id"
                    value={to_string(ticket.id)}
                  />
                  <div class="mb-4">
                    <label
                      for={"ticket_#{ticket.id}_attendee_select"}
                      class="block text-sm font-medium text-zinc-700 mb-2"
                    >
                      Who is this ticket for?
                    </label>
                    <select
                      id={"ticket_#{ticket.id}_attendee_select"}
                      name={"ticket_#{ticket.id}_attendee_select"}
                      value={
                        cond do
                          is_for_me ->
                            "me"

                          has_selected_family_member ->
                            "family_#{selected_family_member.id}"

                          true ->
                            "other"
                        end
                      }
                      class="block w-full rounded-md border-zinc-300 py-2.5 pl-3 pr-10 text-sm focus:border-blue-500 focus:outline-none focus:ring-blue-500"
                    >
                      <option
                        value="me"
                        disabled={
                          me_already_selected_for_other_ticket && !is_for_me
                        }
                      >
                        Me (<%= @current_user.first_name || @current_user.email %>)
                        <%= if me_already_selected_for_other_ticket && !is_for_me do %>
                          (Already selected for another ticket)
                        <% end %>
                      </option>
                      <%= if length(other_family_members) > 0 do %>
                        <optgroup label="Family Members">
                          <%= for family_member <- other_family_members do %>
                            <option value={"family_#{family_member.id}"}>
                              <%= family_member.first_name %> <%= family_member.last_name %>
                            </option>
                          <% end %>
                        </optgroup>
                      <% end %>
                      <option
                        value="other"
                        selected={!is_for_me && !has_selected_family_member}
                      >
                        Someone else (Enter details)
                      </option>
                    </select>
                  </div>
                </form>

                <%!-- Manual Entry Form (shown when "Someone else" is selected) --%>
                <form phx-change="update-registration-field" phx-debounce="500">
                  <div
                    id={"ticket_#{ticket.id}_registration_fields"}
                    class={[
                      !is_for_me && !has_selected_family_member && "block",
                      (is_for_me || has_selected_family_member) && "hidden"
                    ]}
                  >
                    <div class="space-y-4">
                      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                        <div>
                          <label
                            for={"ticket_#{ticket.id}_first_name"}
                            class="block text-sm font-medium text-zinc-700"
                          >
                            First Name
                          </label>
                          <input
                            type="text"
                            id={"ticket_#{ticket.id}_first_name"}
                            name={"ticket_#{ticket.id}_first_name"}
                            value={form_data.first_name}
                            required={!is_for_me && !has_selected_family_member}
                            disabled={is_for_me || has_selected_family_member}
                            phx-value-ticket-id={ticket.id}
                            phx-value-field="first_name"
                            class="mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400"
                          />
                        </div>
                        <div>
                          <label
                            for={"ticket_#{ticket.id}_last_name"}
                            class="block text-sm font-medium text-zinc-700"
                          >
                            Last Name
                          </label>
                          <input
                            type="text"
                            id={"ticket_#{ticket.id}_last_name"}
                            name={"ticket_#{ticket.id}_last_name"}
                            value={form_data.last_name}
                            required={!is_for_me && !has_selected_family_member}
                            disabled={is_for_me || has_selected_family_member}
                            phx-value-ticket-id={ticket.id}
                            phx-value-field="last_name"
                            class="mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400"
                          />
                        </div>
                      </div>
                      <div>
                        <label
                          for={"ticket_#{ticket.id}_email"}
                          class="block text-sm font-medium text-zinc-700"
                        >
                          Email
                        </label>
                        <input
                          type="email"
                          id={"ticket_#{ticket.id}_email"}
                          name={"ticket_#{ticket.id}_email"}
                          value={form_data.email}
                          required={!is_for_me && !has_selected_family_member}
                          disabled={is_for_me || has_selected_family_member}
                          autocomplete="email"
                          phx-value-ticket-id={ticket.id}
                          phx-value-field="email"
                          class="mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400"
                        />
                      </div>
                    </div>
                  </div>
                </form>

                <%!-- Summary Display (shown when "Me" or "Family Member" is selected) --%>
                <div class={[
                  (is_for_me || has_selected_family_member) && "block",
                  !is_for_me && !has_selected_family_member && "hidden"
                ]}>
                  <div class="bg-blue-50 border border-blue-200 rounded-lg p-3">
                    <p class="text-sm text-blue-800">
                      <strong>
                        <%= form_data.first_name %> <%= form_data.last_name %>
                      </strong>
                      <br />
                      <span class="text-blue-600"><%= form_data.email %></span>
                    </p>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
        <!-- Action Buttons -->
        <div class="flex space-x-4 pt-4">
          <.button
            class="flex-1 bg-zinc-200 text-zinc-800 hover:bg-zinc-300"
            phx-click="close-free-ticket-confirmation"
          >
            Cancel
          </.button>
          <.button
            phx-click="confirm-free-tickets"
            phx-disable-with="Confirming..."
            class="flex-1 bg-green-600 hover:bg-green-700"
          >
            Confirm Free Tickets
          </.button>
        </div>
      </div>
    </.modal>
    <!-- Order Completion Modal -->
    <.modal
      :if={@show_order_completion}
      id="order-completion-modal"
      show
      on_cancel={JS.push("close-order-completion")}
      max_width="max-w-2xl"
    >
      <div class="flex flex-col items-center justify-center py-12 space-y-6">
        <div class="text-center">
          <div class="text-green-500 mb-4">
            <.icon name="hero-check-circle" class="w-16 h-16 mx-auto" />
          </div>
          <h2 class="text-2xl font-semibold text-zinc-900 mb-2">
            Order Confirmed!
          </h2>
        </div>
        <!-- Order Details -->
        <div class="w-full max-w-md bg-zinc-50 rounded-lg p-6">
          <h3 class="text-lg font-semibold text-zinc-900 mb-4">Order Details</h3>
          <div class="space-y-3">
            <div class="flex justify-between">
              <span class="text-zinc-600">Order ID:</span>
              <span class="font-medium"><%= @ticket_order.reference_id %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">Event:</span>
              <span class="font-medium"><%= @event.title %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">Date:</span>
              <span class="font-medium">
                <%= Calendar.strftime(@event.start_date, "%B %d, %Y") %>
              </span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">Time:</span>
              <span class="font-medium">
                <%= Calendar.strftime(@event.start_time, "%I:%M %p") %>
              </span>
            </div>
          </div>
        </div>
        <!-- Tickets List -->
        <div class="w-full max-w-md bg-white border rounded-lg p-6">
          <h3 class="text-lg font-semibold text-zinc-900 mb-4">Your Tickets</h3>
          <div class="space-y-3">
            <%= for ticket <- @ticket_order.tickets do %>
              <% ticket_discount_amount =
                ticket.discount_amount || Money.new(0, :USD) %>
              <% has_discount = Money.positive?(ticket_discount_amount) %>
              <div class="space-y-1">
                <div class="flex justify-between items-center p-3 bg-zinc-50 rounded">
                  <div>
                    <p class="font-medium text-zinc-900">
                      <%= ticket.ticket_tier.name %>
                    </p>
                    <p class="text-sm text-zinc-500">
                      Ticket #<%= ticket.reference_id %>
                    </p>
                  </div>
                  <div class="text-right">
                    <p class="font-semibold text-zinc-900">
                      <%= cond do %>
                        <% ticket.ticket_tier.type == "donation" || ticket.ticket_tier.type == :donation -> %>
                          <%= get_donation_amount_for_single_ticket(ticket) %>
                        <% ticket.ticket_tier.price == nil -> %>
                          Free
                        <% Money.zero?(ticket.ticket_tier.price) -> %>
                          Free
                        <% true -> %>
                          <%= if has_discount do %>
                            <span class="text-zinc-400 line-through mr-2 text-sm">
                              <%= case Money.to_string(ticket.ticket_tier.price) do
                                {:ok, amount} -> amount
                                {:error, _} -> "Error"
                              end %>
                            </span>
                            <%= case Money.sub(
                                       ticket.ticket_tier.price,
                                       ticket_discount_amount
                                     ) do
                              {:ok, discounted} ->
                                case Money.to_string(discounted) do
                                  {:ok, amount} -> amount
                                  {:error, _} -> "Error"
                                end

                              _ ->
                                case Money.to_string(ticket.ticket_tier.price) do
                                  {:ok, amount} -> amount
                                  {:error, _} -> "Error"
                                end
                            end %>
                          <% else %>
                            <%= case Money.to_string(ticket.ticket_tier.price) do
                              {:ok, amount} -> amount
                              {:error, _} -> "Error"
                            end %>
                          <% end %>
                      <% end %>
                    </p>
                  </div>
                </div>
                <%= if has_discount do %>
                  <% discount_percentage =
                    if ticket.ticket_tier.price &&
                         Money.positive?(ticket.ticket_tier.price) do
                      case Money.div(
                             ticket_discount_amount,
                             ticket.ticket_tier.price
                           ) do
                        {:ok, ratio} ->
                          Decimal.mult(ratio.amount, Decimal.new(100))
                          |> Decimal.to_float()
                          |> Float.round(2)

                        _ ->
                          nil
                      end
                    else
                      nil
                    end %>
                  <div class="flex justify-between text-xs text-green-600 px-3">
                    <span>
                      Reserved discount<%= if discount_percentage do %>
                        (<%= discount_percentage %>%)
                      <% end %>
                    </span>
                    <span class="font-medium">
                      -<%= case Money.to_string(ticket_discount_amount) do
                        {:ok, amount} -> amount
                        {:error, _} -> "$0.00"
                      end %>
                    </span>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
          <div class="border-t pt-3 mt-4 space-y-2">
            <% total_discount = @ticket_order.discount_amount || Money.new(0, :USD) %>
            <%= if Money.positive?(total_discount) do %>
              <% gross_total =
                case Money.add(@ticket_order.total_amount, total_discount) do
                  {:ok, total} -> total
                  _ -> @ticket_order.total_amount
                end %>
              <div class="flex justify-between text-sm text-zinc-600">
                <span>Subtotal:</span>
                <span>
                  <%= case Money.to_string(gross_total) do
                    {:ok, amount} -> amount
                    {:error, _} -> "$0.00"
                  end %>
                </span>
              </div>
              <div class="flex justify-between text-sm text-green-600 font-medium">
                <span>Discount:</span>
                <span>
                  -<%= case Money.to_string(total_discount) do
                    {:ok, amount} -> amount
                    {:error, _} -> "$0.00"
                  end %>
                </span>
              </div>
            <% end %>
            <div class="flex justify-between items-center">
              <p class="text-lg font-semibold text-zinc-900">Total</p>
              <p class="text-lg font-bold text-green-600">
                <%= if Money.zero?(@ticket_order.total_amount) do %>
                  Free
                <% else %>
                  <%= case Money.to_string(@ticket_order.total_amount) do
                    {:ok, amount} -> amount
                    {:error, _} -> "Error"
                  end %>
                <% end %>
              </p>
            </div>
          </div>
        </div>
        <!-- Email Notice -->
        <div class="w-full max-w-md bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div class="flex items-start">
            <.icon name="hero-envelope" class="w-5 h-5 text-blue-500 mt-0.5 mr-3" />
            <div>
              <p class="text-sm text-blue-800">
                <strong>Confirmation Email Sent</strong>
                <br /> We've sent a detailed confirmation email to
                <strong><%= @current_user.email %></strong>
                with your ticket details.
              </p>
            </div>
          </div>
        </div>
        <!-- Action Buttons -->
        <div class="w-full max-w-md space-y-3">
          <.button
            phx-click="close-order-completion"
            class="w-full bg-green-600 hover:bg-green-700"
          >
            Continue
          </.button>
          <div class="text-center">
            <p class="text-sm text-zinc-500 mb-2">
              Want to bookmark this confirmation?
            </p>
            <.link
              navigate={~p"/orders/#{@ticket_order.id}/confirmation"}
              class="text-blue-600 hover:text-blue-500 text-sm font-medium"
            >
              View Full Order Confirmation →
            </.link>
          </div>
        </div>
      </div>
    </.modal>
    <!-- Attendees Modal -->
    <.modal
      :if={@show_attendees_modal}
      id="attendees-modal"
      show
      on_cancel={JS.push("close-attendees-modal")}
      max_width="max-w-2xl"
    >
      <div class="flex flex-col space-y-6">
        <div class="text-center">
          <h2 class="text-2xl font-semibold text-zinc-900 mb-2">Who's Going</h2>
          <p class="text-zinc-600">
            <%= if @attendees_count do %>
              <%= @attendees_count %> <%= if @attendees_count == 1,
                do: "person",
                else: "people" %> <%= if @attendees_count ==
                                           1,
                                         do: "is",
                                         else: "are" %> attending this event
            <% else %>
              People attending this event
            <% end %>
          </p>
        </div>

        <div class="space-y-3 max-h-[60vh] overflow-y-auto">
          <%= if @attendees_list && length(@attendees_list) > 0 do %>
            <%= for attendee <- @attendees_list do %>
              <% attendee_name =
                "#{attendee.first_name || ""} #{attendee.last_name || ""}"
                |> String.trim() %>
              <% display_name =
                if attendee_name != "",
                  do: attendee_name,
                  else: attendee.email || "Unknown" %>
              <% ticket_count = Map.get(@ticket_counts_per_user, attendee.id, 0) %>
              <div class="flex items-center gap-3 p-3 bg-zinc-50 rounded-lg border border-zinc-200">
                <.user_avatar_image
                  email={attendee.email}
                  user_id={attendee.id}
                  country={Map.get(attendee, :most_connected_country, "SE")}
                  class="h-10 w-10 rounded-full flex-shrink-0"
                />
                <div class="flex-1 min-w-0">
                  <p class="font-medium text-zinc-900">
                    <%= display_name %>
                    <span class="text-zinc-500 font-normal">
                      (<%= ticket_count %> <%= if ticket_count == 1,
                        do: "ticket",
                        else: "tickets" %>)
                    </span>
                  </p>
                  <p
                    :if={attendee.email && attendee_name != ""}
                    class="text-sm text-zinc-500 truncate"
                  >
                    <%= attendee.email %>
                  </p>
                </div>
              </div>
            <% end %>
          <% else %>
            <div class="text-center py-8">
              <p class="text-zinc-500">No attendees found.</p>
            </div>
          <% end %>
        </div>

        <div class="flex justify-end pt-4">
          <.button
            class="bg-zinc-200 text-zinc-800 hover:bg-zinc-300"
            phx-click="close-attendees-modal"
          >
            Close
          </.button>
        </div>
      </div>
    </.modal>
    """
  end

  @impl true
  def mount(%{"id" => event_id}, _session, socket) do
    # Fetch only essential event data for initial static render (SEO & fast first paint)
    case Repo.get(Event, event_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Event not found")
         |> redirect(to: ~p"/events")}

      event ->
        # For disconnected mount: minimal data for fast static HTML
        # For connected mount: full data loading via assign_async
        socket = mount_minimal_assigns(socket, event, event_id)

        if connected?(socket) do
          # Subscribe to real-time updates only when connected
          Events.subscribe()
          Agendas.subscribe(event_id)
          Ysc.Tickets.subscribe_event(event_id)

          if socket.assigns.current_user != nil do
            require Logger

            Logger.info("Subscribing to ticket events for user",
              user_id: socket.assigns.current_user.id,
              event_id: event_id,
              topic: "tickets:user:#{socket.assigns.current_user.id}"
            )

            Ysc.Tickets.subscribe(socket.assigns.current_user.id)
          end

          # Load all heavy data asynchronously after connection
          {:ok, load_async_data(socket, event_id)}
        else
          {:ok, socket}
        end
    end
  end

  # Minimal assigns for fast initial static render (SEO-friendly)
  defp mount_minimal_assigns(socket, event, _event_id) do
    # Preload only ticket_tiers for pricing display (single query)
    event = Repo.preload(event, :ticket_tiers)

    # Convert preloaded tiers to map format expected by pricing functions
    # Add sold_tickets_count: 0 as placeholder (will be updated after async load)
    ticket_tiers_as_maps =
      Enum.map(event.ticket_tiers, fn tier ->
        %{
          id: tier.id,
          name: tier.name,
          description: tier.description,
          type: tier.type,
          price: tier.price,
          quantity: tier.quantity,
          requires_registration: tier.requires_registration,
          start_date: tier.start_date,
          end_date: tier.end_date,
          event_id: tier.event_id,
          lock_version: tier.lock_version,
          inserted_at: tier.inserted_at,
          updated_at: tier.updated_at,
          sold_tickets_count: 0
        }
      end)

    event_with_pricing =
      add_pricing_info_from_tiers(event, ticket_tiers_as_maps)

    has_ticket_tiers = event.ticket_tiers != []

    # Check if we're on the tickets route (live_action == :tickets)
    show_ticket_modal = socket.assigns.live_action == :tickets

    socket
    |> assign(:page_title, event.title)
    |> assign(:event, event_with_pricing)
    # Async data - will be populated after connection
    |> assign(:agendas, [])
    |> assign(:active_agenda, nil)
    |> assign(:user_tickets, [])
    |> assign(:all_tickets_by_order, %{})
    |> assign(:ticket_tiers, ticket_tiers_as_maps)
    # Availability data - loading state until async completes
    |> assign(:availability_data, nil)
    |> assign(:event_at_capacity, false)
    |> assign(:event_selling_fast, false)
    |> assign(:available_capacity, :unlimited)
    |> assign(:sold_percentage, nil)
    |> assign(:has_ticket_tiers, has_ticket_tiers)
    # Attendees - will be loaded async if user has membership
    |> assign(:attendees_count, nil)
    |> assign(:attendees_list, nil)
    |> assign(:ticket_counts_per_user, %{})
    # UI state
    |> assign(:show_ticket_modal, show_ticket_modal)
    |> assign(:show_payment_modal, false)
    |> assign(:show_free_ticket_confirmation, false)
    |> assign(:show_order_completion, false)
    |> assign(:payment_intent, nil)
    |> assign(:public_key, Application.get_env(:stripity_stripe, :public_key))
    |> assign(:ticket_order, nil)
    |> assign(:selected_tickets, %{})
    |> assign(:checkout_expired, false)
    |> assign(:show_registration_modal, false)
    |> assign(:ticket_details_form, %{})
    |> assign(:tickets_for_me, %{})
    |> assign(:selected_family_members, %{})
    |> assign(:show_attendees_modal, false)
    |> assign(:load_radar, true)
    |> assign(:load_stripe, true)
    |> assign(:load_calendar, true)
    |> assign(:payment_redirect_in_progress, false)
    # Reservations - will be loaded async
    |> assign(:user_reservations, [])
    |> assign(:reservations_by_tier, %{})
    # Track async loading state
    |> assign(:async_data_loaded, false)
  end

  # Load expensive data asynchronously after WebSocket connection
  defp load_async_data(socket, event_id) do
    current_user = socket.assigns.current_user
    active_membership? = socket.assigns.active_membership?
    # Pass the event we already have to avoid re-fetching it
    event = socket.assigns.event

    socket
    |> start_async(:load_event_data, fn ->
      load_event_data_async(event, event_id, current_user, active_membership?)
    end)
  end

  # Background task to load all event data in parallel
  # Note: event is passed from socket.assigns to avoid re-fetching it
  defp load_event_data_async(event, event_id, current_user, active_membership?) do
    # Run queries in parallel using Task.async_stream
    # Note: We removed check_availability_with_lock as it's expensive (runs transaction with locks
    # and re-fetches event/ticket_tiers). Instead, we compute availability from ticket_tiers data.
    tasks = [
      {:agendas, fn -> Agendas.list_agendas_for_event(event_id) end},
      {:ticket_tiers, fn -> Events.list_ticket_tiers_for_event(event_id) end},
      {:selling_fast, fn -> Events.event_selling_fast?(event_id) end},
      {:user_tickets, fn -> load_user_tickets(current_user, event_id) end},
      {:attendees,
       fn -> load_attendees(active_membership?, current_user, event_id) end},
      {:user_reservations,
       fn -> load_user_reservations(current_user, event_id) end}
    ]

    results =
      tasks
      |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
        timeout: :infinity
      )
      |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
        Map.put(acc, key, value)
      end)

    # Compute availability from ticket_tiers data (avoids expensive locking transaction)
    # list_ticket_tiers_for_event already includes sold_tickets_count via LEFT JOIN
    ticket_tiers = Map.get(results, :ticket_tiers, [])
    availability = compute_availability_from_tiers(event, ticket_tiers)

    Map.put(results, :availability, availability)
  end

  # Compute availability data from ticket_tiers without expensive database transaction
  # This reuses the sold_tickets_count from list_ticket_tiers_for_event query
  defp compute_availability_from_tiers(event, ticket_tiers) do
    # Calculate event-level capacity info
    # Count only non-donation tickets (donations don't count toward capacity)
    total_sold =
      ticket_tiers
      |> Enum.reject(fn tier ->
        tier_type = tier.type
        tier_type == :donation or tier_type == "donation"
      end)
      |> Enum.reduce(0, fn tier, acc -> acc + (tier.sold_tickets_count || 0) end)

    event_capacity =
      case event.max_attendees do
        nil ->
          %{
            max_attendees: nil,
            current_attendees: total_sold,
            available: :unlimited,
            at_capacity: false
          }

        max_attendees ->
          available = max(0, max_attendees - total_sold)

          %{
            max_attendees: max_attendees,
            current_attendees: total_sold,
            available: available,
            at_capacity: total_sold >= max_attendees
          }
      end

    # Calculate per-tier availability
    tier_availability =
      Enum.map(ticket_tiers, fn tier ->
        sold = tier.sold_tickets_count || 0
        total_qty = tier.quantity

        available =
          if total_qty == nil or total_qty == 0 do
            :unlimited
          else
            max(0, total_qty - sold)
          end

        on_sale = tier_on_sale?(tier)

        %{
          tier_id: tier.id,
          name: tier.name,
          total_quantity: total_qty,
          available: available,
          sold: sold,
          on_sale: on_sale,
          start_date: tier.start_date,
          end_date: tier.end_date
        }
      end)

    %{
      event_capacity: event_capacity,
      tiers: tier_availability
    }
  end

  defp load_user_tickets(nil, _event_id), do: {[], %{}}

  defp load_user_tickets(current_user, event_id) do
    import Ecto.Query
    alias Ysc.Events.Ticket

    confirmed_tickets =
      Ysc.Tickets.list_user_tickets_for_event(current_user.id, event_id)

    order_ids =
      confirmed_tickets
      |> Enum.filter(&(&1.ticket_order_id != nil))
      |> Enum.map(& &1.ticket_order_id)
      |> Enum.uniq()

    all_tickets_by_order =
      if Enum.empty?(order_ids) do
        %{}
      else
        Ticket
        |> where([t], t.ticket_order_id in ^order_ids)
        |> preload([:ticket_tier, :ticket_order])
        |> Repo.all()
        |> Enum.group_by(& &1.ticket_order_id)
      end

    {confirmed_tickets, all_tickets_by_order}
  end

  defp load_user_reservations(nil, _event_id), do: []

  defp load_user_reservations(current_user, event_id) do
    Events.list_ticket_reservations_for_user(current_user.id, event_id)
  end

  defp load_attendees(false, _current_user, _event_id), do: {nil, nil, %{}}

  defp load_attendees(true, current_user, event_id) do
    ticket_count = Events.count_tickets_sold_excluding_donations(event_id)

    if ticket_count >= 5 do
      attendees = Events.list_unique_attendees_for_event(event_id)

      filtered_attendees =
        if current_user do
          Enum.reject(attendees, fn attendee ->
            attendee.id == current_user.id
          end)
        else
          attendees
        end

      ticket_counts = Events.get_ticket_counts_per_user(event_id)
      {ticket_count, filtered_attendees, ticket_counts}
    else
      {nil, nil, %{}}
    end
  end

  @impl true
  def handle_async(:load_event_data, {:ok, results}, socket) do
    event = socket.assigns.event

    # Extract results
    agendas = Map.get(results, :agendas, [])
    ticket_tiers_with_counts = Map.get(results, :ticket_tiers, [])
    availability_data = Map.get(results, :availability, nil)
    event_selling_fast = Map.get(results, :selling_fast, false)

    {user_tickets, all_tickets_by_order} =
      Map.get(results, :user_tickets, {[], %{}})

    {attendees_count, attendees_list, ticket_counts_per_user} =
      Map.get(results, :attendees, {nil, nil, %{}})

    user_reservations = Map.get(results, :user_reservations, [])

    # Build a map of tier_id => reserved_quantity for quick lookup
    reservations_by_tier =
      user_reservations
      |> Enum.group_by(& &1.ticket_tier_id)
      |> Enum.map(fn {tier_id, reservations} ->
        total_reserved =
          Enum.reduce(reservations, 0, fn r, acc -> acc + r.quantity end)

        {tier_id, total_reserved}
      end)
      |> Map.new()

    # Compute derived values
    ticket_tiers = get_ticket_tiers_from_list(ticket_tiers_with_counts)

    event_at_capacity =
      compute_event_at_capacity(
        event,
        ticket_tiers_with_counts,
        availability_data
      )

    available_capacity = get_available_capacity_from_data(availability_data)
    sold_percentage = compute_sold_percentage(event, availability_data)
    has_ticket_tiers = ticket_tiers_with_counts != []

    # Update event with accurate pricing info
    event_with_pricing =
      add_pricing_info_from_tiers(event, ticket_tiers_with_counts)

    {:noreply,
     socket
     |> assign(:event, event_with_pricing)
     |> assign(:agendas, agendas)
     |> assign(:active_agenda, default_active_agenda(agendas))
     |> assign(:user_tickets, user_tickets)
     |> assign(:all_tickets_by_order, all_tickets_by_order)
     |> assign(:ticket_tiers, ticket_tiers)
     |> assign(:availability_data, availability_data)
     |> assign(:event_at_capacity, event_at_capacity)
     |> assign(:event_selling_fast, event_selling_fast)
     |> assign(:available_capacity, available_capacity)
     |> assign(:sold_percentage, sold_percentage)
     |> assign(:has_ticket_tiers, has_ticket_tiers)
     |> assign(:attendees_count, attendees_count)
     |> assign(:attendees_list, attendees_list)
     |> assign(:ticket_counts_per_user, ticket_counts_per_user)
     |> assign(:user_reservations, user_reservations)
     |> assign(:reservations_by_tier, reservations_by_tier)
     |> assign(:async_data_loaded, true)}
  end

  def handle_async(:load_event_data, {:exit, reason}, socket) do
    require Logger
    Logger.error("Failed to load event data async: #{inspect(reason)}")

    # Keep showing the page with minimal data, mark as loaded to avoid infinite loading
    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    # Parse query parameters from URI
    query_params = parse_query_params(uri)

    # Check for checkout state in URL: checkout=payment|free&order_id=xxx
    checkout_step = query_params["checkout"] || query_params[:checkout]

    order_id =
      query_params["order_id"] || query_params[:order_id] ||
        query_params["resume_order"] ||
        query_params[:resume_order]

    socket =
      cond do
        # If we have checkout step and order_id, restore that state
        checkout_step && order_id && socket.assigns.current_user ->
          restore_checkout_state_from_url(
            socket,
            order_id,
            checkout_step,
            socket.assigns.event.id
          )

        # Legacy: resume_order parameter (for backwards compatibility)
        order_id && socket.assigns.current_user ->
          restore_checkout_state(socket, order_id, socket.assigns.event.id)

        # If we're on the tickets route, show ticket modal
        socket.assigns.live_action == :tickets ->
          socket
          |> assign(:show_ticket_modal, true)

        # Otherwise, clear any checkout state
        true ->
          socket
          |> assign(:show_ticket_modal, false)
          |> assign(:show_payment_modal, false)
          |> assign(:show_free_ticket_confirmation, false)
      end

    {:noreply, socket}
  end

  # Helper to parse query parameters from URI
  defp parse_query_params(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{query: nil} -> %{}
      %URI{query: query} -> URI.decode_query(query)
      _ -> %{}
    end
  end

  defp parse_query_params(_), do: %{}

  # Restore checkout state from URL parameters
  defp restore_checkout_state_from_url(
         socket,
         order_id,
         checkout_step,
         event_id
       ) do
    require Logger

    Logger.debug("restore_checkout_state_from_url: Starting restore",
      order_id: order_id,
      checkout_step: checkout_step,
      event_id: event_id,
      current_user_id: socket.assigns.current_user.id
    )

    case Ysc.Tickets.get_ticket_order(order_id) do
      nil ->
        Logger.warning("restore_checkout_state_from_url: Order not found",
          order_id: order_id
        )

        socket
        |> put_flash(:error, "Order not found")
        |> push_patch(to: ~p"/events/#{event_id}")

      ticket_order ->
        Logger.debug(
          "restore_checkout_state_from_url: Order found - order_id=#{ticket_order.id}, order_user_id=#{ticket_order.user_id}, order_event_id=#{ticket_order.event_id}, order_status=#{inspect(ticket_order.status)}, order_expires_at=#{inspect(ticket_order.expires_at)}, current_user_id=#{socket.assigns.current_user.id}, expected_event_id=#{event_id}"
        )

        # Verify the order belongs to the current user and event
        user_matches = ticket_order.user_id == socket.assigns.current_user.id
        event_matches = ticket_order.event_id == event_id
        status_pending = ticket_order.status == :pending

        Logger.debug(
          "restore_checkout_state_from_url: Validation checks - user_matches=#{user_matches}, event_matches=#{event_matches}, status_pending=#{status_pending}, order_status=#{inspect(ticket_order.status)}, all_valid=#{user_matches && event_matches && status_pending}"
        )

        if user_matches && event_matches && status_pending do
          # Check if order has expired
          now = DateTime.utc_now()
          is_expired = DateTime.compare(now, ticket_order.expires_at) == :gt

          Logger.debug("restore_checkout_state_from_url: Expiration check",
            now: now,
            expires_at: ticket_order.expires_at,
            is_expired: is_expired
          )

          if is_expired do
            Logger.warning("restore_checkout_state_from_url: Order expired",
              order_id: ticket_order.id,
              expires_at: ticket_order.expires_at,
              now: now
            )

            socket
            |> put_flash(
              :error,
              "This order has expired. Please create a new order."
            )
            |> push_patch(to: ~p"/events/#{event_id}")
          else
            Logger.debug(
              "restore_checkout_state_from_url: All checks passed, restoring state",
              order_id: ticket_order.id,
              checkout_step: checkout_step
            )

            # Restore the ticket order and payment intent based on checkout step
            restore_payment_state_from_url(socket, ticket_order, checkout_step)
          end
        else
          Logger.debug(
            "restore_checkout_state_from_url: Validation failed - order_id=#{ticket_order.id}, user_matches=#{user_matches}, event_matches=#{event_matches}, status_pending=#{status_pending}, order_user_id=#{ticket_order.user_id}, current_user_id=#{socket.assigns.current_user.id}, order_event_id=#{ticket_order.event_id}, expected_event_id=#{event_id}, order_status=#{inspect(ticket_order.status)}"
          )

          # Provide a more specific error message based on the order status
          error_message =
            case ticket_order.status do
              :cancelled ->
                "This order was cancelled. Please select your tickets again to create a new order."

              :completed ->
                "This order has already been completed. Please check your tickets."

              :expired ->
                "This order has expired. Please select your tickets again to create a new order."

              _ ->
                "Cannot resume this order. Please select your tickets again."
            end

          socket
          |> put_flash(:error, error_message)
          |> push_patch(to: ~p"/events/#{event_id}")
        end
    end
  end

  # Restore checkout state from a pending order (legacy support)
  defp restore_checkout_state(socket, order_id, event_id) do
    require Logger

    Logger.debug("restore_checkout_state: Starting restore (legacy)",
      order_id: order_id,
      event_id: event_id,
      current_user_id: socket.assigns.current_user.id
    )

    # Determine checkout step based on order amount
    case Ysc.Tickets.get_ticket_order(order_id) do
      nil ->
        Logger.warning("restore_checkout_state: Order not found",
          order_id: order_id
        )

        socket
        |> put_flash(:error, "Order not found")

      ticket_order ->
        Logger.debug(
          "restore_checkout_state: Order found - order_id=#{ticket_order.id}, order_user_id=#{ticket_order.user_id}, order_event_id=#{ticket_order.event_id}, order_status=#{inspect(ticket_order.status)}, order_total_amount=#{inspect(ticket_order.total_amount)}, current_user_id=#{socket.assigns.current_user.id}, expected_event_id=#{event_id}"
        )

        # Verify the order belongs to the current user and event
        user_matches = ticket_order.user_id == socket.assigns.current_user.id
        event_matches = ticket_order.event_id == event_id
        status_pending = ticket_order.status == :pending

        Logger.debug(
          "restore_checkout_state: Validation checks - user_matches=#{user_matches}, event_matches=#{event_matches}, status_pending=#{status_pending}, all_valid=#{user_matches && event_matches && status_pending}"
        )

        if user_matches && event_matches && status_pending do
          # Check if order has expired
          now = DateTime.utc_now()
          is_expired = DateTime.compare(now, ticket_order.expires_at) == :gt

          Logger.debug("restore_checkout_state: Expiration check",
            now: now,
            expires_at: ticket_order.expires_at,
            is_expired: is_expired
          )

          if is_expired do
            Logger.warning("restore_checkout_state: Order expired",
              order_id: ticket_order.id,
              expires_at: ticket_order.expires_at,
              now: now
            )

            socket
            |> put_flash(
              :error,
              "This order has expired. Please create a new order."
            )
          else
            checkout_step =
              if Money.zero?(ticket_order.total_amount),
                do: "free",
                else: "payment"

            Logger.debug(
              "restore_checkout_state: All checks passed, restoring state",
              order_id: ticket_order.id,
              checkout_step: checkout_step
            )

            # Determine checkout step and restore
            restore_payment_state_from_url(socket, ticket_order, checkout_step)
          end
        else
          Logger.debug(
            "restore_checkout_state: Validation failed - order_id=#{ticket_order.id}, user_matches=#{user_matches}, event_matches=#{event_matches}, status_pending=#{status_pending}, order_user_id=#{ticket_order.user_id}, current_user_id=#{socket.assigns.current_user.id}, order_event_id=#{ticket_order.event_id}, expected_event_id=#{event_id}, order_status=#{inspect(ticket_order.status)}"
          )

          # Provide a more specific error message based on the order status
          error_message =
            case ticket_order.status do
              :cancelled ->
                "This order was cancelled. Please select your tickets again to create a new order."

              :completed ->
                "This order has already been completed. Please check your tickets."

              :expired ->
                "This order has expired. Please select your tickets again to create a new order."

              _ ->
                "Cannot resume this order. Please select your tickets again."
            end

          socket
          |> put_flash(:error, error_message)
        end
    end
  end

  # Restore payment state from URL (payment intent or free ticket confirmation)
  defp restore_payment_state_from_url(socket, ticket_order, checkout_step) do
    require Logger

    Logger.debug("restore_payment_state_from_url: Starting restore",
      order_id: ticket_order.id,
      checkout_step: checkout_step
    )

    # Reload ticket order with tickets and tiers
    ticket_order = Ysc.Tickets.get_ticket_order(ticket_order.id)

    Logger.debug("restore_payment_state_from_url: Ticket order reloaded",
      order_id: ticket_order.id,
      tickets_count: length(ticket_order.tickets || []),
      total_amount: ticket_order.total_amount
    )

    # Reconstruct selected_tickets map from the ticket order
    selected_tickets = build_selected_tickets_from_order(ticket_order)

    # Check if any tickets require registration
    tickets_requiring_registration =
      get_tickets_requiring_registration(ticket_order.tickets)

    # Load family members for the current user
    family_members = Ysc.Accounts.get_family_group(socket.assigns.current_user)

    # Initialize ticket details form with existing registrations or empty values
    # Pre-fill first ticket with user details if it's defaulted to "for me"
    # For non-first tickets, leave form data empty (they default to "Someone else")
    ticket_details_form =
      tickets_requiring_registration
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {ticket, index}, acc ->
        ticket_detail = Ysc.Events.get_registration_for_ticket(ticket.id)
        ticket_id_str = to_string(ticket.id)

        # If this is the first ticket and it's defaulted to "for me", pre-fill with user details
        # For non-first tickets (index > 0), always use empty values (they default to "Someone else")
        form_data =
          if index == 0 && is_nil(ticket_detail) do
            %{
              first_name: socket.assigns.current_user.first_name || "",
              last_name: socket.assigns.current_user.last_name || "",
              email: socket.assigns.current_user.email || ""
            }
          else
            # For non-first tickets or tickets with existing details, use empty or existing values
            %{
              first_name:
                if(ticket_detail, do: ticket_detail.first_name, else: ""),
              last_name:
                if(ticket_detail, do: ticket_detail.last_name, else: ""),
              email: if(ticket_detail, do: ticket_detail.email, else: "")
            }
          end

        Map.put(acc, ticket_id_str, form_data)
      end)

    # Initialize tickets_for_me map
    # Smart default: First ticket defaults to "for me" for better UX
    tickets_for_me =
      tickets_requiring_registration
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {ticket, index}, acc ->
        # Default first ticket (index 0) to "for me"
        # Use string key for consistency with handler
        Map.put(acc, to_string(ticket.id), index == 0)
      end)

    # Initialize selected_family_members map (tracks which family member is selected for each ticket)
    selected_family_members =
      tickets_requiring_registration
      |> Enum.reduce(%{}, fn ticket, acc ->
        # Use string key for consistency with handler
        Map.put(acc, to_string(ticket.id), nil)
      end)

    # Initialize active_ticket_index for progressive disclosure (first ticket is active by default)
    active_ticket_index =
      if tickets_requiring_registration != [], do: 0, else: nil

    # Use cached ticket tiers from assigns instead of querying again
    ticket_tiers = socket.assigns.ticket_tiers

    availability_data =
      case Ysc.Tickets.BookingLocker.check_availability_with_lock(
             ticket_order.event_id
           ) do
        {:ok, availability} -> availability
        {:error, _} -> nil
      end

    socket = socket |> assign(:selected_tickets, selected_tickets)

    case checkout_step do
      "free" ->
        # For free tickets, show confirmation modal with registration
        socket
        |> assign(:show_ticket_modal, false)
        |> assign(:show_free_ticket_confirmation, true)
        |> assign(:ticket_order, ticket_order)
        |> assign(
          :tickets_requiring_registration,
          tickets_requiring_registration
        )
        |> assign(:ticket_details_form, ticket_details_form)
        |> assign(:tickets_for_me, tickets_for_me)
        |> assign(:selected_family_members, selected_family_members)
        |> assign(:family_members, family_members)
        |> assign(:active_ticket_index, active_ticket_index)
        |> assign(:ticket_tiers, ticket_tiers)
        |> assign(:availability_data, availability_data)

      "payment" ->
        # For paid tickets, retrieve or create payment intent and show payment modal with registration
        require Logger

        Logger.debug(
          "restore_payment_state_from_url: Retrieving/creating payment intent",
          order_id: ticket_order.id,
          payment_intent_id: ticket_order.payment_intent_id,
          user_stripe_id: socket.assigns.current_user.stripe_id
        )

        case retrieve_or_create_payment_intent(
               ticket_order,
               socket.assigns.current_user
             ) do
          {:ok, payment_intent} ->
            Logger.debug(
              "restore_payment_state_from_url: Payment intent retrieved/created successfully",
              order_id: ticket_order.id,
              payment_intent_id: payment_intent.id,
              payment_intent_status: payment_intent.status
            )

            socket
            |> assign(:show_ticket_modal, false)
            |> assign(:show_payment_modal, true)
            |> assign(:checkout_expired, false)
            |> assign(:payment_intent, payment_intent)
            |> assign(:ticket_order, ticket_order)
            |> assign(
              :tickets_requiring_registration,
              tickets_requiring_registration
            )
            |> assign(:ticket_details_form, ticket_details_form)
            |> assign(:tickets_for_me, tickets_for_me)
            |> assign(:selected_family_members, selected_family_members)
            |> assign(:family_members, family_members)
            |> assign(:ticket_tiers, ticket_tiers)
            |> assign(:availability_data, availability_data)
            |> assign(:payment_redirect_in_progress, false)

          {:error, reason} ->
            Logger.error(
              "restore_payment_state_from_url: Failed to retrieve/create payment intent",
              order_id: ticket_order.id,
              error: reason
            )

            socket
            |> put_flash(:error, "Failed to restore payment: #{reason}")
            |> push_patch(to: ~p"/events/#{socket.assigns.event.id}")
        end

      _ ->
        # Unknown checkout step, clear state
        socket
        |> push_patch(to: ~p"/events/#{socket.assigns.event.id}")
    end
  end

  # Convert Money struct to cents (integer)
  defp money_to_cents(%Money{amount: amount, currency: :USD}) do
    # Use Decimal for precise conversion to avoid floating-point errors
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(%Money{amount: amount, currency: _currency}) do
    # For other currencies, use same conversion
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(_) do
    # Fallback for invalid money values
    0
  end

  # Build selected_tickets map from a ticket order
  # For regular tickets: tier_id => quantity
  # For donation tickets: tier_id => amount_cents (total donation amount in cents)
  defp build_selected_tickets_from_order(ticket_order) do
    if ticket_order.tickets && ticket_order.tickets != [] do
      # Group tickets by tier_id
      tickets_by_tier =
        ticket_order.tickets
        |> Enum.group_by(& &1.ticket_tier_id)

      # Build selected_tickets map
      tickets_by_tier
      |> Enum.reduce(%{}, fn {tier_id, tickets}, acc ->
        first_ticket = List.first(tickets)
        tier = first_ticket.ticket_tier
        quantity = length(tickets)

        # Check if this is a donation tier
        is_donation = tier.type == "donation" || tier.type == :donation

        if is_donation do
          # For donations, calculate the total donation amount for this tier
          # The donation amount is stored in the ticket_order.total_amount
          # We need to calculate how much of the total is for this specific donation tier
          {_gross_event_amount, donation_amount, _discount_amount} =
            Ysc.Tickets.calculate_event_and_donation_amounts(ticket_order)

          # Count all donation tickets in the order
          donation_tickets_count =
            ticket_order.tickets
            |> Enum.count(fn t ->
              t.ticket_tier.type == "donation" ||
                t.ticket_tier.type == :donation
            end)

          # Calculate donation amount per ticket, then multiply by quantity for this tier
          if donation_tickets_count > 0 do
            case Money.div(donation_amount, donation_tickets_count) do
              {:ok, amount_per_ticket} ->
                # Multiply by quantity for this tier and convert to cents
                case Money.mult(amount_per_ticket, quantity) do
                  {:ok, tier_donation_total} ->
                    # Convert Money to cents
                    amount_cents = money_to_cents(tier_donation_total)
                    Map.put(acc, tier_id, amount_cents)

                  _ ->
                    acc
                end

              _ ->
                acc
            end
          else
            acc
          end
        else
          # For regular tickets, just store the quantity
          Map.put(acc, tier_id, quantity)
        end
      end)
    else
      %{}
    end
  end

  # Retrieve existing payment intent or create a new one
  defp retrieve_or_create_payment_intent(ticket_order, user) do
    if ticket_order.payment_intent_id do
      # Try to retrieve existing payment intent
      case Stripe.PaymentIntent.retrieve(ticket_order.payment_intent_id, %{}) do
        {:ok, payment_intent} ->
          # Check if payment intent is still valid (not succeeded or canceled)
          if payment_intent.status in [
               "requires_payment_method",
               "requires_confirmation",
               "requires_action"
             ] do
            {:ok, payment_intent}
          else
            # Payment intent is in a final state, create a new one
            Ysc.Tickets.StripeService.create_payment_intent(ticket_order,
              customer_id: user.stripe_id
            )
          end

        {:error, _} ->
          # Payment intent not found, create a new one
          Ysc.Tickets.StripeService.create_payment_intent(ticket_order,
            customer_id: user.stripe_id
          )
      end
    else
      # No payment intent exists, create a new one
      Ysc.Tickets.StripeService.create_payment_intent(ticket_order,
        customer_id: user.stripe_id
      )
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.EventUpdated{event: event}},
        socket
      ) do
    # Add pricing info to the updated event
    # Ensure ticket_tiers is preloaded in case it wasn't included in the event update
    event = Repo.preload(event, :ticket_tiers)
    event_with_pricing = add_pricing_info(event)
    {:noreply, assign(socket, :event, event_with_pricing)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaAdded{agenda: agenda}},
        socket
      ) do
    new_agendas = socket.assigns.agendas ++ [agenda]

    {:noreply,
     socket
     |> assign(:agendas, new_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaUpdated{agenda: agenda}},
        socket
      ) do
    new_agendas =
      socket.assigns.agendas
      |> Enum.map(fn
        a when a.id == agenda.id -> agenda
        a -> a
      end)

    {:noreply,
     socket
     |> assign(:agendas, new_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaDeleted{agenda: agenda}},
        socket
      ) do
    new_agendas = socket.assigns.agendas |> Enum.reject(&(&1.id == agenda.id))

    active_agenda =
      new_active_agenda(agenda.id, socket.assigns.active_agenda, new_agendas)

    {:noreply,
     socket
     |> assign(:agendas, new_agendas)
     |> assign(:active_agenda, active_agenda)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas,
         %Ysc.MessagePassingEvents.AgendaRepositioned{agenda: agenda}},
        socket
      ) do
    agendas = Agendas.list_agendas_for_event(agenda.event_id)
    {:noreply, socket |> assign(:agendas, agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas,
         %Ysc.MessagePassingEvents.AgendaItemAdded{agenda_item: agenda_item}},
        socket
      ) do
    updated_agendas =
      socket.assigns.agendas
      |> Enum.map(fn
        agenda when agenda.id == agenda_item.agenda_id ->
          %{agenda | agenda_items: agenda.agenda_items ++ [agenda_item]}

        agenda ->
          agenda
      end)

    {:noreply,
     socket
     |> assign(:agendas, updated_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas,
         %Ysc.MessagePassingEvents.AgendaItemDeleted{agenda_item: agenda_item}},
        socket
      ) do
    updated_agendas =
      socket.assigns.agendas
      |> Enum.map(fn
        agenda when agenda.id == agenda_item.agenda_id ->
          %{
            agenda
            | agenda_items:
                Enum.reject(agenda.agenda_items, &(&1.id == agenda_item.id))
          }

        agenda ->
          agenda
      end)

    {:noreply, socket |> assign(:agendas, updated_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas,
         %Ysc.MessagePassingEvents.AgendaItemRepositioned{
           agenda_item: _agenda_item
         }},
        socket
      ) do
    updated_agendas = Agendas.list_agendas_for_event(socket.assigns.event.id)

    {:noreply,
     socket
     |> assign(:agendas, updated_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas,
         %Ysc.MessagePassingEvents.AgendaItemUpdated{agenda_item: agenda_item}},
        socket
      ) do
    updated_agendas =
      socket.assigns.agendas
      |> Enum.map(fn
        agenda when agenda.id == agenda_item.agenda_id ->
          agenda
          |> Map.update!(
            :agenda_items,
            &Enum.map(&1, fn
              item when item.id == agenda_item.id -> agenda_item
              item -> item
            end)
          )

        agenda ->
          agenda
      end)

    {:noreply,
     socket
     |> assign(:agendas, updated_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Tickets,
         %Ysc.MessagePassingEvents.CheckoutSessionExpired{} = event},
        socket
      ) do
    # Handle checkout session expiration
    require Logger

    Logger.info("Received CheckoutSessionExpired event in EventDetailsLive",
      user_id: socket.assigns.current_user.id,
      show_payment_modal: socket.assigns.show_payment_modal,
      current_ticket_order_id:
        socket.assigns.ticket_order && socket.assigns.ticket_order.id,
      expired_ticket_order_id: event.ticket_order && event.ticket_order.id,
      event_data: inspect(event, limit: :infinity)
    )

    # Show expired message if:
    # 1. We have a payment modal open, OR
    # 2. This is the same session that expired
    current_order_id =
      socket.assigns.ticket_order && socket.assigns.ticket_order.id

    expired_order_id = event.ticket_order && event.ticket_order.id

    if socket.assigns.show_payment_modal &&
         (current_order_id == expired_order_id || current_order_id == nil) do
      # Show expired message for the current session or if no specific session is active
      {:noreply,
       socket
       |> assign(:checkout_expired, true)
       |> assign(:payment_intent, nil)
       |> assign(:ticket_order, nil)}
    else
      # This is a different session, just clear the current state without showing expired message
      {:noreply,
       socket
       |> assign(:show_payment_modal, false)
       |> assign(:payment_intent, nil)
       |> assign(:ticket_order, nil)
       |> assign(:selected_tickets, %{})}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Tickets,
         %Ysc.MessagePassingEvents.CheckoutSessionCancelled{} = event},
        socket
      ) do
    # Handle checkout session cancellation
    require Logger

    Logger.info("Received CheckoutSessionCancelled event in EventDetailsLive",
      user_id: socket.assigns.current_user.id,
      show_payment_modal: socket.assigns.show_payment_modal,
      current_ticket_order_id:
        socket.assigns.ticket_order && socket.assigns.ticket_order.id,
      cancelled_ticket_order_id: event.ticket_order && event.ticket_order.id
    )

    # Only show expired message if this is the same session that was cancelled
    if socket.assigns.ticket_order && event.ticket_order &&
         socket.assigns.ticket_order.id == event.ticket_order.id do
      {:noreply,
       socket
       |> assign(:checkout_expired, true)
       |> assign(:payment_intent, nil)
       |> assign(:ticket_order, nil)}
    else
      # This is a different session, just clear the current state without showing expired message
      {:noreply,
       socket
       |> assign(:show_payment_modal, false)
       |> assign(:payment_intent, nil)
       |> assign(:ticket_order, nil)
       |> assign(:selected_tickets, %{})}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCreated{
           ticket_reservation: reservation
         }},
        socket
      ) do
    # Reservations affect availability - refresh availability if for this event
    ticket_tier = Events.get_ticket_tier(reservation.ticket_tier_id)

    if ticket_tier && ticket_tier.event_id == socket.assigns.event.id do
      # Use the same refresh logic as TicketAvailabilityUpdated
      event_id = socket.assigns.event.id
      ticket_tiers_with_counts = Events.list_ticket_tiers_for_event(event_id)
      ticket_tiers = get_ticket_tiers_from_list(ticket_tiers_with_counts)

      availability_data =
        case Ysc.Tickets.BookingLocker.check_availability_with_lock(event_id) do
          {:ok, availability} -> availability
          {:error, _} -> socket.assigns.availability_data
        end

      event = socket.assigns.event

      event_at_capacity =
        compute_event_at_capacity(
          event,
          ticket_tiers_with_counts,
          availability_data
        )

      event_selling_fast = Events.event_selling_fast?(event_id)
      available_capacity = get_available_capacity_from_data(availability_data)
      sold_percentage = compute_sold_percentage(event, availability_data)

      {:noreply,
       socket
       |> assign(:ticket_tiers, ticket_tiers)
       |> assign(:availability_data, availability_data)
       |> assign(:event_at_capacity, event_at_capacity)
       |> assign(:event_selling_fast, event_selling_fast)
       |> assign(:available_capacity, available_capacity)
       |> assign(:sold_percentage, sold_percentage)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationFulfilled{
           ticket_reservation: reservation
         }},
        socket
      ) do
    # Reservations affect availability - refresh availability if for this event
    ticket_tier = Events.get_ticket_tier(reservation.ticket_tier_id)

    if ticket_tier && ticket_tier.event_id == socket.assigns.event.id do
      # Use the same refresh logic as TicketAvailabilityUpdated
      event_id = socket.assigns.event.id
      ticket_tiers_with_counts = Events.list_ticket_tiers_for_event(event_id)
      ticket_tiers = get_ticket_tiers_from_list(ticket_tiers_with_counts)

      availability_data =
        case Ysc.Tickets.BookingLocker.check_availability_with_lock(event_id) do
          {:ok, availability} -> availability
          {:error, _} -> socket.assigns.availability_data
        end

      event = socket.assigns.event

      event_at_capacity =
        compute_event_at_capacity(
          event,
          ticket_tiers_with_counts,
          availability_data
        )

      event_selling_fast = Events.event_selling_fast?(event_id)
      available_capacity = get_available_capacity_from_data(availability_data)
      sold_percentage = compute_sold_percentage(event, availability_data)

      {:noreply,
       socket
       |> assign(:ticket_tiers, ticket_tiers)
       |> assign(:availability_data, availability_data)
       |> assign(:event_at_capacity, event_at_capacity)
       |> assign(:event_selling_fast, event_selling_fast)
       |> assign(:available_capacity, available_capacity)
       |> assign(:sold_percentage, sold_percentage)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCancelled{
           ticket_reservation: reservation
         }},
        socket
      ) do
    # Reservations affect availability - refresh availability if for this event
    ticket_tier = Events.get_ticket_tier(reservation.ticket_tier_id)

    if ticket_tier && ticket_tier.event_id == socket.assigns.event.id do
      # Use the same refresh logic as TicketAvailabilityUpdated
      event_id = socket.assigns.event.id
      ticket_tiers_with_counts = Events.list_ticket_tiers_for_event(event_id)
      ticket_tiers = get_ticket_tiers_from_list(ticket_tiers_with_counts)

      availability_data =
        case Ysc.Tickets.BookingLocker.check_availability_with_lock(event_id) do
          {:ok, availability} -> availability
          {:error, _} -> socket.assigns.availability_data
        end

      event = socket.assigns.event

      event_at_capacity =
        compute_event_at_capacity(
          event,
          ticket_tiers_with_counts,
          availability_data
        )

      event_selling_fast = Events.event_selling_fast?(event_id)
      available_capacity = get_available_capacity_from_data(availability_data)
      sold_percentage = compute_sold_percentage(event, availability_data)

      {:noreply,
       socket
       |> assign(:ticket_tiers, ticket_tiers)
       |> assign(:availability_data, availability_data)
       |> assign(:event_at_capacity, event_at_capacity)
       |> assign(:event_selling_fast, event_selling_fast)
       |> assign(:available_capacity, available_capacity)
       |> assign(:sold_percentage, sold_percentage)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Tickets,
         %Ysc.MessagePassingEvents.TicketAvailabilityUpdated{event_id: event_id}},
        socket
      ) do
    # Handle ticket availability updates - refresh the event to get updated availability counts
    # Only process if this is for the current event
    if socket.assigns.event.id == event_id do
      # Reload ticket tiers with fresh sold counts
      ticket_tiers_with_counts = Events.list_ticket_tiers_for_event(event_id)
      ticket_tiers = get_ticket_tiers_from_list(ticket_tiers_with_counts)

      # Refresh cached availability data
      availability_data =
        case Ysc.Tickets.BookingLocker.check_availability_with_lock(event_id) do
          {:ok, availability} -> availability
          {:error, _} -> socket.assigns.availability_data
        end

      # Recompute cached values with fresh data
      event = socket.assigns.event

      event_at_capacity =
        compute_event_at_capacity(
          event,
          ticket_tiers_with_counts,
          availability_data
        )

      event_selling_fast = Events.event_selling_fast?(event_id)
      available_capacity = get_available_capacity_from_data(availability_data)
      sold_percentage = compute_sold_percentage(event, availability_data)

      # Update event with fresh pricing info
      event_with_pricing =
        add_pricing_info_from_tiers(event, ticket_tiers_with_counts)

      # Refresh attendees list if user has active membership
      {attendees_count, attendees_list, ticket_counts_per_user} =
        if socket.assigns.active_membership? do
          ticket_count = Events.count_tickets_sold_excluding_donations(event_id)

          if ticket_count >= 5 do
            attendees = Events.list_unique_attendees_for_event(event_id)
            # Filter out the current user from the attendees list
            filtered_attendees =
              if socket.assigns.current_user do
                Enum.reject(attendees, fn attendee ->
                  attendee.id == socket.assigns.current_user.id
                end)
              else
                attendees
              end

            ticket_counts = Events.get_ticket_counts_per_user(event_id)
            {ticket_count, filtered_attendees, ticket_counts}
          else
            {nil, nil, %{}}
          end
        else
          {nil, nil, %{}}
        end

      # Trigger animation on all tier availability elements
      {:noreply,
       socket
       |> assign(:event, event_with_pricing)
       |> assign(:ticket_tiers, ticket_tiers)
       |> assign(:availability_data, availability_data)
       |> assign(:event_at_capacity, event_at_capacity)
       |> assign(:event_selling_fast, event_selling_fast)
       |> assign(:available_capacity, available_capacity)
       |> assign(:sold_percentage, sold_percentage)
       |> assign(:attendees_count, attendees_count)
       |> assign(:attendees_list, attendees_list)
       |> assign(:ticket_counts_per_user, ticket_counts_per_user)
       |> push_event("animate-availability-update", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Cancel any pending ticket order when the LiveView terminates
    # BUT don't cancel if a payment redirect is in progress (e.g., Amazon Pay, CashApp)
    # The payment success page will handle the redirect back
    if socket.assigns.ticket_order && socket.assigns.show_payment_modal &&
         !socket.assigns[:payment_redirect_in_progress] do
      # Check payment intent status to see if a redirect is required
      # Payment methods like Amazon Pay, CashApp require redirects and set status to "requires_action"
      should_cancel =
        case socket.assigns.ticket_order.payment_intent_id do
          nil ->
            # No payment intent yet, safe to cancel
            true

          payment_intent_id ->
            # Check payment intent status from Stripe
            # If it requires action (redirect), don't cancel - user is completing payment
            case Stripe.PaymentIntent.retrieve(payment_intent_id, %{}) do
              {:ok, payment_intent} ->
                # Don't cancel if payment intent is in a state that indicates active payment processing
                # Statuses that indicate redirect/action required: requires_action (Amazon Pay, CashApp, etc.)
                # Statuses that indicate in-progress: processing, requires_confirmation
                # Statuses that indicate completion: succeeded, canceled (order already handled)
                # Status that indicates no payment method: requires_payment_method (user hasn't started payment yet, safe to cancel)
                case payment_intent.status do
                  "requires_action" ->
                    # Redirect payment method in progress - don't cancel
                    false

                  "processing" ->
                    # Payment is being processed - don't cancel
                    false

                  "requires_confirmation" ->
                    # Payment needs confirmation - don't cancel
                    false

                  "succeeded" ->
                    # Payment already succeeded - order should be completed, but if we're here,
                    # something went wrong. Don't cancel to be safe.
                    require Logger

                    Logger.warning(
                      "Payment intent already succeeded in terminate/2, not cancelling order",
                      payment_intent_id: payment_intent_id,
                      ticket_order_id: socket.assigns.ticket_order.id
                    )

                    false

                  _ ->
                    # Other statuses (requires_payment_method, canceled, etc.) - safe to cancel
                    true
                end

              {:error, _} ->
                # If we can't retrieve payment intent, err on the side of caution
                # and don't cancel (might be a temporary Stripe API issue or payment in progress)
                require Logger

                Logger.warning(
                  "Could not retrieve payment intent status in terminate/2, not cancelling order",
                  payment_intent_id: payment_intent_id,
                  ticket_order_id: socket.assigns.ticket_order.id
                )

                false
            end
        end

      if should_cancel do
        Ysc.Tickets.cancel_ticket_order(
          socket.assigns.ticket_order,
          "User left checkout"
        )
      end
    end
  end

  @impl true
  def handle_event("set-active-agenda", %{"id" => id}, socket) do
    {:noreply, assign(socket, :active_agenda, id)}
  end

  @impl true
  def handle_event("toggle-map", _, socket) do
    event = socket.assigns.event

    {:noreply,
     socket
     |> Phoenix.LiveView.push_event("add-marker", %{
       lat: event.latitude,
       lon: event.longitude,
       locked: true
     })
     |> Phoenix.LiveView.push_event("position", %{})
     |> Phoenix.LiveView.push_event("toggle-map-text", %{})}
  end

  @impl true
  def handle_event("login-redirect", _params, socket) do
    {:noreply, socket |> redirect(to: ~p"/users/log-in")}
  end

  @impl true
  def handle_event("open-ticket-modal", _params, socket) do
    {:noreply,
     socket |> push_navigate(to: ~p"/events/#{socket.assigns.event.id}/tickets")}
  end

  @impl true
  def handle_event("close-ticket-modal", _params, socket) do
    # If we're on the tickets route, navigate back to the event details page
    if socket.assigns.live_action == :tickets do
      {:noreply,
       socket
       |> push_navigate(to: ~p"/events/#{socket.assigns.event.id}")
       |> assign(:show_ticket_modal, false)
       |> assign(:selected_tickets, %{})}
    else
      {:noreply,
       socket
       |> assign(:show_ticket_modal, false)
       |> assign(:selected_tickets, %{})}
    end
  end

  @impl true
  def handle_event("close-payment-modal", _params, socket) do
    # Cancel the ticket order to release reserved tickets
    if socket.assigns.ticket_order do
      Ysc.Tickets.cancel_ticket_order(
        socket.assigns.ticket_order,
        "User cancelled checkout"
      )
    end

    {:noreply,
     socket
     |> assign(:show_payment_modal, false)
     |> assign(:checkout_expired, false)
     |> assign(:payment_intent, nil)
     |> assign(:ticket_order, nil)
     |> assign(:tickets_requiring_registration, [])
     |> assign(:ticket_details_form, %{})
     |> assign(:tickets_for_me, %{})
     |> assign(:payment_redirect_in_progress, false)
     |> push_patch(to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def handle_event("close-registration-modal", _params, socket) do
    # Cancel the ticket order to release reserved tickets
    if socket.assigns.ticket_order do
      Ysc.Tickets.cancel_ticket_order(
        socket.assigns.ticket_order,
        "User cancelled registration"
      )
    end

    {:noreply,
     socket
     |> assign(:show_registration_modal, false)
     |> assign(:ticket_order, nil)
     |> assign(:tickets_requiring_registration, [])
     |> assign(:ticket_details_form, %{})}
  end

  @impl true
  def handle_event("submit-registration", params, socket) do
    # Extract ticket details from form params
    ticket_details_list =
      socket.assigns.tickets_requiring_registration
      |> Enum.map(fn ticket ->
        %{
          ticket_id: ticket.id,
          first_name: params["ticket_#{ticket.id}_first_name"] || "",
          last_name: params["ticket_#{ticket.id}_last_name"] || "",
          email: params["ticket_#{ticket.id}_email"] || ""
        }
      end)

    # Validate that all fields are filled
    all_valid =
      ticket_details_list
      |> Enum.all?(fn detail ->
        detail.first_name != "" &&
          detail.last_name != "" &&
          detail.email != ""
      end)

    if all_valid do
      # Save ticket details
      case Ysc.Events.create_ticket_details(ticket_details_list) do
        {:ok, _ticket_details} ->
          # Proceed to payment or free confirmation
          proceed_to_payment_or_free(
            socket
            |> assign(:show_registration_modal, false)
            |> assign(:tickets_requiring_registration, [])
            |> assign(:ticket_details_form, %{}),
            socket.assigns.ticket_order
          )

        {:error, _reason} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Failed to save registration details. Please try again."
           )}
      end
    else
      {:noreply,
       socket
       |> put_flash(
         :error,
         "Please fill in all required fields for each ticket."
       )}
    end
  end

  @impl true
  def handle_event("close-free-ticket-confirmation", _params, socket) do
    # Cancel the ticket order to release reserved tickets
    if socket.assigns.ticket_order do
      Ysc.Tickets.cancel_ticket_order(
        socket.assigns.ticket_order,
        "User cancelled free ticket confirmation"
      )
    end

    {:noreply,
     socket
     |> assign(:show_free_ticket_confirmation, false)
     |> assign(:ticket_order, nil)
     |> assign(:tickets_requiring_registration, [])
     |> assign(:ticket_details_form, %{})
     |> assign(:tickets_for_me, %{})
     |> push_patch(to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def handle_event("confirm-free-tickets", _params, socket) do
    # Save registration details if any tickets require registration
    tickets_requiring_registration =
      socket.assigns.tickets_requiring_registration || []

    if Enum.any?(tickets_requiring_registration) do
      tickets_for_me = socket.assigns.tickets_for_me || %{}
      ticket_details_form = socket.assigns.ticket_details_form || %{}
      current_user = socket.assigns.current_user

      ticket_details_list =
        build_ticket_details_list(
          tickets_requiring_registration,
          tickets_for_me,
          ticket_details_form,
          current_user
        )

      all_valid =
        validate_ticket_details(
          tickets_requiring_registration,
          ticket_details_list,
          tickets_for_me,
          current_user
        )

      if all_valid do
        save_ticket_details_and_process(ticket_details_list, socket, fn ->
          process_free_tickets(socket)
        end)
      else
        handle_registration_validation_failure(
          tickets_requiring_registration,
          ticket_details_list,
          tickets_for_me,
          ticket_details_form,
          current_user,
          socket,
          "Please fill in all required registration fields before confirming."
        )
      end
    else
      # No registration required, proceed with free ticket processing
      process_free_tickets(socket)
    end
  end

  @impl true
  def handle_event("close-order-completion", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_order_completion, false)
     |> assign(:ticket_order, nil)
     |> push_patch(to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def handle_event("show-attendees-modal", _params, socket) do
    {:noreply, assign(socket, :show_attendees_modal, true)}
  end

  @impl true
  def handle_event("close-attendees-modal", _params, socket) do
    {:noreply, assign(socket, :show_attendees_modal, false)}
  end

  @impl true
  def handle_event("payment-redirect-started", _params, socket) do
    # Track that a payment redirect is in progress (e.g., Amazon Pay, CashApp)
    # This prevents the order from being cancelled when the LiveView connection is lost
    {:noreply, assign(socket, :payment_redirect_in_progress, true)}
  end

  @impl true
  def handle_event(
        "payment-success",
        %{"payment_intent_id" => payment_intent_id},
        socket
      ) do
    # Save registration details if any tickets require registration
    tickets_requiring_registration =
      socket.assigns.tickets_requiring_registration || []

    if Enum.any?(tickets_requiring_registration) do
      tickets_for_me = socket.assigns.tickets_for_me || %{}
      ticket_details_form = socket.assigns.ticket_details_form || %{}
      current_user = socket.assigns.current_user

      ticket_details_list =
        build_ticket_details_list(
          tickets_requiring_registration,
          tickets_for_me,
          ticket_details_form,
          current_user
        )

      all_valid =
        validate_ticket_details(
          tickets_requiring_registration,
          ticket_details_list,
          tickets_for_me,
          current_user
        )

      if all_valid do
        save_ticket_details_and_process(ticket_details_list, socket, fn ->
          process_payment_success(socket, payment_intent_id)
        end)
      else
        handle_registration_validation_failure(
          tickets_requiring_registration,
          ticket_details_list,
          tickets_for_me,
          ticket_details_form,
          current_user,
          socket,
          "Please fill in all required registration fields before completing payment."
        )
      end
    else
      # No registration required, proceed with payment
      process_payment_success(socket, payment_intent_id)
    end
  end

  @impl true
  def handle_event("checkout-expired", _params, socket) do
    # Expire the ticket order to release reserved tickets
    if socket.assigns.ticket_order do
      Ysc.Tickets.expire_ticket_order(socket.assigns.ticket_order)
    end

    # Handle checkout expiration
    {:noreply,
     socket
     |> put_flash(
       :error,
       "Your checkout session has expired. Please select your tickets again to continue."
     )
     |> assign(:show_payment_modal, false)
     |> assign(:payment_intent, nil)
     |> assign(:ticket_order, nil)
     |> assign(:selected_tickets, %{})
     |> assign(:tickets_requiring_registration, [])
     |> assign(:ticket_details_form, %{})
     |> assign(:tickets_for_me, %{})
     |> push_patch(to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def handle_event("retry-checkout", _params, socket) do
    # Reset checkout state and show ticket selection modal
    {:noreply,
     socket
     |> assign(:checkout_expired, false)
     |> assign(:show_payment_modal, false)
     |> assign(:payment_intent, nil)
     |> assign(:ticket_order, nil)
     |> assign(:selected_tickets, %{})
     |> assign(:tickets_requiring_registration, [])
     |> assign(:ticket_details_form, %{})
     |> assign(:tickets_for_me, %{})
     |> assign(:show_ticket_modal, true)
     |> push_patch(to: ~p"/events/#{socket.assigns.event.id}/tickets")}
  end

  @impl true
  def handle_event("toggle-ticket-for-me", %{"ticket-id" => ticket_id}, socket) do
    # Toggle the "for me" state for this ticket
    # Normalize ticket_id - try to find the actual ticket to get its ID format
    ticket_id_normalized =
      socket.assigns.tickets_requiring_registration
      |> Enum.find(fn ticket ->
        to_string(ticket.id) == to_string(ticket_id)
      end)
      |> case do
        %{id: id} -> id
        nil -> ticket_id
      end

    tickets_for_me = socket.assigns.tickets_for_me || %{}
    ticket_details_form = socket.assigns.ticket_details_form || %{}
    ticket_id_str = to_string(ticket_id_normalized)

    # Check both string and original ID format
    current_state =
      Map.get(tickets_for_me, ticket_id_normalized, false) ||
        Map.get(tickets_for_me, ticket_id_str, false)

    new_state = !current_state

    # Store in tickets_for_me using the original ticket.id format for consistency
    updated_tickets_for_me =
      Map.put(tickets_for_me, ticket_id_normalized, new_state)

    # If checked, auto-fill with user's details
    updated_form =
      if new_state do
        # Auto-fill with current user's details
        Map.put(ticket_details_form, ticket_id_str, %{
          first_name: socket.assigns.current_user.first_name || "",
          last_name: socket.assigns.current_user.last_name || "",
          email: socket.assigns.current_user.email || ""
        })
      else
        # Clear the form data when unchecked
        Map.put(ticket_details_form, ticket_id_str, %{
          first_name: "",
          last_name: "",
          email: ""
        })
      end

    # Clear selected family member when "for me" is toggled
    selected_family_members = socket.assigns.selected_family_members || %{}

    updated_selected_family_members =
      if new_state do
        # Clear family member selection when "for me" is checked
        Map.put(selected_family_members, ticket_id_normalized, nil)
      else
        selected_family_members
      end

    {:noreply,
     socket
     |> assign(:tickets_for_me, updated_tickets_for_me)
     |> assign(:ticket_details_form, updated_form)
     |> assign(:selected_family_members, updated_selected_family_members)}
  end

  @impl true
  def handle_event("select-family-member", params, socket) do
    # Extract ticket_id from phx-value-ticket-id
    ticket_id = params["ticket-id"] || params["ticket_id"]

    # Get the selected user ID from the select value
    # The select name is "ticket_#{ticket_id}_family_member", so we need to extract it from params
    select_name = "ticket_#{ticket_id}_family_member"
    user_id = params[select_name] || params["user-id"]

    if ticket_id && user_id && user_id != "" do
      # Find the selected family member
      family_members = socket.assigns.family_members || []

      selected_user =
        Enum.find(family_members, fn user ->
          to_string(user.id) == to_string(user_id)
        end)

      if selected_user do
        # Normalize ticket_id
        ticket_id_normalized =
          socket.assigns.tickets_requiring_registration
          |> Enum.find(fn ticket ->
            to_string(ticket.id) == to_string(ticket_id)
          end)
          |> case do
            %{id: id} -> id
            nil -> ticket_id
          end

        ticket_details_form = socket.assigns.ticket_details_form || %{}
        ticket_id_str = to_string(ticket_id_normalized)

        # Auto-fill with selected family member's details
        updated_form =
          Map.put(ticket_details_form, ticket_id_str, %{
            first_name: selected_user.first_name || "",
            last_name: selected_user.last_name || "",
            email: selected_user.email || ""
          })

        # Uncheck "for me" if it was checked (since we're selecting a different family member)
        tickets_for_me = socket.assigns.tickets_for_me || %{}

        updated_tickets_for_me =
          Map.put(tickets_for_me, ticket_id_normalized, false)

        # Track the selected family member for this ticket
        selected_family_members = socket.assigns.selected_family_members || %{}

        updated_selected_family_members =
          Map.put(
            selected_family_members,
            ticket_id_normalized,
            selected_user.id
          )

        {:noreply,
         socket
         |> assign(:ticket_details_form, updated_form)
         |> assign(:tickets_for_me, updated_tickets_for_me)
         |> assign(:selected_family_members, updated_selected_family_members)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select-ticket-attendee", params, socket) do
    require Logger

    # Get ticket_id from the hidden field
    ticket_id = params["ticket_id"]

    # Get the selected value directly from the select field
    # The select field name is "ticket_#{ticket_id}_attendee_select"
    selected_value =
      if ticket_id do
        select_field_name = "ticket_#{ticket_id}_attendee_select"
        params[select_field_name]
      else
        nil
      end

    if ticket_id && selected_value do
      # Normalize ticket_id - find the actual ticket to get its ID
      ticket_id_normalized =
        socket.assigns.tickets_requiring_registration
        |> Enum.find(fn ticket ->
          to_string(ticket.id) == to_string(ticket_id)
        end)
        |> case do
          %{id: id} -> id
          nil -> ticket_id
        end

      ticket_id_str = to_string(ticket_id_normalized)
      ticket_details_form = socket.assigns.ticket_details_form || %{}
      tickets_for_me = socket.assigns.tickets_for_me || %{}
      selected_family_members = socket.assigns.selected_family_members || %{}
      family_members = socket.assigns.family_members || []

      {updated_tickets_for_me, updated_selected_family_members, updated_form} =
        cond do
          selected_value == "me" ->
            # Check if "Me" is already selected for another ticket
            me_already_selected =
              socket.assigns.tickets_requiring_registration
              |> Enum.any?(fn other_ticket ->
                other_ticket_id_str = to_string(other_ticket.id)

                other_ticket_id_str != ticket_id_str &&
                  (Map.get(tickets_for_me, other_ticket.id, false) ||
                     Map.get(tickets_for_me, other_ticket_id_str, false))
              end)

            if me_already_selected do
              # "Me" is already selected for another ticket, don't allow this selection
              Logger.warning(
                "select-ticket-attendee: Attempted to select 'Me' for ticket #{ticket_id_str}, but 'Me' is already selected for another ticket"
              )

              # Return unchanged state
              {tickets_for_me, selected_family_members, ticket_details_form}
            else
              # Select "Me" - first unset "Me" for any other tickets
              updated_tickets_for_me =
                socket.assigns.tickets_requiring_registration
                |> Enum.reduce(tickets_for_me, fn other_ticket, acc ->
                  other_ticket_id_str = to_string(other_ticket.id)
                  # Unset "Me" for all other tickets
                  if other_ticket_id_str != ticket_id_str do
                    Map.put(acc, other_ticket_id_str, false)
                  else
                    acc
                  end
                end)
                |> Map.put(ticket_id_str, true)

              # Clear selected family members for all tickets (since we're selecting "Me")
              updated_selected_family_members =
                socket.assigns.tickets_requiring_registration
                |> Enum.reduce(selected_family_members, fn other_ticket, acc ->
                  other_ticket_id_str = to_string(other_ticket.id)
                  Map.put(acc, other_ticket_id_str, nil)
                end)

              form_data = %{
                first_name: socket.assigns.current_user.first_name || "",
                last_name: socket.assigns.current_user.last_name || "",
                email: socket.assigns.current_user.email || ""
              }

              {
                updated_tickets_for_me,
                updated_selected_family_members,
                Map.put(ticket_details_form, ticket_id_str, form_data)
              }
            end

          selected_value == "other" ->
            # Select "Someone else" - clear selections and form data
            {
              Map.put(tickets_for_me, ticket_id_str, false),
              Map.put(selected_family_members, ticket_id_str, nil),
              # Clear form data for this ticket so fields show as empty
              Map.put(ticket_details_form, ticket_id_str, %{
                first_name: "",
                last_name: "",
                email: ""
              })
            }

          is_binary(selected_value) and
              String.starts_with?(selected_value, "family_") ->
            # Select a family member
            user_id_str = String.replace(selected_value, "family_", "")

            selected_user =
              Enum.find(family_members, fn u ->
                to_string(u.id) == user_id_str
              end)

            if selected_user do
              form_data = %{
                first_name: selected_user.first_name || "",
                last_name: selected_user.last_name || "",
                email: selected_user.email || ""
              }

              {
                Map.put(tickets_for_me, ticket_id_str, false),
                Map.put(
                  selected_family_members,
                  ticket_id_str,
                  selected_user.id
                ),
                Map.put(ticket_details_form, ticket_id_str, form_data)
              }
            else
              {tickets_for_me, selected_family_members, ticket_details_form}
            end

          true ->
            {tickets_for_me, selected_family_members, ticket_details_form}
        end

      {:noreply,
       socket
       |> assign(:ticket_details_form, updated_form)
       |> assign(:tickets_for_me, updated_tickets_for_me)
       |> assign(:selected_family_members, updated_selected_family_members)}
    else
      Logger.warning(
        "select-ticket-attendee: Missing ticket_id or selected_value. ticket_id=#{inspect(ticket_id)}, selected_value=#{inspect(selected_value)}, all_params=#{inspect(params)}"
      )

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "expand-ticket-registration",
        %{"ticket-index" => ticket_index_str},
        socket
      ) do
    ticket_index = String.to_integer(ticket_index_str)
    current_active = socket.assigns.active_ticket_index || 0

    # Toggle: if clicking the same ticket, collapse it; otherwise expand the new one
    new_active_index =
      if current_active == ticket_index, do: nil, else: ticket_index

    {:noreply, assign(socket, :active_ticket_index, new_active_index)}
  end

  @impl true
  def handle_event("update-registration-field", params, socket) do
    require Logger

    # LiveView sends ALL form fields when phx-change fires on a form
    # Extract all ticket fields from params and update them all at once
    # Find all input names that match our pattern: "ticket_{id}_{field}"
    ticket_fields =
      params
      |> Enum.filter(fn {key, _value} ->
        String.starts_with?(key, "ticket_") &&
          (String.ends_with?(key, "_first_name") ||
             String.ends_with?(key, "_last_name") ||
             String.ends_with?(key, "_email"))
      end)
      |> Enum.reduce(%{}, fn {name, val}, acc ->
        # Parse "ticket_{id}_{field}" pattern
        case Regex.run(~r/^ticket_(.+?)_(first_name|last_name|email)$/, name) do
          [_, ticket_id_str, field_str] ->
            # Group by ticket_id
            ticket_data = Map.get(acc, ticket_id_str, %{})
            # Convert known field names to atoms (regex already validates these)
            field_atom =
              case field_str do
                "first_name" -> :first_name
                "last_name" -> :last_name
                "email" -> :email
              end

            ticket_data = Map.put(ticket_data, field_atom, val || "")
            Map.put(acc, ticket_id_str, ticket_data)

          _ ->
            acc
        end
      end)

    if map_size(ticket_fields) > 0 do
      # Update the ticket_details_form assign with all fields for all tickets
      updated_form =
        ticket_fields
        |> Enum.reduce(socket.assigns.ticket_details_form, fn {ticket_id_str,
                                                               fields},
                                                              acc ->
          # Merge with existing form data to preserve other fields
          existing_data = Map.get(acc, ticket_id_str, %{})
          merged_data = Map.merge(existing_data, fields)
          Map.put(acc, ticket_id_str, merged_data)
        end)

      {:noreply, assign(socket, :ticket_details_form, updated_form)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update-donation-amount", params, socket) do
    tier_id = params["tier-id"] || params["tier_id"]

    # The JavaScript hook pushes the value using the input's name attribute
    # Try to get the value from params using the input name pattern
    # The name is "donation_amount_#{tier_id}"
    value =
      if tier_id do
        params["donation_amount_#{tier_id}"] ||
          params["donation_amount"] ||
          params["value"] ||
          params["val"] ||
          ""
      else
        # Fallback: try to find any donation_amount_* key
        params
        |> Map.keys()
        |> Enum.find(&String.starts_with?(&1, "donation_amount_"))
        |> case do
          nil -> ""
          key -> params[key] || ""
        end
      end

    # Parse the donation amount from the input string (e.g., "10.99" -> 1099 cents)
    donation_amount_cents = parse_donation_amount(value)

    updated_tickets =
      if donation_amount_cents > 0 and tier_id do
        # Add or update the donation amount in selected_tickets
        Map.put(socket.assigns.selected_tickets, tier_id, donation_amount_cents)
      else
        # Remove the donation tier from selected_tickets if amount is 0 or empty
        if tier_id,
          do: Map.delete(socket.assigns.selected_tickets, tier_id),
          else: socket.assigns.selected_tickets
      end

    {:noreply, assign(socket, :selected_tickets, updated_tickets)}
  end

  @impl true
  def handle_event(
        "set-donation-amount",
        %{"tier-id" => tier_id, "amount" => amount_str},
        socket
      ) do
    # Parse the amount string to integer (amount is in cents)
    case Integer.parse(amount_str) do
      {amount_cents, _} when amount_cents > 0 ->
        # Set the donation amount in selected_tickets (amount is already in cents)
        updated_tickets =
          Map.put(socket.assigns.selected_tickets, tier_id, amount_cents)

        {:noreply, assign(socket, :selected_tickets, updated_tickets)}

      _ ->
        # Invalid amount, don't update
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("decrease-ticket-quantity", %{"tier-id" => tier_id}, socket) do
    current_quantity =
      get_ticket_quantity(socket.assigns.selected_tickets, tier_id)

    new_quantity = max(0, current_quantity - 1)

    updated_tickets =
      if new_quantity == 0 do
        Map.delete(socket.assigns.selected_tickets, tier_id)
      else
        Map.put(socket.assigns.selected_tickets, tier_id, new_quantity)
      end

    {:noreply, assign(socket, :selected_tickets, updated_tickets)}
  end

  @impl true
  def handle_event("increase-ticket-quantity", %{"tier-id" => tier_id}, socket) do
    # Use cached ticket tiers instead of querying
    ticket_tier =
      socket.assigns.ticket_tiers
      |> Enum.find(&(&1.id == tier_id))

    # Only handle quantity changes for non-donation tiers
    if ticket_tier &&
         (ticket_tier.type == "donation" || ticket_tier.type == :donation) do
      {:noreply, socket}
    else
      current_quantity =
        get_ticket_quantity(socket.assigns.selected_tickets, tier_id)

      # Use cached availability data for faster checks
      if ticket_tier &&
           can_increase_quantity_cached?(
             ticket_tier,
             current_quantity,
             socket.assigns.selected_tickets,
             socket.assigns.event,
             socket.assigns.availability_data,
             socket.assigns.ticket_tiers
           ) do
        new_quantity = current_quantity + 1

        # Preserve all existing selected_tickets, only update this tier's quantity
        updated_tickets =
          Map.put(socket.assigns.selected_tickets, tier_id, new_quantity)

        {:noreply, assign(socket, :selected_tickets, updated_tickets)}
      else
        # Don't increase if we've reached the limit
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("proceed-to-checkout", _params, socket) do
    user_id = socket.assigns.current_user.id
    event_id = socket.assigns.event.id
    ticket_selections = socket.assigns.selected_tickets

    case Ysc.Tickets.create_ticket_order(user_id, event_id, ticket_selections) do
      {:ok, ticket_order} ->
        # Reload the ticket order with tickets and their tiers
        ticket_order_with_tickets =
          Ysc.Tickets.get_ticket_order(ticket_order.id)

        # Proceed directly to payment/free confirmation with registration integrated
        proceed_to_payment_or_free(socket, ticket_order_with_tickets)

      {:error, :overbooked} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Sorry, the event is now at capacity or the selected tickets are no longer available."
         )
         |> assign(:show_ticket_modal, false)}

      {:error, :event_capacity_exceeded} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Sorry, the event has reached its maximum capacity. The selected tickets are no longer available."
         )
         |> assign(:show_ticket_modal, false)}

      {:error, :stale_inventory} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "The ticket availability changed while you were booking. Please refresh and try again."
         )
         |> assign(:show_ticket_modal, false)}

      {:error, :event_not_available} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "This event is no longer available for ticket purchase."
         )
         |> assign(:show_ticket_modal, false)}

      {:error, :membership_required} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "An active membership is required to purchase tickets. Please ensure your membership is active and try again."
         )
         |> assign(:show_ticket_modal, false)}

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        # Handle changeset errors (e.g., membership validation in ticket changeset)
        error_message =
          case changeset.errors do
            [user_id: {"active membership required to purchase tickets", _}] ->
              "An active membership is required to purchase tickets. Please ensure your membership is active and try again."

            _ ->
              "There was an error processing your ticket order. Please try again."
          end

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign(:show_ticket_modal, false)}

      {:error, reason} ->
        require Logger

        Logger.error("Unexpected error creating ticket order",
          user_id: user_id,
          event_id: event_id,
          reason: reason
        )

        {:noreply,
         socket
         |> put_flash(
           :error,
           "There was an unexpected error processing your ticket order. Please try again."
         )
         |> assign(:show_ticket_modal, false)}
    end
  end

  def format_start_date(date) do
    Timex.format!(date, "{WDfull}, {Mfull} {D}")
  end

  defp event_body(%Event{rendered_details: nil} = event),
    do: Scrubber.scrub(event.raw_details, Scrubber.BasicHTML)

  defp event_body(%Event{} = event), do: event.rendered_details

  defp default_active_agenda([]), do: nil
  defp default_active_agenda(agendas), do: hd(agendas).id

  defp format_time(nil), do: nil
  defp format_time(""), do: nil

  defp format_time(time) when is_binary(time) do
    case Timex.parse(time, "%H:%M:%S", :strftime) do
      {:ok, time} -> time
      {:error, _} -> Timex.parse!(time, "%H:%M", :strftime)
    end
  end

  defp format_time(time), do: time

  defp format_start_end(start_time, end_time) do
    start_time = format_time(start_time)
    end_time = format_time(end_time)

    case {start_time, end_time} do
      {nil, nil} ->
        nil

      {nil, _} ->
        end_time

      {_, nil} ->
        Timex.format!(start_time, "{h12}:{m} {AM}")

      {start_time, end_time} ->
        "#{Timex.format!(start_time, "{h12}:{m} {AM}")} - #{Timex.format!(end_time, "{h12}:{m} {AM}")}"
    end
  end

  def date_for_add_to_cal(nil), do: nil

  def date_for_add_to_cal(dt) do
    Timex.format!(dt, "%Y-%m-%d", :strftime)
  end

  defp get_end_time_for_calendar(event) do
    case {event.start_time, event.end_time} do
      {start_time, nil} when not is_nil(start_time) ->
        # Add 3 hours to start_time when end_time is null
        Time.add(start_time, 3 * 60 * 60, :second)

      {_start_time, end_time} ->
        # Use the actual end_time if it exists
        end_time
    end
  end

  defp get_end_date_for_calendar(event) do
    case {event.start_time, event.end_time, event.end_date} do
      {start_time, nil, _end_date} when not is_nil(start_time) ->
        # Calculate end time and check if it goes past midnight
        calculated_end_time = Time.add(start_time, 3 * 60 * 60, :second)

        # If calculated end time is earlier than start time, it means we went past midnight
        if Time.compare(calculated_end_time, start_time) == :lt do
          # Add one day to the start date
          case event.start_date do
            %DateTime{} = start_date ->
              DateTime.add(start_date, 1, :day)

            _ ->
              # If start_date is not a DateTime, try to add a day using Date
              case event.start_date do
                %Date{} = start_date ->
                  Date.add(start_date, 1)

                _ ->
                  event.start_date
              end
          end
        else
          # End time is on the same day, use start_date
          event.start_date
        end

      {_start_time, _end_time, end_date} ->
        # Use the actual end_date if it exists
        end_date
    end
  end

  defp new_active_agenda(agenda_id, active_agenda_id, new_agendas)
       when agenda_id == active_agenda_id do
    default_active_agenda(new_agendas)
  end

  defp new_active_agenda(_, active_agenda_id, _) do
    active_agenda_id
  end

  # Helper function to add pricing information to events (same logic as Events module)
  defp add_pricing_info(event) do
    ticket_tiers = Events.list_ticket_tiers_for_event(event.id)
    pricing_info = calculate_event_pricing(ticket_tiers)
    Map.put(event, :pricing_info, pricing_info)
  end

  # Optimized version that uses pre-loaded ticket tiers
  defp add_pricing_info_from_tiers(event, ticket_tiers) do
    pricing_info = calculate_event_pricing(ticket_tiers)
    Map.put(event, :pricing_info, pricing_info)
  end

  # Get ticket tiers from pre-loaded list (sorted)
  defp get_ticket_tiers_from_list(ticket_tiers) do
    ticket_tiers
    |> Enum.sort_by(fn tier ->
      # Sort by status: available tiers first, then pre-sale tiers, then sold-out/ended tiers
      available = get_available_quantity(tier)
      on_sale = tier_on_sale?(tier)
      sale_ended = tier_sale_ended?(tier)

      cond do
        # Available tiers
        on_sale and available > 0 -> {0, tier.inserted_at}
        # Pre-sale tiers
        not on_sale and not sale_ended -> {1, tier.inserted_at}
        # Sale-ended tiers
        sale_ended -> {2, tier.inserted_at}
        # Sold-out tiers
        on_sale and available == 0 -> {3, tier.inserted_at}
        # Fallback
        true -> {4, tier.inserted_at}
      end
    end)
  end

  # Pre-compute event at capacity using cached data
  defp compute_event_at_capacity(event, ticket_tiers, availability_data) do
    # Filter out donation tiers - donations don't count toward "sold out" status
    non_donation_tiers =
      Enum.filter(ticket_tiers, fn tier ->
        tier_type = Map.get(tier, :type) || Map.get(tier, "type")
        tier_type != "donation" && tier_type != :donation
      end)

    # If there are no non-donation tiers, event is not sold out
    if Enum.empty?(non_donation_tiers) do
      false
    else
      # Filter out pre-sale tiers (tiers that haven't started selling yet)
      # We want to check tiers that are on sale OR have ended their sale
      relevant_tiers =
        Enum.filter(non_donation_tiers, fn tier ->
          tier_on_sale?(tier) || tier_sale_ended?(tier)
        end)

      # If there are no relevant tiers (all are pre-sale), check event capacity
      if Enum.empty?(relevant_tiers) do
        # Check event capacity if max_attendees is set
        case event.max_attendees do
          nil ->
            false

          max_attendees ->
            # Use availability_data if available, otherwise fall back to query
            total_sold =
              if availability_data do
                availability_data.event_capacity.current_attendees
              else
                Events.count_total_tickets_sold_for_event(event.id)
              end

            total_sold >= max_attendees
        end
      else
        # Check if all relevant non-donation tiers are sold out
        all_tiers_sold_out =
          Enum.all?(relevant_tiers, fn tier ->
            available = get_available_quantity(tier)
            available == 0
          end)

        # Also check event capacity if max_attendees is set
        event_at_capacity =
          case event.max_attendees do
            nil ->
              false

            max_attendees ->
              # Use availability_data if available, otherwise fall back to query
              total_sold =
                if availability_data do
                  availability_data.event_capacity.current_attendees
                else
                  Events.count_total_tickets_sold_for_event(event.id)
                end

              total_sold >= max_attendees
          end

        all_tiers_sold_out || event_at_capacity
      end
    end
  end

  # Get available capacity from cached availability data
  defp get_available_capacity_from_data(nil), do: :unlimited

  defp get_available_capacity_from_data(availability_data) do
    availability_data.event_capacity.available
  end

  # Compute sold percentage from cached data
  defp compute_sold_percentage(event, availability_data) do
    if event.max_attendees != nil && event.max_attendees > 0 do
      if availability_data do
        event_capacity = availability_data.event_capacity
        max_attendees = event_capacity.max_attendees

        if max_attendees != nil && max_attendees > 0 do
          current_attendees = event_capacity.current_attendees
          percentage = round(current_attendees / max_attendees * 100)
          min(percentage, 100)
        else
          nil
        end
      else
        nil
      end
    else
      nil
    end
  end

  # Calculate pricing display information for an event
  defp calculate_event_pricing([]) do
    %{display_text: "FREE", has_free_tiers: true, lowest_price: nil}
  end

  defp calculate_event_pricing(ticket_tiers) do
    # Check if there are any free tiers (handle both atom and string types)
    has_free_tiers =
      Enum.any?(ticket_tiers, &(&1.type == :free or &1.type == "free"))

    # Get the lowest price from paid tiers only (exclude donation tiers)
    # Filter out donation, free, and tiers with nil prices
    paid_tiers =
      Enum.filter(ticket_tiers, fn tier ->
        (tier.type == :paid or tier.type == "paid") && tier.price != nil
      end)

    case {has_free_tiers, paid_tiers} do
      {true, []} ->
        %{display_text: "FREE", has_free_tiers: true, lowest_price: nil}

      {true, _paid_tiers} ->
        # When there are both free and paid tiers, show "From $0.00"
        %{display_text: "From $0.00", has_free_tiers: true, lowest_price: nil}

      {false, []} ->
        %{display_text: "FREE", has_free_tiers: false, lowest_price: nil}

      {false, paid_tiers} ->
        lowest_price = Enum.min_by(paid_tiers, & &1.price.amount, fn -> nil end)

        # If there's only one paid tier, show the exact price instead of "From $X"
        display_text =
          if length(paid_tiers) == 1 do
            format_price(lowest_price.price)
          else
            "From #{format_price(lowest_price.price)}"
          end

        %{
          display_text: display_text,
          has_free_tiers: false,
          lowest_price: lowest_price
        }
    end
  end

  # Format price for display
  defp format_price(%Money{} = money) do
    Ysc.MoneyHelper.format_money!(money)
  end

  defp format_price(_), do: "$0.00"

  # Helper functions for ticket modal

  defp get_ticket_tier_by_id(_event_id, tier_id, ticket_tiers) do
    Enum.find(ticket_tiers, &(&1.id == tier_id))
  end

  defp get_ticket_quantity(selected_tickets, tier_id) do
    Map.get(selected_tickets, tier_id, 0)
  end

  defp get_available_quantity(ticket_tier) do
    quantity =
      Map.get(ticket_tier, :quantity) || Map.get(ticket_tier, "quantity")

    sold_count =
      Map.get(ticket_tier, :sold_tickets_count) ||
        Map.get(ticket_tier, "sold_tickets_count") || 0

    case quantity do
      # Unlimited
      nil ->
        :unlimited

      # Unlimited
      0 ->
        :unlimited

      qty ->
        available = qty - sold_count
        max(0, available)
    end
  end

  # Helper function to build ticket details list from registration data
  defp build_ticket_details_list(
         tickets_requiring_registration,
         tickets_for_me,
         ticket_details_form,
         current_user
       ) do
    tickets_requiring_registration
    |> Enum.map(fn ticket ->
      # Check both string and atom keys for tickets_for_me
      is_for_me =
        Map.get(tickets_for_me, ticket.id, false) ||
          Map.get(tickets_for_me, to_string(ticket.id), false)

      if is_for_me do
        # Use current user's details
        %{
          ticket_id: ticket.id,
          first_name: current_user.first_name,
          last_name: current_user.last_name,
          email: current_user.email
        }
      else
        # Use form data - ensure we convert ticket.id to string for consistent key lookup
        ticket_id_str = to_string(ticket.id)

        form_data =
          Map.get(ticket_details_form, ticket_id_str, %{}) ||
            Map.get(ticket_details_form, ticket.id, %{})

        %{
          ticket_id: ticket.id,
          first_name: get_form_value(form_data, :first_name) || "",
          last_name: get_form_value(form_data, :last_name) || "",
          email: get_form_value(form_data, :email) || ""
        }
      end
    end)
  end

  # Helper function to validate ticket details
  defp validate_ticket_details(
         tickets_requiring_registration,
         ticket_details_list,
         tickets_for_me,
         current_user
       ) do
    tickets_requiring_registration
    |> Enum.with_index()
    |> Enum.all?(fn {ticket, index} ->
      detail = Enum.at(ticket_details_list, index)
      # Check both string and atom keys for tickets_for_me
      is_for_me =
        Map.get(tickets_for_me, ticket.id, false) ||
          Map.get(tickets_for_me, to_string(ticket.id), false)

      if is_for_me do
        # For "for me" tickets, validate user's account has required fields
        user = current_user

        user.first_name != nil &&
          user.first_name != "" &&
          user.last_name != nil &&
          user.last_name != "" &&
          user.email != nil &&
          user.email != ""
      else
        # For form-filled tickets, validate form fields
        first_name = detail.first_name || ""
        last_name = detail.last_name || ""
        email = detail.email || ""

        first_name_valid = first_name != "" && String.trim(first_name) != ""
        last_name_valid = last_name != "" && String.trim(last_name) != ""
        email_valid = email != "" && String.trim(email) != ""

        first_name_valid && last_name_valid && email_valid
      end
    end)
  end

  # Helper function to save ticket details and process (free or paid)
  defp save_ticket_details_and_process(
         ticket_details_list,
         socket,
         on_success_fn
       ) do
    case Ysc.Events.create_ticket_details(ticket_details_list) do
      {:ok, _ticket_details} ->
        on_success_fn.()

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Failed to save registration details. Please try again."
         )}
    end
  end

  # Helper function to check if ticket detail is invalid
  defp ticket_detail_invalid?(detail, is_for_me, current_user) do
    if is_for_me do
      !user_fields_valid?(current_user)
    else
      !form_fields_valid?(detail)
    end
  end

  # Helper function to check if user fields are valid
  defp user_fields_valid?(user) do
    user.first_name != nil &&
      user.first_name != "" &&
      user.last_name != nil &&
      user.last_name != "" &&
      user.email != nil &&
      user.email != ""
  end

  # Helper function to check if form fields are valid
  defp form_fields_valid?(detail) do
    first_name = detail.first_name || ""
    last_name = detail.last_name || ""
    email = detail.email || ""

    first_name_valid = first_name != "" && String.trim(first_name) != ""
    last_name_valid = last_name != "" && String.trim(last_name) != ""
    email_valid = email != "" && String.trim(email) != ""

    first_name_valid && last_name_valid && email_valid
  end

  # Helper function to get is_for_me flag
  defp get_is_for_me_flag(tickets_for_me, ticket_id) do
    Map.get(tickets_for_me, ticket_id, false) ||
      Map.get(tickets_for_me, to_string(ticket_id), false)
  end

  # Helper function to find failing tickets
  defp find_failing_tickets(
         tickets_requiring_registration,
         ticket_details_list,
         tickets_for_me,
         current_user
       ) do
    tickets_requiring_registration
    |> Enum.with_index()
    |> Enum.filter(fn {ticket, index} ->
      detail = Enum.at(ticket_details_list, index)
      is_for_me = get_is_for_me_flag(tickets_for_me, ticket.id)
      ticket_detail_invalid?(detail, is_for_me, current_user)
    end)
  end

  # Helper function to build failing details
  defp build_failing_details(
         failing_tickets,
         ticket_details_list,
         tickets_for_me,
         ticket_details_form,
         current_user
       ) do
    failing_tickets
    |> Enum.map(fn {ticket, index} ->
      detail = Enum.at(ticket_details_list, index)
      is_for_me = Map.get(tickets_for_me, ticket.id, false)
      ticket_id_str = to_string(ticket.id)

      form_data =
        Map.get(ticket_details_form, ticket_id_str, %{}) ||
          Map.get(ticket_details_form, ticket.id, %{})

      %{
        ticket_id: ticket.id,
        is_for_me: is_for_me,
        detail: detail,
        form_data: form_data,
        user: if(is_for_me, do: current_user, else: nil)
      }
    end)
  end

  # Helper function to handle registration validation failure
  defp handle_registration_validation_failure(
         tickets_requiring_registration,
         ticket_details_list,
         tickets_for_me,
         ticket_details_form,
         current_user,
         socket,
         error_message
       ) do
    require Logger

    failing_tickets =
      find_failing_tickets(
        tickets_requiring_registration,
        ticket_details_list,
        tickets_for_me,
        current_user
      )

    failing_details =
      build_failing_details(
        failing_tickets,
        ticket_details_list,
        tickets_for_me,
        ticket_details_form,
        current_user
      )

    failing_info =
      failing_details
      |> Enum.map_join("; ", fn f ->
        "Ticket #{f.ticket_id}: is_for_me=#{f.is_for_me}, detail=#{inspect(f.detail)}, form_data=#{inspect(f.form_data)}"
      end)

    Logger.warning(
      "Registration validation failed. Failing tickets: #{failing_info}. All form_data: #{inspect(ticket_details_form)}. Tickets_for_me: #{inspect(tickets_for_me)}"
    )

    {:noreply,
     socket
     |> put_flash(
       :error,
       error_message
     )}
  end

  # Helper function to process free tickets
  defp process_free_tickets(socket) do
    # Process the free ticket order directly without payment
    case Ysc.Tickets.process_free_ticket_order(socket.assigns.ticket_order) do
      {:ok, updated_order} ->
        # Get the completed order with tickets for the completion screen
        order_with_tickets = Ysc.Tickets.get_ticket_order(updated_order.id)

        # Update user tickets for this event
        updated_user_tickets =
          Ysc.Tickets.list_user_tickets_for_event(
            socket.assigns.current_user.id,
            socket.assigns.event.id
          )

        {:noreply,
         socket
         |> assign(:show_free_ticket_confirmation, false)
         |> assign(:show_order_completion, true)
         |> assign(:ticket_order, order_with_tickets)
         |> assign(:user_tickets, updated_user_tickets)
         |> assign(:selected_tickets, %{})
         |> assign(:tickets_requiring_registration, [])
         |> assign(:ticket_details_form, %{})
         |> redirect(
           to: ~p"/orders/#{order_with_tickets.id}/confirmation?confetti=true"
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to confirm free tickets: #{reason}")
         |> assign(:show_free_ticket_confirmation, false)}
    end
  end

  # Helper function to get form value from either atom or string key
  defp get_form_value(form_data, field) when is_atom(field) do
    form_data[field] || form_data[to_string(field)]
  end

  # Helper function to process payment success
  defp process_payment_success(socket, payment_intent_id) do
    # Process the successful payment
    case Ysc.Tickets.StripeService.process_successful_payment(payment_intent_id) do
      {:ok, completed_order} ->
        # Get the completed order with tickets for the completion screen
        order_with_tickets = Ysc.Tickets.get_ticket_order(completed_order.id)

        # Update user tickets for this event
        updated_user_tickets =
          Ysc.Tickets.list_user_tickets_for_event(
            socket.assigns.current_user.id,
            socket.assigns.event.id
          )

        {:noreply,
         socket
         |> assign(:show_payment_modal, false)
         |> assign(:show_order_completion, true)
         |> assign(:ticket_order, order_with_tickets)
         |> assign(:user_tickets, updated_user_tickets)
         |> assign(:payment_intent, nil)
         |> assign(:selected_tickets, %{})
         |> assign(:tickets_requiring_registration, [])
         |> assign(:ticket_details_form, %{})
         |> redirect(
           to: ~p"/orders/#{order_with_tickets.id}/confirmation?confetti=true"
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Payment processed but there was an issue confirming your tickets. Please contact support."
         )
         |> assign(:show_payment_modal, false)}
    end
  end

  defp tier_on_sale?(ticket_tier) do
    now = DateTime.utc_now()

    start_date =
      Map.get(ticket_tier, :start_date) || Map.get(ticket_tier, "start_date")

    end_date =
      Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    # Check if sale has started
    sale_started =
      case start_date do
        # No start date means sale has started
        nil -> true
        sd -> DateTime.compare(now, sd) != :lt
      end

    # Check if sale has ended
    sale_ended =
      case end_date do
        # No end date means sale hasn't ended
        nil -> false
        ed -> DateTime.compare(now, ed) == :gt
      end

    sale_started && !sale_ended
  end

  defp tier_sale_ended?(ticket_tier) do
    now = DateTime.utc_now()

    end_date =
      Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    case end_date do
      nil -> false
      ed -> DateTime.compare(now, ed) == :gt
    end
  end

  defp days_until_sale_starts(ticket_tier) do
    case ticket_tier.start_date do
      # No start date
      nil ->
        nil

      start_date ->
        now = DateTime.utc_now()

        if DateTime.compare(now, start_date) == :lt do
          # Convert to dates and calculate calendar day difference
          start_date_only = DateTime.to_date(start_date)
          now_date_only = DateTime.to_date(now)

          # Calculate days difference using calendar days
          diff = Date.diff(start_date_only, now_date_only)
          max(0, diff)
        else
          # Already on sale
          nil
        end
    end
  end

  # Optimized version that uses cached availability data
  defp can_increase_quantity_cached?(
         ticket_tier,
         current_quantity,
         selected_tickets,
         event,
         availability_data,
         ticket_tiers,
         user_id \\ nil
       ) do
    if tier_on_sale?(ticket_tier) do
      if donation_tier?(ticket_tier) do
        true
      else
        check_availability_cached(
          availability_data,
          ticket_tier,
          current_quantity,
          selected_tickets,
          event,
          ticket_tiers,
          user_id
        )
      end
    else
      false
    end
  end

  defp donation_tier?(ticket_tier) do
    ticket_tier.type == "donation" || ticket_tier.type == :donation
  end

  defp check_availability_cached(
         availability,
         ticket_tier,
         current_quantity,
         selected_tickets,
         event,
         ticket_tiers,
         user_id
       )

  defp check_availability_cached(
         nil,
         ticket_tier,
         current_quantity,
         selected_tickets,
         event,
         ticket_tiers,
         user_id
       ) do
    # Fallback to query if cache is not available
    can_increase_quantity?(
      ticket_tier,
      current_quantity,
      selected_tickets,
      event,
      ticket_tiers,
      user_id
    )
  end

  defp check_availability_cached(
         availability,
         ticket_tier,
         current_quantity,
         selected_tickets,
         event,
         ticket_tiers,
         user_id
       ) do
    tier_info = Enum.find(availability.tiers, &(&1.tier_id == ticket_tier.id))
    event_capacity = availability.event_capacity

    tier_available =
      check_tier_availability(
        tier_info,
        current_quantity,
        ticket_tier.id,
        user_id
      )

    event_available =
      check_event_capacity(
        event_capacity,
        selected_tickets,
        event.id,
        ticket_tiers,
        user_id
      )

    tier_available && event_available
  end

  defp check_tier_availability(nil, _current_quantity, _tier_id, _user_id),
    do: false

  defp check_tier_availability(tier_info, current_quantity, tier_id, user_id) do
    if tier_info.available == :unlimited do
      true
    else
      # If user has reservations, add their reserved quantity to available
      user_available =
        if user_id do
          user_reserved = Events.get_user_reserved_quantity(tier_id, user_id)
          tier_info.available + user_reserved
        else
          tier_info.available
        end

      current_quantity < user_available
    end
  end

  defp check_event_capacity(
         event_capacity,
         selected_tickets,
         event_id,
         ticket_tiers,
         user_id
       ) do
    case event_capacity.available do
      :unlimited ->
        true

      available ->
        # If user has reservations, allow bypassing event capacity
        user_has_reservations =
          if user_id do
            Events.list_ticket_reservations_for_user(user_id, event_id) != []
          else
            false
          end

        if user_has_reservations do
          true
        else
          total_selected =
            calculate_total_selected_tickets(
              selected_tickets,
              event_id,
              ticket_tiers
            )

          total_selected + 1 <= available
        end
    end
  end

  # Original version kept for fallback
  defp can_increase_quantity?(
         ticket_tier,
         current_quantity,
         selected_tickets,
         event,
         ticket_tiers,
         user_id
       ) do
    if tier_on_sale?(ticket_tier) do
      if donation_tier?(ticket_tier) do
        true
      else
        check_availability_with_lock(
          ticket_tier,
          current_quantity,
          selected_tickets,
          event,
          ticket_tiers,
          user_id
        )
      end
    else
      false
    end
  end

  defp check_availability_with_lock(
         ticket_tier,
         current_quantity,
         selected_tickets,
         event,
         ticket_tiers,
         user_id
       ) do
    case Ysc.Tickets.BookingLocker.check_availability_with_lock(event.id) do
      {:ok, availability} ->
        tier_info =
          Enum.find(availability.tiers, &(&1.tier_id == ticket_tier.id))

        event_capacity = availability.event_capacity

        tier_available =
          check_tier_availability(
            tier_info,
            current_quantity,
            ticket_tier.id,
            user_id
          )

        event_available =
          check_event_capacity(
            event_capacity,
            selected_tickets,
            event.id,
            ticket_tiers,
            user_id
          )

        tier_available && event_available

      {:error, _} ->
        false
    end
  end

  # Original version kept for compatibility - now uses cached ticket_tiers
  defp calculate_total_selected_tickets(
         selected_tickets,
         event_id,
         ticket_tiers
       ) do
    selected_tickets
    |> Enum.reduce(0, fn {tier_id, quantity}, acc ->
      # Only count non-donation tiers towards event capacity
      ticket_tier = get_ticket_tier_by_id(event_id, tier_id, ticket_tiers)

      if ticket_tier &&
           (ticket_tier.type != "donation" && ticket_tier.type != :donation) do
        acc + quantity
      else
        acc
      end
    end)
  end

  defp has_any_tickets_selected?(selected_tickets) do
    selected_tickets
    |> Enum.any?(fn {_tier_id, quantity} -> quantity > 0 end)
  end

  defp event_in_past?(event) do
    now = DateTime.utc_now()

    # Combine the date and time properly
    event_datetime =
      case {event.start_date, event.start_time} do
        {%DateTime{} = date, %Time{} = time} ->
          # Convert DateTime to NaiveDateTime, then combine with time
          naive_date = DateTime.to_naive(date)
          date_part = NaiveDateTime.to_date(naive_date)
          naive_datetime = NaiveDateTime.new!(date_part, time)
          DateTime.from_naive!(naive_datetime, "Etc/UTC")

        {date, time} when not is_nil(date) and not is_nil(time) ->
          # Handle other date/time combinations
          NaiveDateTime.new!(date, time)
          |> DateTime.from_naive!("Etc/UTC")

        _ ->
          # Fallback to just the date if time is nil
          event.start_date
      end

    DateTime.compare(now, event_datetime) == :gt
  end

  defp calculate_total_price(
         selected_tickets,
         event_id,
         ticket_tiers,
         reservations_by_tier,
         current_user,
         user_reservations
       ) do
    pricing =
      calculate_pricing_with_discounts(
        selected_tickets,
        event_id,
        ticket_tiers,
        reservations_by_tier,
        current_user,
        user_reservations
      )

    format_price(pricing.total)
  end

  # Calculate pricing breakdown including discounts from reservations
  defp calculate_pricing_with_discounts(
         selected_tickets,
         event_id,
         ticket_tiers,
         _reservations_by_tier,
         current_user,
         user_reservations
       ) do
    user_id = if current_user, do: current_user.id, else: nil

    {subtotal, discount_total, tier_breakdowns} =
      selected_tickets
      |> Enum.reduce({Money.new(0, :USD), Money.new(0, :USD), []}, fn {tier_id,
                                                                       amount_or_quantity},
                                                                      {acc_subtotal,
                                                                       acc_discount,
                                                                       acc_breakdowns} ->
        ticket_tier = get_ticket_tier_by_id(event_id, tier_id, ticket_tiers)

        tier_reservations =
          if user_id,
            do: Enum.filter(user_reservations, &(&1.ticket_tier_id == tier_id)),
            else: []

        case ticket_tier.type do
          "free" ->
            breakdown = %{
              tier_id: tier_id,
              tier_name: ticket_tier.name,
              quantity: amount_or_quantity,
              original_price: Money.new(0, :USD),
              discount_amount: Money.new(0, :USD),
              final_price: Money.new(0, :USD),
              discount_percentage: nil
            }

            {acc_subtotal, acc_discount, [breakdown | acc_breakdowns]}

          "donation" ->
            dollars_decimal =
              Ysc.MoneyHelper.cents_to_dollars(amount_or_quantity)

            donation_amount = Money.new(:USD, dollars_decimal)

            new_subtotal =
              case Money.add(acc_subtotal, donation_amount) do
                {:ok, total} -> total
                {:error, _} -> acc_subtotal
              end

            breakdown = %{
              tier_id: tier_id,
              tier_name: ticket_tier.name,
              quantity: 1,
              original_price: donation_amount,
              discount_amount: Money.new(0, :USD),
              final_price: donation_amount,
              discount_percentage: nil
            }

            {new_subtotal, acc_discount, [breakdown | acc_breakdowns]}

          :donation ->
            dollars_decimal =
              Ysc.MoneyHelper.cents_to_dollars(amount_or_quantity)

            donation_amount = Money.new(:USD, dollars_decimal)

            new_subtotal =
              case Money.add(acc_subtotal, donation_amount) do
                {:ok, total} -> total
                {:error, _} -> acc_subtotal
              end

            breakdown = %{
              tier_id: tier_id,
              tier_name: ticket_tier.name,
              quantity: 1,
              original_price: donation_amount,
              discount_amount: Money.new(0, :USD),
              final_price: donation_amount,
              discount_percentage: nil
            }

            {new_subtotal, acc_discount, [breakdown | acc_breakdowns]}

          _ ->
            # Regular paid tiers: calculate with discounts
            original_tier_total =
              case Money.mult(ticket_tier.price, amount_or_quantity) do
                {:ok, total} -> total
                {:error, _} -> Money.new(0, :USD)
              end

            # Calculate discount for reserved tickets
            {tier_discount, discount_pct} =
              if user_id && tier_reservations != [] do
                calculate_tier_discount(
                  ticket_tier,
                  amount_or_quantity,
                  tier_reservations
                )
              else
                {Money.new(0, :USD), nil}
              end

            final_tier_total =
              case Money.sub(original_tier_total, tier_discount) do
                {:ok, total} -> total
                {:error, _} -> original_tier_total
              end

            new_subtotal =
              case Money.add(acc_subtotal, original_tier_total) do
                {:ok, total} -> total
                {:error, _} -> acc_subtotal
              end

            new_discount =
              case Money.add(acc_discount, tier_discount) do
                {:ok, total} -> total
                {:error, _} -> acc_discount
              end

            breakdown = %{
              tier_id: tier_id,
              tier_name: ticket_tier.name,
              quantity: amount_or_quantity,
              original_price: original_tier_total,
              discount_amount: tier_discount,
              final_price: final_tier_total,
              discount_percentage: discount_pct
            }

            {new_subtotal, new_discount, [breakdown | acc_breakdowns]}
        end
      end)

    total =
      case Money.sub(subtotal, discount_total) do
        {:ok, amount} -> amount
        _ -> subtotal
      end

    %{
      subtotal: subtotal,
      discount_amount: discount_total,
      total: total,
      tier_breakdowns: Enum.reverse(tier_breakdowns)
    }
  end

  # Calculate discount for a specific tier based on reservations
  defp calculate_tier_discount(tier, requested_quantity, reservations) do
    {total_discount, max_discount_pct, _covered_qty} =
      reservations
      |> Enum.reduce_while({Money.new(0, :USD), nil, 0}, fn reservation,
                                                            {discount_acc,
                                                             max_pct,
                                                             covered_qty} ->
        remaining_to_cover = requested_quantity - covered_qty

        if remaining_to_cover <= 0 do
          {:halt, {discount_acc, max_pct, covered_qty}}
        else
          reservation_qty = reservation.quantity

          reservation_discount_pct =
            reservation.discount_percentage || Decimal.new(0)

          if Decimal.gt?(reservation_discount_pct, 0) do
            tickets_from_reservation = min(reservation_qty, remaining_to_cover)

            reservation_tier_total =
              case Money.mult(tier.price, tickets_from_reservation) do
                {:ok, total} -> total
                {:error, _} -> Money.new(0, :USD)
              end

            discount_pct_decimal =
              Decimal.div(reservation_discount_pct, Decimal.new(100))

            discount_amount =
              case Money.mult(reservation_tier_total, discount_pct_decimal) do
                {:ok, discount} -> discount
                {:error, _} -> Money.new(0, :USD)
              end

            new_discount =
              case Money.add(discount_acc, discount_amount) do
                {:ok, total} -> total
                {:error, _} -> discount_acc
              end

            # Track the maximum discount percentage for display
            pct_float = Decimal.to_float(reservation_discount_pct)

            new_max_pct =
              if max_pct == nil || pct_float > max_pct,
                do: pct_float,
                else: max_pct

            new_covered = covered_qty + tickets_from_reservation

            if new_covered >= requested_quantity do
              {:halt, {new_discount, new_max_pct, new_covered}}
            else
              {:cont, {new_discount, new_max_pct, new_covered}}
            end
          else
            new_covered = covered_qty + min(reservation_qty, remaining_to_cover)
            {:cont, {discount_acc, max_pct, new_covered}}
          end
        end
      end)

    # Convert max_discount_pct from float to Decimal for consistency, or keep as float
    discount_pct = if max_discount_pct, do: max_discount_pct, else: nil

    {total_discount, discount_pct}
  end

  # Get reservation discount information for display
  defp get_reservation_discount_info(
         tier_id,
         reserved_quantity,
         _reservations_by_tier,
         user_reservations,
         tier_price
       ) do
    if reserved_quantity > 0 && user_reservations do
      # Find reservations for this tier
      tier_reservations =
        user_reservations
        |> Enum.filter(&(&1.ticket_tier_id == tier_id))

      # Get maximum discount percentage
      max_discount_pct =
        tier_reservations
        |> Enum.map(&(&1.discount_percentage || Decimal.new(0)))
        |> Enum.filter(&Decimal.gt?(&1, 0))
        |> Enum.reduce(nil, fn discount, acc ->
          if acc do
            if Decimal.gt?(discount, acc), do: discount, else: acc
          else
            discount
          end
        end)

      # Calculate discount savings
      discount_savings =
        if max_discount_pct && tier_price do
          original_total =
            case Money.mult(tier_price, reserved_quantity) do
              {:ok, total} -> total
              {:error, _} -> Money.new(0, :USD)
            end

          discount_pct_decimal = Decimal.div(max_discount_pct, Decimal.new(100))

          case Money.mult(original_total, discount_pct_decimal) do
            {:ok, discount} -> discount
            {:error, _} -> Money.new(0, :USD)
          end
        else
          Money.new(0, :USD)
        end

      %{
        discount_percentage:
          max_discount_pct && Decimal.to_float(max_discount_pct),
        discount_savings: discount_savings
      }
    else
      %{
        discount_percentage: nil,
        discount_savings: Money.new(0, :USD)
      }
    end
  end

  defp group_tickets_by_tier(tickets) do
    tickets
    |> Enum.group_by(& &1.ticket_tier.name)
    |> Enum.sort_by(fn {_tier_name, tickets} -> length(tickets) end, :desc)
  end

  defp group_tickets_by_order(tickets) do
    tickets
    |> Enum.filter(&(&1.ticket_order_id != nil))
    |> Enum.group_by(& &1.ticket_order_id)
    |> Enum.sort_by(
      fn {_order_id, order_tickets} ->
        # Sort by the most recent ticket's inserted_at (most recent orders first)
        List.first(order_tickets).inserted_at
      end,
      {:desc, DateTime}
    )
  end

  defp format_donation_amount(selected_tickets, tier_id) do
    case Map.get(selected_tickets, tier_id) do
      nil ->
        ""

      amount_cents when is_integer(amount_cents) ->
        # Convert cents to dollars and format
        dollars = amount_cents / 100
        :erlang.float_to_binary(dollars, [{:decimals, 2}])

      _ ->
        ""
    end
  end

  defp parse_donation_amount(value) when is_binary(value) do
    # Handle empty strings explicitly
    trimmed = String.trim(value)

    if trimmed == "" || trimmed == "0" || trimmed == "0.00" do
      0
    else
      # Remove any non-numeric characters except decimal point
      cleaned = trimmed |> String.replace(~r/[^\d.]/, "")

      if cleaned == "" do
        0
      else
        case Decimal.parse(cleaned) do
          {decimal, _} ->
            # Convert to cents (multiply by 100)
            decimal
            |> Decimal.mult(Decimal.new(100))
            |> Decimal.to_integer()

          :error ->
            0
        end
      end
    end
  end

  defp parse_donation_amount(_), do: 0

  # Helper function to get tickets that require registration
  defp get_tickets_requiring_registration(tickets) do
    tickets
    |> Enum.filter(fn ticket ->
      ticket.ticket_tier && ticket.ticket_tier.requires_registration == true
    end)
  end

  # Proceed to payment or free ticket confirmation after registration (if needed)
  defp proceed_to_payment_or_free(socket, ticket_order) do
    # Reload ticket order with tickets and their tiers
    ticket_order_with_tickets = Ysc.Tickets.get_ticket_order(ticket_order.id)

    # Check if any tickets require registration
    tickets_requiring_registration =
      get_tickets_requiring_registration(ticket_order_with_tickets.tickets)

    # Load family members for the current user
    family_members = Ysc.Accounts.get_family_group(socket.assigns.current_user)

    # Initialize ticket details form with existing registrations or empty values
    # Pre-fill first ticket with user details if it's defaulted to "for me"
    # For non-first tickets, leave form data empty (they default to "Someone else")
    ticket_details_form =
      tickets_requiring_registration
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {ticket, index}, acc ->
        ticket_detail = Ysc.Events.get_registration_for_ticket(ticket.id)
        ticket_id_str = to_string(ticket.id)

        # If this is the first ticket and it's defaulted to "for me", pre-fill with user details
        # For non-first tickets (index > 0), always use empty values (they default to "Someone else")
        form_data =
          if index == 0 && is_nil(ticket_detail) do
            %{
              first_name: socket.assigns.current_user.first_name || "",
              last_name: socket.assigns.current_user.last_name || "",
              email: socket.assigns.current_user.email || ""
            }
          else
            # For non-first tickets or tickets with existing details, use empty or existing values
            %{
              first_name:
                if(ticket_detail, do: ticket_detail.first_name, else: ""),
              last_name:
                if(ticket_detail, do: ticket_detail.last_name, else: ""),
              email: if(ticket_detail, do: ticket_detail.email, else: "")
            }
          end

        Map.put(acc, ticket_id_str, form_data)
      end)

    # Initialize tickets_for_me map
    # Smart default: First ticket defaults to "for me" for better UX
    tickets_for_me =
      tickets_requiring_registration
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {ticket, index}, acc ->
        # Default first ticket (index 0) to "for me"
        # Use string key for consistency with handler
        Map.put(acc, to_string(ticket.id), index == 0)
      end)

    # Initialize selected_family_members map (tracks which family member is selected for each ticket)
    selected_family_members =
      tickets_requiring_registration
      |> Enum.reduce(%{}, fn ticket, acc ->
        # Use string key for consistency with handler
        Map.put(acc, to_string(ticket.id), nil)
      end)

    # Initialize active_ticket_index for progressive disclosure (first ticket is active by default)
    active_ticket_index =
      if tickets_requiring_registration != [], do: 0, else: nil

    # Check if this is a free order (zero amount)
    if Money.zero?(ticket_order_with_tickets.total_amount) do
      # For free tickets, show confirmation modal instead of payment form
      # Update URL to reflect checkout state
      {:noreply,
       socket
       |> assign(:show_ticket_modal, false)
       |> assign(:show_free_ticket_confirmation, true)
       |> assign(:ticket_order, ticket_order_with_tickets)
       |> assign(
         :tickets_requiring_registration,
         tickets_requiring_registration
       )
       |> assign(:ticket_details_form, ticket_details_form)
       |> assign(:tickets_for_me, tickets_for_me)
       |> assign(:selected_family_members, selected_family_members)
       |> assign(:family_members, family_members)
       |> push_patch(
         to:
           ~p"/events/#{socket.assigns.event.id}?checkout=free&order_id=#{ticket_order_with_tickets.id}"
       )}
    else
      # For paid tickets, create Stripe payment intent
      case Ysc.Tickets.StripeService.create_payment_intent(
             ticket_order_with_tickets,
             customer_id: socket.assigns.current_user.stripe_id
           ) do
        {:ok, payment_intent} ->
          # Show payment form with Stripe Elements
          # Update URL to reflect checkout state
          {:noreply,
           socket
           |> assign(:show_ticket_modal, false)
           |> assign(:show_payment_modal, true)
           |> assign(:checkout_expired, false)
           |> assign(:payment_intent, payment_intent)
           |> assign(:ticket_order, ticket_order_with_tickets)
           |> assign(
             :tickets_requiring_registration,
             tickets_requiring_registration
           )
           |> assign(:ticket_details_form, ticket_details_form)
           |> assign(:tickets_for_me, tickets_for_me)
           |> assign(:selected_family_members, selected_family_members)
           |> assign(:family_members, family_members)
           |> assign(:active_ticket_index, active_ticket_index)
           |> assign(:payment_redirect_in_progress, false)
           |> push_patch(
             to:
               ~p"/events/#{socket.assigns.event.id}?checkout=payment&order_id=#{ticket_order_with_tickets.id}"
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to create payment: #{reason}")
           |> assign(:show_ticket_modal, false)
           |> push_patch(to: ~p"/events/#{socket.assigns.event.id}")}
      end
    end
  end

  # Helper function to calculate donation amount for a single ticket
  defp get_donation_amount_for_single_ticket(ticket) do
    if ticket.ticket_order do
      # Reload the ticket order with all tickets to calculate donation amount
      ticket_order = Ysc.Tickets.get_ticket_order(ticket.ticket_order.id)

      if ticket_order && ticket_order.tickets do
        # Calculate non-donation ticket costs
        non_donation_total =
          ticket_order.tickets
          |> Enum.filter(fn t ->
            t.ticket_tier.type != "donation" && t.ticket_tier.type != :donation
          end)
          |> Enum.reduce(Money.new(0, :USD), fn t, acc ->
            case t.ticket_tier.price do
              nil ->
                acc

              price when is_struct(price, Money) ->
                case Money.add(acc, price) do
                  {:ok, new_total} -> new_total
                  _ -> acc
                end

              _ ->
                acc
            end
          end)

        # Calculate donation total
        donation_total =
          case Money.sub(ticket_order.total_amount, non_donation_total) do
            {:ok, amount} -> amount
            _ -> Money.new(0, :USD)
          end

        # Count donation tickets
        donation_tickets =
          ticket_order.tickets
          |> Enum.filter(fn t ->
            t.ticket_tier.type == "donation" || t.ticket_tier.type == :donation
          end)

        donation_count = length(donation_tickets)

        if donation_count > 0 && Money.positive?(donation_total) do
          # Calculate per-ticket donation amount
          per_ticket_amount =
            case Money.div(donation_total, donation_count) do
              {:ok, amount} -> amount
              _ -> Money.new(0, :USD)
            end

          # Format and display
          case Money.to_string(per_ticket_amount) do
            {:ok, amount} -> amount
            _ -> "Donation"
          end
        else
          "Donation"
        end
      else
        "Donation"
      end
    else
      "Donation"
    end
  end

  # Check if event is "selling fast" (based on recent ticket sales)

  # Check if event is currently "live" (happening now in PST)
  defp event_live?(event) do
    if event.start_date != nil && event.start_time != nil &&
         event.end_time != nil do
      # Get current time in PST
      now_pst = DateTime.now!("America/Los_Angeles")
      now_time_pst = DateTime.to_time(now_pst)
      today_pst = DateTime.to_date(now_pst)

      # Get event date in PST
      event_date_pst =
        case event.start_date do
          %DateTime{} = dt ->
            dt_pst = DateTime.shift_zone!(dt, "America/Los_Angeles")
            DateTime.to_date(dt_pst)

          %Date{} = d ->
            d

          _ ->
            nil
        end

      # Check if event is happening today
      if event_date_pst == today_pst do
        # Get start and end times
        start_time = format_time(event.start_time)
        end_time = format_time(event.end_time)

        case {start_time, end_time} do
          {%Time{} = start, %Time{} = end_time_val} ->
            # Check if current time is between start and end times
            Time.compare(now_time_pst, start) != :lt &&
              Time.compare(now_time_pst, end_time_val) != :gt

          _ ->
            false
        end
      else
        false
      end
    else
      false
    end
  end

  # Check if an agenda item is currently happening (between start_time and end_time)
  # All comparisons are done in PST timezone since events are in PST
  defp agenda_item_current?(agenda_item, event) do
    # Only check if event is happening today and has start_date/start_time
    if event.start_date != nil && event.start_time != nil &&
         agenda_item.start_time != nil && agenda_item.end_time != nil do
      # Get current time in PST
      now_pst = DateTime.now!("America/Los_Angeles")
      now_time_pst = DateTime.to_time(now_pst)
      today_pst = DateTime.to_date(now_pst)

      # Get event date in PST (convert DateTime to PST first if needed, then get Date)
      event_date_pst =
        case event.start_date do
          %DateTime{} = dt ->
            # Convert UTC DateTime to PST, then get the date
            dt_pst = DateTime.shift_zone!(dt, "America/Los_Angeles")
            DateTime.to_date(dt_pst)

          %Date{} = d ->
            # Date structs don't have timezone, use as-is
            d

          _ ->
            nil
        end

      # Only show pulse if event is happening today (in PST)
      if event_date_pst == today_pst do
        # Check if current time (in PST) is between agenda item start and end times
        # Agenda item times are stored as Time structs and are in PST context
        Time.compare(now_time_pst, agenda_item.start_time) != :lt &&
          Time.compare(now_time_pst, agenda_item.end_time) != :gt
      else
        false
      end
    else
      false
    end
  end
end
