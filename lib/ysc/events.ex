defmodule Ysc.Events do
  @moduledoc """
  Context module for managing events and tickets.

  Provides functions for creating, updating, and querying events, ticket tiers,
  tickets, and related data.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Events.Agenda
  alias Ysc.Events.AgendaItem
  alias Ysc.Events.Event
  alias Ysc.Events.FaqQuestion
  alias Ysc.Events.TicketTier
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketDetail
  alias Ysc.Events.TicketReservation
  alias Ysc.Events.EventNotificationSubscription
  alias Ysc.Events.EventUpdate
  alias Ysc.Accounts.User
  alias Ysc.StaffPreview

  def subscribe() do
    Phoenix.PubSub.subscribe(Ysc.PubSub, topic())
  end

  @doc """
  Fetch an event by its ID.
  """
  def get_event!(id) do
    Repo.get!(Event, id)
  end

  @doc """
  Fetch an event by its ID, returns nil if not found.
  """
  def get_event(id) do
    Repo.get(Event, id)
  end

  @doc """
  Fetch an event by its reference ID.
  """
  def get_event_by_reference!(reference_id) do
    Repo.get_by!(Event, reference_id: reference_id)
  end

  @doc """
  Fetch an event by its reference ID, returns nil if not found.
  """
  def get_event_by_reference(reference_id) do
    Repo.get_by(Event, reference_id: reference_id)
  end

  @public_event_states [:published, :cancelled]
  @staff_preview_event_states [:draft, :scheduled]

  @doc """
  Returns an event visible on public pages (published or cancelled), or nil.
  """
  def get_public_event(id) do
    from(e in Event, where: e.id == ^id and e.state in ^@public_event_states)
    |> Repo.one()
  end

  @doc """
  Returns an event visible on public pages by reference id, or nil.
  """
  def get_public_event_by_reference(reference_id) do
    from(e in Event,
      where:
        e.reference_id == ^reference_id and e.state in ^@public_event_states
    )
    |> Repo.one()
  end

  @doc """
  Returns an event for the public event page.

  Published and cancelled events are visible to everyone. Admins and volunteers may
  also preview draft and scheduled events on the public page layout.
  """
  def get_event_for_page(id, viewer) do
    case get_public_event(id) do
      %Event{} = event ->
        event

      nil ->
        get_staff_preview_event(id, viewer)
    end
  end

  @doc """
  Returns an event by reference id for the public event page.

  See `get_event_for_page/2`.
  """
  def get_event_for_page_by_reference(reference_id, viewer) do
    case get_public_event_by_reference(reference_id) do
      %Event{} = event ->
        event

      nil ->
        get_staff_preview_event_by_reference(reference_id, viewer)
    end
  end

  defp get_staff_preview_event(id, viewer) do
    if StaffPreview.staff_content_preview?(viewer) do
      from(e in Event,
        where: e.id == ^id and e.state in ^@staff_preview_event_states
      )
      |> Repo.one()
    end
  end

  defp get_staff_preview_event_by_reference(reference_id, viewer) do
    if StaffPreview.staff_content_preview?(viewer) do
      from(e in Event,
        where:
          e.reference_id == ^reference_id and
            e.state in ^@staff_preview_event_states
      )
      |> Repo.one()
    end
  end

  @doc """
  Loads an event with pricing, ticket tiers, and cover image for TV/Roku poster rendering.
  """
  def get_event_for_tv_poster(id) do
    case Repo.get(Event, id) do
      nil -> nil
      %Event{} = event -> Ysc.Events.EventPricingCache.enrich_event(event)
    end
  end

  @doc """
  List all events, optionally with filters.
  """
  def list_events(filters \\ %{}) do
    Event
    |> apply_filters(filters)
    |> Repo.all()
    |> Repo.preload(:organizer)
  end

  def list_events_paginated(params, opts \\ []) do
    opts = normalize_list_events_opts(opts)
    date_from = Keyword.get(opts, :date_from, "")
    date_to = Keyword.get(opts, :date_to, "")
    search_term = Keyword.get(opts, :search_term)
    tab = opts |> Keyword.get(:tab, :all) |> normalize_tab()

    query =
      if search_term in [nil, ""] do
        Event
        |> where([e], e.state not in ["deleted"])
        |> maybe_filter_tab(tab)
        |> maybe_filter_start_date_from(date_from)
        |> maybe_filter_start_date_to(date_to)
        |> join(:left, [e], u in assoc(e, :organizer), as: :organizer)
        |> preload([organizer: o], organizer: o)
      else
        fuzzy_search_event(search_term)
        |> maybe_filter_tab(tab)
        |> maybe_filter_start_date_from(date_from)
        |> maybe_filter_start_date_to(date_to)
      end

    case query
         |> Flop.validate_and_run(params, for: Event) do
      {:ok, {events, meta}} ->
        events = enrich_events_with_capacity(events)
        {:ok, {events, meta}}

      error ->
        error
    end
  end

  defp maybe_filter_tab(query, :upcoming) do
    now = DateTime.utc_now()

    query
    |> where([e], e.state not in ["draft"])
    |> where([e], e.start_date > ^now)
  end

  defp maybe_filter_tab(query, :drafts) do
    where(query, [e], e.state == "draft")
  end

  defp maybe_filter_tab(query, :past) do
    now = DateTime.utc_now()

    query
    |> where([e], e.state not in ["draft"])
    |> where([e], e.start_date <= ^now)
  end

  defp maybe_filter_tab(query, _), do: query

  @known_tabs ~w(upcoming drafts past all)
  defp normalize_tab(tab) when is_atom(tab), do: tab

  defp normalize_tab(tab) when is_binary(tab) and tab in @known_tabs,
    do: String.to_existing_atom(tab)

  defp normalize_tab(_), do: :all

  defp enrich_events_with_capacity([]), do: []

  defp enrich_events_with_capacity(events) do
    event_ids = Enum.map(events, & &1.id)
    ticket_tiers_by_event = batch_load_ticket_tiers(event_ids)

    registrations_by_event =
      batch_count_tickets_sold_excluding_donations(event_ids)

    Enum.map(events, fn event ->
      enrich_single_event_capacity(
        event,
        ticket_tiers_by_event,
        registrations_by_event
      )
    end)
  end

  defp enrich_single_event_capacity(
         %Event{} = event,
         ticket_tiers_by_event,
         registrations_by_event
       ) do
    tiers = Map.get(ticket_tiers_by_event, event.id, [])
    registrations = Map.get(registrations_by_event, event.id, 0)

    event_for_capacity = %Event{event | ticket_tiers: tiers}
    capacity = calculate_event_capacity(event_for_capacity)

    %Event{
      event
      | capacity_info: %{registrations: registrations, capacity: capacity}
    }
  end

  defp calculate_event_capacity(event) do
    event_capacity = event.max_attendees

    # Get non-donation ticket tiers
    non_donation_tiers =
      Enum.reject(event.ticket_tiers || [], fn tier ->
        tier.type == :donation or tier.type == "donation"
      end)

    # Calculate sum of tier capacities
    tier_capacity = calculate_tier_capacity_sum(non_donation_tiers)

    # Determine actual capacity
    case {event_capacity, tier_capacity} do
      {nil, :unlimited} -> :unlimited
      {nil, tier_cap} -> tier_cap
      {event_cap, :unlimited} -> event_cap
      {event_cap, tier_cap} -> min(event_cap, tier_cap)
    end
  end

  defp calculate_tier_capacity_sum([]), do: :unlimited

  defp calculate_tier_capacity_sum(tiers) do
    # If any tier is unlimited (nil or 0 quantity), the event has unlimited capacity
    # Otherwise, sum up all tier quantities
    has_unlimited =
      Enum.any?(tiers, fn tier ->
        tier.quantity == nil or tier.quantity == 0
      end)

    if has_unlimited do
      :unlimited
    else
      Enum.reduce(tiers, 0, fn tier, acc ->
        acc + (tier.quantity || 0)
      end)
    end
  end

  defp normalize_list_events_opts(search_term)
       when is_binary(search_term) or is_nil(search_term),
       do: [search_term: search_term]

  defp normalize_list_events_opts(opts) when is_list(opts), do: opts

  defp maybe_filter_start_date_from(query, ""), do: query

  defp maybe_filter_start_date_from(query, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        where(query, [e], e.start_date >= ^datetime)

      _ ->
        query
    end
  end

  defp maybe_filter_start_date_to(query, ""), do: query

  defp maybe_filter_start_date_to(query, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
        where(query, [e], e.start_date <= ^datetime)

      _ ->
        query
    end
  end

  defp fuzzy_search_event(search_term) do
    search_like = "%#{search_term}%"

    from(e in Event,
      left_join: u in assoc(e, :organizer),
      as: :organizer,
      where:
        e.state not in ["deleted"] and
          (fragment("SIMILARITY(?, ?) > 0.2", e.title, ^search_term) or
             ilike(e.title, ^search_like) or
             ilike(coalesce(e.description, ""), ^search_like) or
             ilike(coalesce(e.reference_id, ""), ^search_like) or
             (not is_nil(u.id) and
                (fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
                   fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term) or
                   ilike(u.first_name, ^search_like) or
                   ilike(u.last_name, ^search_like)))),
      preload: [organizer: u]
    )
  end

  @doc """
  Insert a new event into the database.
  """
  @dialyzer {:nowarn_function, create_event: 1}
  def create_event(attrs \\ %{}) do
    organizer_id =
      Map.get(attrs, :organizer_id) || Map.get(attrs, "organizer_id")

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:event, Event.changeset(%Event{}, attrs))

    multi =
      if organizer_id do
        Ecto.Multi.run(multi, :add_host, fn repo, %{event: event} ->
          case repo.get(User, organizer_id) do
            nil ->
              {:ok, nil}

            organizer ->
              event
              |> repo.preload(:hosts)
              |> Ecto.Changeset.change()
              |> Ecto.Changeset.put_assoc(:hosts, [organizer])
              |> repo.update()
          end
        end)
      else
        multi
      end

    case Repo.transaction(multi) do
      {:ok, %{event: event}} ->
        invalidate_event_caches()
        broadcast(%Ysc.MessagePassingEvents.EventAdded{event: event})
        {:ok, event}

      {:error, :event, changeset, _} ->
        {:error, changeset}

      {:error, :add_host, error, _} ->
        {:error, error}
    end
  end

  @doc """
  List hosts for an event, preloaded from the join table.
  """
  def list_event_hosts(%Event{} = event) do
    event
    |> Repo.preload(hosts: :current_avatar)
    |> then(& &1.hosts)
  end

  @doc """
  List hosts for an event by event_id, without needing a full Event struct.
  """
  def list_event_hosts_by_event_id(event_id) do
    from(u in User,
      join: eh in "event_hosts",
      on: eh.user_id == u.id,
      where: eh.event_id == type(^event_id, Ecto.ULID),
      order_by: [asc: eh.user_id],
      preload: [:current_avatar]
    )
    |> Repo.all()
  end

  @doc """
  Add a user as a host of an event. Silently succeeds if already a host.
  Uses force-reload and optimistic locking to prevent lost concurrent updates.
  """
  def add_event_host(%Event{} = event, %User{} = user) do
    event = Repo.get!(Event, event.id) |> Repo.preload(:hosts, force: true)
    hosts = Enum.uniq_by([user | event.hosts], & &1.id)

    result =
      event
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.optimistic_lock(:lock_version)
      |> Ecto.Changeset.put_assoc(:hosts, hosts)
      |> Repo.update()

    case result do
      {:ok, updated_event} ->
        broadcast(%Ysc.MessagePassingEvents.EventHostsUpdated{
          event_id: updated_event.id
        })

        {:ok, updated_event}

      error ->
        error
    end
  end

  @doc """
  Remove a user from the hosts of an event.
  Uses force-reload and optimistic locking to prevent lost concurrent updates.
  """
  def remove_event_host(%Event{} = event, user_id) do
    event = Repo.get!(Event, event.id) |> Repo.preload(:hosts, force: true)
    hosts = Enum.reject(event.hosts, &(&1.id == user_id))

    result =
      event
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.optimistic_lock(:lock_version)
      |> Ecto.Changeset.put_assoc(:hosts, hosts)
      |> Repo.update()

    case result do
      {:ok, updated_event} ->
        broadcast(%Ysc.MessagePassingEvents.EventHostsUpdated{
          event_id: updated_event.id
        })

        {:ok, updated_event}

      error ->
        error
    end
  end

  @doc """
  Deep-copy an event as a new draft, including agendas (with items), ticket tiers, and FAQ questions.
  The new event is unpublished (state: :draft). No tickets are copied.
  Returns `{:ok, new_event}` or `{:error, reason}`.
  """
  def copy_event(%Event{} = event) do
    event =
      Repo.preload(event, [
        :ticket_tiers,
        :faq_questions,
        agendas: :agenda_items
      ])

    event_attrs = %{
      state: :draft,
      published_at: nil,
      publish_at: nil,
      organizer_id: event.organizer_id,
      title: "Copy of #{event.title}",
      description: event.description,
      max_attendees: event.max_attendees,
      unlimited_capacity:
        event.max_attendees == nil or event.max_attendees == 0,
      age_restriction: event.age_restriction,
      raw_details: event.raw_details,
      rendered_details: event.rendered_details,
      image_id: event.image_id,
      location_name: event.location_name,
      address: event.address,
      latitude: event.latitude,
      longitude: event.longitude,
      place_id: event.place_id,
      partiful_link: event.partiful_link,
      tickets_tbd: event.tickets_tbd,
      start_date: event.start_date,
      start_time: event.start_time,
      end_date: event.end_date,
      end_time: event.end_time
    }

    result =
      Repo.transaction(fn ->
        case %Event{}
             |> Event.changeset(event_attrs)
             |> Repo.insert() do
          {:ok, new_event} ->
            Enum.each(event.agendas || [], fn agenda ->
              agenda_cs =
                %Agenda{}
                |> Agenda.changeset(%{
                  event_id: new_event.id,
                  title: agenda.title
                })
                |> Ecto.Changeset.put_change(:position, agenda.position || 0)

              {:ok, new_agenda} = Repo.insert(agenda_cs)

              Enum.each(agenda.agenda_items || [], fn item ->
                item_cs =
                  %AgendaItem{}
                  |> AgendaItem.changeset(%{
                    agenda_id: new_agenda.id,
                    title: item.title,
                    description: item.description,
                    start_time: item.start_time,
                    end_time: item.end_time
                  })
                  |> Ecto.Changeset.put_change(:position, item.position || 0)

                Repo.insert!(item_cs)
              end)
            end)

            Enum.each(event.ticket_tiers || [], fn tier ->
              tier_attrs = %{
                event_id: new_event.id,
                name: tier.name,
                description: tier.description,
                type: tier.type,
                price: tier.price,
                quantity: tier.quantity,
                unlimited_quantity: tier.quantity == nil or tier.quantity == 0,
                requires_registration: tier.requires_registration,
                start_date: tier.start_date,
                end_date: tier.end_date
              }

              %TicketTier{}
              |> TicketTier.changeset(tier_attrs)
              |> Repo.insert!()
            end)

            Enum.each(event.faq_questions || [], fn faq ->
              %FaqQuestion{}
              |> Ecto.Changeset.change(%{
                event_id: new_event.id,
                question: faq.question,
                answer: faq.answer
              })
              |> Repo.insert!()
            end)

            new_event

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, new_event} ->
        invalidate_event_caches()
        broadcast(%Ysc.MessagePassingEvents.EventAdded{event: new_event})
        {:ok, new_event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update an existing event with new attributes.
  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
    |> finalize_event_update()
  end

  @doc """
  Updates editorial event fields from the admin editor (auto-save / validate).

  Ignores mass-assigned publish controls (`state`, `published_at`, `publish_at`,
  `organizer_id`). Use `publish_event/1`, `unpublish_event/1`, and similar for
  lifecycle transitions.
  """
  def update_event_editor(%Event{} = event, attrs) do
    event
    |> Event.editor_changeset(attrs)
    |> Repo.update()
    |> finalize_event_update()
  end

  defp finalize_event_update(result) do
    case result do
      {:ok, event} ->
        invalidate_event_caches()
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})
        maybe_reschedule_event_photo_reminder(event)
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Delete an event from the database.
  """
  def delete_event(%Event{} = event) do
    event
    |> Event.changeset(%{state: :deleted, published_at: nil})
    |> Repo.update()
    |> case do
      {:ok, event} ->
        invalidate_event_caches()
        broadcast(%Ysc.MessagePassingEvents.EventDeleted{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Count the number of published events.
  """
  def count_published_events do
    Event
    |> where(state: "published")
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Count the number of upcoming events without loading all event data.
  """
  def count_upcoming_events do
    Ysc.Events.EventListCache.count_upcoming_events()
  end

  def count_upcoming_events_from_db do
    from(e in Event,
      where: e.start_date > ^DateTime.utc_now(),
      where: e.state in [:published, :cancelled]
    )
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Check if there are more past events beyond a given limit without loading full event data.
  Uses a simple count query to avoid loading associations.
  """
  def has_more_past_events?(limit) do
    # Count events and check if there are more than the limit
    from(e in Event,
      where: e.start_date <= ^DateTime.utc_now(),
      where: e.state in [:published, :cancelled],
      select: count(e.id)
    )
    |> Repo.one() > limit
  end

  @doc """
  Fetch events with upcoming start dates, optionally limited.
  Optimized to batch load ticket tiers and ticket counts to avoid N+1 queries.
  """
  def list_upcoming_events(limit \\ 50) do
    Ysc.Events.EventListCache.list_upcoming_events(limit)
  end

  def list_upcoming_events_from_db(limit \\ 50) do
    three_days_ago = DateTime.add(DateTime.utc_now(), -3, :day)

    events =
      from(e in Event,
        where: e.start_date > ^DateTime.utc_now(),
        where: e.state in [:published, :cancelled],
        left_join: t in Ticket,
        on:
          t.event_id == e.id and t.status == :confirmed and
            t.inserted_at >= ^three_days_ago,
        left_join: tt in TicketTier,
        on: t.ticket_tier_id == tt.id and tt.type != :donation,
        group_by: e.id,
        select: %{
          id: e.id,
          reference_id: e.reference_id,
          state: e.state,
          published_at: e.published_at,
          publish_at: e.publish_at,
          organizer_id: e.organizer_id,
          title: e.title,
          description: e.description,
          max_attendees: e.max_attendees,
          age_restriction: e.age_restriction,
          show_participants: e.show_participants,
          raw_details: e.raw_details,
          rendered_details: e.rendered_details,
          image_id: e.image_id,
          start_date: e.start_date,
          start_time: e.start_time,
          end_date: e.end_date,
          end_time: e.end_time,
          location_name: e.location_name,
          address: e.address,
          latitude: e.latitude,
          longitude: e.longitude,
          place_id: e.place_id,
          partiful_link: e.partiful_link,
          tickets_tbd: e.tickets_tbd,
          lock_version: e.lock_version,
          inserted_at: e.inserted_at,
          updated_at: e.updated_at,
          recent_tickets_count: count(t.id),
          selling_fast: fragment("count(?) >= 5", t.id)
        },
        order_by: [
          # First sort by state: non-cancelled events first, cancelled events last
          asc: fragment("CASE WHEN ? = 'cancelled' THEN 1 ELSE 0 END", e.state),
          # Then sort by start_date for non-cancelled events
          asc: e.start_date,
          # Finally sort by start_time for events on the same date
          asc: e.start_time
        ],
        limit: ^limit
      )
      |> Repo.all()

    # Batch load all ticket tiers, ticket counts, and images for all events at once
    add_pricing_info_batch(events)
  end

  @doc """
  Paginated list of upcoming published/cancelled events for the mobile API.

  Accepts a map with optional keys:
    - "page"      – 1-based page number (default 1)
    - "page_size" – records per page (default 20, max 100)

  Returns `{events, meta}` where meta contains pagination details and each
  event is enriched with pricing_info, ticket_tiers, ticket_count, and image
  (same shape as `list_upcoming_events/1`).
  """
  def list_upcoming_events_paginated(params \\ %{}) do
    page = parse_page_param(params, "page", 1)
    page_size = parse_page_param(params, "page_size", 20) |> min(100)
    offset = (page - 1) * page_size

    now = DateTime.utc_now()
    three_days_ago = DateTime.add(now, -3, :day)

    total_count =
      from(e in Event,
        where: e.start_date > ^now,
        where: e.state in [:published, :cancelled],
        select: count(e.id)
      )
      |> Repo.one()

    events =
      from(e in Event,
        where: e.start_date > ^now,
        where: e.state in [:published, :cancelled],
        left_join: t in Ticket,
        on:
          t.event_id == e.id and t.status == :confirmed and
            t.inserted_at >= ^three_days_ago,
        left_join: tt in TicketTier,
        on: t.ticket_tier_id == tt.id and tt.type != :donation,
        group_by: e.id,
        select: %{
          id: e.id,
          reference_id: e.reference_id,
          state: e.state,
          published_at: e.published_at,
          publish_at: e.publish_at,
          organizer_id: e.organizer_id,
          title: e.title,
          description: e.description,
          max_attendees: e.max_attendees,
          age_restriction: e.age_restriction,
          show_participants: e.show_participants,
          raw_details: e.raw_details,
          rendered_details: e.rendered_details,
          image_id: e.image_id,
          start_date: e.start_date,
          start_time: e.start_time,
          end_date: e.end_date,
          end_time: e.end_time,
          location_name: e.location_name,
          address: e.address,
          latitude: e.latitude,
          longitude: e.longitude,
          place_id: e.place_id,
          partiful_link: e.partiful_link,
          tickets_tbd: e.tickets_tbd,
          lock_version: e.lock_version,
          inserted_at: e.inserted_at,
          updated_at: e.updated_at,
          recent_tickets_count: count(t.id),
          selling_fast: fragment("count(?) >= 5", t.id)
        },
        order_by: [
          asc: fragment("CASE WHEN ? = 'cancelled' THEN 1 ELSE 0 END", e.state),
          asc: e.start_date,
          asc: e.start_time
        ],
        limit: ^page_size,
        offset: ^offset
      )
      |> Repo.all()
      |> add_pricing_info_batch()

    total_pages = ceil(total_count / page_size)

    meta = %{
      page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages,
      has_next_page: page < total_pages,
      has_prev_page: page > 1
    }

    {events, meta}
  end

  defp parse_page_param(params, key, default) do
    case Map.get(params, key) do
      nil ->
        default

      val when is_integer(val) ->
        max(val, 1)

      val when is_binary(val) ->
        case Integer.parse(val) do
          {n, ""} -> max(n, 1)
          _ -> default
        end

      _ ->
        default
    end
  end

  @doc false
  def upcoming_events_with_preload_query(limit \\ 36) do
    from(e in Event,
      where: e.start_date > ^DateTime.utc_now(),
      where: e.state in [:published, :cancelled],
      order_by: [
        asc: fragment("CASE WHEN ? = 'cancelled' THEN 1 ELSE 0 END", e.state),
        asc: e.start_date,
        asc: e.start_time
      ],
      limit: ^limit
    )
  end

  @doc """
  Fetch upcoming events as full Event structs with given preloads.

  Use for admin pickers (e.g. newsletter) where full structs and cover_image are needed.
  Single query + preload, no N+1.
  """
  def list_upcoming_events_with_preload(limit \\ 36, preloads \\ [:cover_image]) do
    limit
    |> upcoming_events_with_preload_query()
    |> Repo.all()
    |> Repo.preload(preloads)
  end

  @doc """
  Fetch past events (events that have already occurred), optionally limited.
  Optimized to batch load ticket tiers and ticket counts to avoid N+1 queries.
  """
  def list_past_events(limit \\ 20) do
    Ysc.Events.EventListCache.list_past_events(limit)
  end

  def list_past_events_from_db(limit \\ 20) do
    three_days_ago = DateTime.add(DateTime.utc_now(), -3, :day)

    events =
      from(e in Event,
        where: e.start_date <= ^DateTime.utc_now(),
        where: e.state in [:published, :cancelled],
        left_join: t in Ticket,
        on:
          t.event_id == e.id and t.status == :confirmed and
            t.inserted_at >= ^three_days_ago,
        left_join: tt in TicketTier,
        on: t.ticket_tier_id == tt.id and tt.type != :donation,
        group_by: e.id,
        select: %{
          id: e.id,
          reference_id: e.reference_id,
          state: e.state,
          published_at: e.published_at,
          publish_at: e.publish_at,
          organizer_id: e.organizer_id,
          title: e.title,
          description: e.description,
          max_attendees: e.max_attendees,
          age_restriction: e.age_restriction,
          show_participants: e.show_participants,
          raw_details: e.raw_details,
          rendered_details: e.rendered_details,
          image_id: e.image_id,
          start_date: e.start_date,
          start_time: e.start_time,
          end_date: e.end_date,
          end_time: e.end_time,
          location_name: e.location_name,
          address: e.address,
          latitude: e.latitude,
          longitude: e.longitude,
          place_id: e.place_id,
          partiful_link: e.partiful_link,
          tickets_tbd: e.tickets_tbd,
          lock_version: e.lock_version,
          inserted_at: e.inserted_at,
          updated_at: e.updated_at,
          recent_tickets_count: count(t.id),
          selling_fast: fragment("count(?) >= 5", t.id)
        },
        order_by: [
          # Sort by start_date descending (most recent past events first)
          desc: e.start_date,
          # Then sort by start_time for events on the same date
          desc: e.start_time
        ],
        limit: ^limit
      )
      |> Repo.all()

    # Batch load all ticket tiers, ticket counts, and images for all events at once
    add_pricing_info_batch(events)
  end

  @doc """
  List events that are upcoming or occurred in the last 3 months.
  This is useful for expense reports to help users associate expenses with events.
  Events are ordered with upcoming events first (ascending by start_date),
  followed by past events (descending by start_date, most recent first).
  """
  def list_recent_and_upcoming_events do
    now = DateTime.utc_now()
    three_months_ago = DateTime.add(now, -90, :day)

    events =
      from(e in Event,
        where: e.state in [:published, :cancelled],
        where:
          (e.start_date >= ^three_months_ago and e.start_date <= ^now) or
            e.start_date > ^now,
        limit: 100
      )
      |> Repo.all()

    # Sort: upcoming events first (ascending), then past events (descending)
    {upcoming, past} =
      Enum.split_with(events, &(DateTime.compare(&1.start_date, now) == :gt))

    upcoming_sorted = Enum.sort_by(upcoming, & &1.start_date, {:asc, DateTime})
    past_sorted = Enum.sort_by(past, & &1.start_date, {:desc, DateTime})

    upcoming_sorted ++ past_sorted
  end

  # Batch load pricing info for all events to avoid N+1 queries
  defp add_pricing_info_batch(events) when is_list(events) do
    Ysc.Events.EventPricingCache.enrich_events(events)
  end

  @doc false
  def enrich_single_event_with_pricing_from_db(event) do
    [enriched] = enrich_events_with_pricing_info([event])
    enriched
  end

  defp enrich_events_with_pricing_info(events) do
    event_ids = Enum.map(events, & &1.id)

    # Batch load all ticket tiers for all events
    ticket_tiers_by_event = batch_load_ticket_tiers(event_ids)

    # Batch load ticket counts for all events
    ticket_counts_by_event = batch_load_ticket_counts(event_ids)

    # Batch load images for all events (extract unique image_ids)
    image_ids =
      events
      |> Enum.map(& &1.image_id)
      |> Enum.filter(&(&1 != nil))
      |> Enum.uniq()

    images_by_id = batch_load_images(image_ids)

    # Add pricing info, ticket counts, and images to each event
    Enum.map(events, fn event ->
      enrich_event_with_data(
        event,
        ticket_tiers_by_event,
        ticket_counts_by_event,
        images_by_id
      )
    end)
  end

  defp enrich_event_with_data(
         event,
         ticket_tiers_by_event,
         ticket_counts_by_event,
         images_by_id
       ) do
    ticket_tiers = Map.get(ticket_tiers_by_event, event.id, [])
    ticket_count = Map.get(ticket_counts_by_event, event.id, 0)

    pricing_info =
      if Map.get(event, :tickets_tbd) do
        %{
          display_text: "Tickets Coming Soon",
          has_free_tiers: false,
          lowest_price: nil
        }
      else
        calculate_event_pricing(ticket_tiers)
      end

    image = get_event_image(event, images_by_id)

    event
    |> Map.put(:pricing_info, pricing_info)
    |> Map.put(:ticket_tiers, ticket_tiers)
    |> Map.put(:ticket_count, ticket_count)
    |> Map.put(:image, image)
    |> Map.put(:cover_image, image)
  end

  defp get_event_image(event, images_by_id) do
    if event.image_id do
      Map.get(images_by_id, event.image_id)
    else
      nil
    end
  end

  # Batch load images for multiple image IDs
  defp batch_load_images(image_ids) when is_list(image_ids) do
    if image_ids == [] do
      %{}
    else
      alias Ysc.Media.Image

      from(i in Image, where: i.id in ^image_ids)
      |> Repo.all()
      |> Enum.into(%{}, fn image -> {image.id, image} end)
    end
  end

  # Batch load ticket tiers for multiple events
  defp batch_load_ticket_tiers(event_ids) when is_list(event_ids) do
    if event_ids == [] do
      %{}
    else
      from(tt in TicketTier,
        where: tt.event_id in ^event_ids,
        left_join: t in Ticket,
        on: t.ticket_tier_id == tt.id and t.status == :confirmed,
        group_by: [
          tt.id,
          tt.name,
          tt.description,
          tt.type,
          tt.price,
          tt.quantity,
          tt.requires_registration,
          tt.start_date,
          tt.end_date,
          tt.event_id,
          tt.lock_version,
          tt.inserted_at,
          tt.updated_at
        ],
        select: %{
          id: tt.id,
          name: tt.name,
          description: tt.description,
          type: tt.type,
          price: tt.price,
          quantity: tt.quantity,
          requires_registration: tt.requires_registration,
          start_date: tt.start_date,
          end_date: tt.end_date,
          event_id: tt.event_id,
          lock_version: tt.lock_version,
          inserted_at: tt.inserted_at,
          updated_at: tt.updated_at,
          sold_tickets_count: count(t.id)
        },
        order_by: [asc: tt.inserted_at]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.event_id)
    end
  end

  # Batch load attendee ticket counts for multiple events (donations excluded).
  defp batch_load_ticket_counts(event_ids) when is_list(event_ids) do
    batch_count_tickets_sold_excluding_donations(event_ids)
  end

  # Batch count confirmed tickets excluding donation tiers (same rules as count_tickets_sold_excluding_donations/1).
  defp batch_count_tickets_sold_excluding_donations([]), do: %{}

  defp batch_count_tickets_sold_excluding_donations(event_ids)
       when is_list(event_ids) do
    from(t in Ticket,
      join: tt in TicketTier,
      on: t.ticket_tier_id == tt.id,
      where: t.event_id in ^event_ids,
      where: t.status == :confirmed,
      where: tt.type != :donation,
      group_by: t.event_id,
      select: {t.event_id, count(t.id)}
    )
    |> Repo.all()
    |> Enum.into(%{}, fn {event_id, count} -> {event_id, count} end)
  end

  # Calculate pricing display information for an event
  defp calculate_event_pricing([]) do
    %{display_text: "Free", has_free_tiers: true, lowest_price: nil}
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
        %{display_text: "Free", has_free_tiers: true, lowest_price: nil}

      {true, _paid_tiers} ->
        # When there are both free and paid tiers, show "From $0.00"
        %{display_text: "From $0.00", has_free_tiers: true, lowest_price: nil}

      {false, []} ->
        %{display_text: "Free", has_free_tiers: false, lowest_price: nil}

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

  @doc """
  Returns a short display string for event pricing (e.g. "Free", "From $10", "Tickets coming soon").
  Use for newsletters and other places that need a single line. Event can have ticket_tiers preloaded
  or they will be loaded.
  """
  def event_pricing_display_string(%Event{} = event) do
    event = ensure_ticket_tiers_loaded(event)

    if Map.get(event, :tickets_tbd) do
      "Tickets coming soon"
    else
      tiers = event.ticket_tiers || []
      pricing = calculate_event_pricing(tiers)
      pricing.display_text
    end
  end

  @doc """
  Returns the earliest datetime when any ticket tier goes on sale, or nil.
  Use for newsletters (e.g. "Tickets on sale Jan 15"). Event can have ticket_tiers preloaded.
  """
  def event_earliest_tickets_sale_date(%Event{} = event) do
    event = ensure_ticket_tiers_loaded(event)

    dates =
      (event.ticket_tiers || [])
      |> Enum.map(& &1.start_date)
      |> Enum.reject(&is_nil/1)

    case dates do
      [] -> nil
      list -> Enum.min(list)
    end
  end

  defp ensure_ticket_tiers_loaded(%Event{} = event) do
    if Ecto.assoc_loaded?(event.ticket_tiers) do
      event
    else
      Repo.preload(event, :ticket_tiers)
    end
  end

  @doc """
  Publish an event by updating its state and setting `published_at`.
  """
  def publish_event(%Event{} = event) do
    cond do
      event.state not in [:draft, :scheduled] ->
        {:error, :invalid_state}

      event.title in [nil, ""] ->
        {:error, :missing_title}

      event.start_date in [nil, ""] ->
        {:error, :missing_start_date}

      true ->
        now = DateTime.utc_now()

        event
        |> Event.changeset(%{state: "published", published_at: now})
        |> Repo.update()
        |> case do
          {:ok, updated_event} ->
            invalidate_event_caches()

            broadcast(%Ysc.MessagePassingEvents.EventUpdated{
              event: updated_event
            })

            schedule_event_notifications(updated_event, now)
            schedule_event_photo_reminders(updated_event)

            {:ok, updated_event}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp schedule_event_notifications(event, published_at) do
    require Ysc.Logging

    try do
      YscWeb.Workers.EventNotificationWorker.schedule_notifications(
        event.id,
        published_at
      )

      Ysc.Logging.info("Scheduled event notification emails",
        event_id: event.id,
        published_at: published_at
      )
    rescue
      error ->
        Ysc.Logging.error("Failed to schedule event notification emails",
          event_id: event.id,
          error: Exception.message(error)
        )
    end
  end

  defp schedule_event_photo_reminders(%Event{} = event) do
    require Ysc.Logging

    try do
      case Ysc.EventPhotos.ensure_collection_for_event(event) do
        {:ok, _collection} ->
          YscWeb.Workers.EventPhotoReminderWorker.schedule_reminder(event)

        {:error, reason} ->
          Ysc.Logging.error("Failed to ensure event photo collection",
            event_id: event.id,
            error: inspect(reason)
          )
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to schedule event photo reminders",
          event_id: event.id,
          error: Exception.message(error)
        )
    end
  end

  defp maybe_reschedule_event_photo_reminder(%Event{state: state} = event)
       when state in [:published, "published"] do
    collection = Ysc.EventPhotos.get_by_event_id(event.id)

    if collection && is_nil(collection.reminder_sent_at) do
      YscWeb.Workers.EventPhotoReminderWorker.schedule_reminder(event)
    end

    :ok
  end

  defp maybe_reschedule_event_photo_reminder(_event), do: :ok

  def unpublish_event(%Event{} = event) do
    event
    |> Event.changeset(%{state: "draft", published_at: nil})
    |> Repo.update()
    |> case do
      {:ok, event} ->
        invalidate_event_caches()
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def cancel_event(%Event{} = event) do
    event
    |> Event.changeset(%{state: "cancelled"})
    |> Repo.update()
    |> case do
      {:ok, event} ->
        invalidate_event_caches()
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def schedule_event(%Event{} = event, publish_at) when is_binary(publish_at) do
    # Try to parse as full ISO8601 first, then fall back to datetime-local format
    parsed_datetime =
      case DateTime.from_iso8601(publish_at) do
        {:ok, dt, _offset} ->
          # Already a DateTime, use it directly
          dt

        {:error, _} ->
          # Try parsing as datetime-local string (format: "YYYY-MM-DDTHH:MM") as PST and convert to UTC
          case NaiveDateTime.from_iso8601("#{publish_at}:00") do
            {:ok, naive_dt} ->
              # Create DateTime in America/Los_Angeles timezone (PST)
              local_dt = DateTime.from_naive!(naive_dt, "America/Los_Angeles")
              # Convert to UTC for storage
              DateTime.shift_zone!(local_dt, "Etc/UTC")

            {:error, _} ->
              raise ArgumentError, "Invalid datetime format: #{publish_at}"
          end
      end

    schedule_event(event, parsed_datetime)
  end

  def schedule_event(%Event{} = event, publish_at)
      when is_struct(publish_at, DateTime) do
    changeset =
      Event.changeset(event, %{state: "scheduled", publish_at: publish_at})

    case Repo.update(changeset) do
      {:ok, event} ->
        invalidate_event_caches()
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def get_all_authors() do
    from(
      event in Event,
      left_join: user in assoc(event, :organizer),
      distinct: event.organizer_id,
      select: %{
        "organizer_id" => event.organizer_id,
        "organizer_first" => user.first_name,
        "organizer_last" => user.last_name
      },
      order_by: [{:desc, user.first_name}]
    )
    |> Repo.all()
    |> format_authors()
  end

  defp format_authors(result) do
    result
    |> Enum.reduce([], fn entry, acc ->
      [{name_format(entry), entry["organizer_id"]} | acc]
    end)
  end

  defp name_format(%{"organizer_first" => first, "organizer_last" => last}) do
    "#{String.capitalize(first)} #{String.downcase(last)}"
  end

  # Helper function for applying filters dynamically.
  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:organizer_id, organizer_id}, query ->
        where(query, [e], e.organizer_id == ^organizer_id)

      {:state, state}, query ->
        where(query, [e], e.state == ^state)

      {:title, title}, query ->
        where(query, [e], ilike(e.title, ^"%#{title}%"))

      _other, query ->
        query
    end)
  end

  defp topic() do
    "events"
  end

  # Ticket Tier Management Functions

  @doc """
  List all ticket tiers for an event with ticket counts.
  """
  def list_ticket_tiers_for_event(event_id) do
    from(tt in TicketTier,
      where: tt.event_id == ^event_id,
      left_join: t in Ticket,
      on: t.ticket_tier_id == tt.id and t.status == :confirmed,
      group_by: [
        tt.id,
        tt.name,
        tt.description,
        tt.type,
        tt.price,
        tt.quantity,
        tt.requires_registration,
        tt.start_date,
        tt.end_date,
        tt.event_id,
        tt.lock_version,
        tt.inserted_at,
        tt.updated_at
      ],
      select: %{
        id: tt.id,
        name: tt.name,
        description: tt.description,
        type: tt.type,
        price: tt.price,
        quantity: tt.quantity,
        requires_registration: tt.requires_registration,
        start_date: tt.start_date,
        end_date: tt.end_date,
        event_id: tt.event_id,
        lock_version: tt.lock_version,
        inserted_at: tt.inserted_at,
        updated_at: tt.updated_at,
        sold_tickets_count: count(t.id)
      },
      order_by: [asc: tt.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get upcoming events with ticket tier counts for admin dashboard.
  Optimized to batch load ticket tiers in a single query.
  """
  def get_upcoming_events_with_ticket_tier_counts() do
    now = DateTime.utc_now()

    events =
      Repo.all(
        from e in Event,
          where: e.start_date > ^now,
          where: e.state == :published,
          order_by: [asc: e.start_date]
      )

    # Batch load all ticket tiers for all events in a single query
    event_ids = Enum.map(events, & &1.id)

    tiers_by_event_id =
      if Enum.empty?(event_ids) do
        %{}
      else
        from(tt in TicketTier,
          where: tt.event_id in ^event_ids,
          left_join: t in Ticket,
          on: t.ticket_tier_id == tt.id and t.status == :confirmed,
          group_by: [
            tt.id,
            tt.name,
            tt.description,
            tt.type,
            tt.price,
            tt.quantity,
            tt.requires_registration,
            tt.start_date,
            tt.end_date,
            tt.event_id,
            tt.lock_version,
            tt.inserted_at,
            tt.updated_at
          ],
          select: %{
            id: tt.id,
            name: tt.name,
            description: tt.description,
            type: tt.type,
            price: tt.price,
            quantity: tt.quantity,
            requires_registration: tt.requires_registration,
            start_date: tt.start_date,
            end_date: tt.end_date,
            event_id: tt.event_id,
            lock_version: tt.lock_version,
            inserted_at: tt.inserted_at,
            updated_at: tt.updated_at,
            sold_tickets_count: count(t.id)
          },
          order_by: [asc: tt.inserted_at]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.event_id)
      end

    Enum.map(events, fn event ->
      tiers = Map.get(tiers_by_event_id, event.id, [])
      %{event: event, ticket_tiers: tiers}
    end)
  end

  @doc """
  Get a ticket tier by ID.
  """
  def get_ticket_tier!(id) do
    Repo.get!(TicketTier, id)
  end

  @doc """
  Get a ticket tier by ID, returns nil if not found.
  """
  def get_ticket_tier(id) do
    Repo.get(TicketTier, id)
  end

  @doc """
  Set or clear the tickets_tbd flag on an event.
  When true, the event shows "Tickets Coming Soon" until the first tier is added.
  When cleared (false), schedules save-the-date notifications for all subscribers.
  """
  def set_tickets_tbd(%Event{} = event, tbd \\ true) do
    was_tbd = event.tickets_tbd

    event
    |> Event.changeset(%{tickets_tbd: tbd})
    |> Repo.update()
    |> case do
      {:ok, updated_event} ->
        invalidate_event_caches()
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: updated_event})

        if was_tbd and not tbd do
          schedule_save_the_date_notifications(updated_event)
        end

        {:ok, updated_event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Create a new ticket tier.
  Automatically clears tickets_tbd on the event when the first tier is added.
  """
  def create_ticket_tier(attrs \\ %{}) do
    result =
      %TicketTier{}
      |> TicketTier.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, ticket_tier} ->
        invalidate_event_caches()

        broadcast(%Ysc.MessagePassingEvents.TicketTierAdded{
          ticket_tier: ticket_tier
        })

        # Auto-clear tickets_tbd when first tier is added
        if event = get_event(ticket_tier.event_id),
          do: clear_tickets_tbd_if_set(event)

        {:ok, ticket_tier}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp clear_tickets_tbd_if_set(%Event{tickets_tbd: true} = event) do
    set_tickets_tbd(event, false)
  end

  defp clear_tickets_tbd_if_set(_event), do: :ok

  @doc """
  Update an existing ticket tier.
  """
  def update_ticket_tier(%TicketTier{} = ticket_tier, attrs) do
    ticket_tier
    |> TicketTier.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, ticket_tier} ->
        invalidate_event_caches()

        broadcast(%Ysc.MessagePassingEvents.TicketTierUpdated{
          ticket_tier: ticket_tier
        })

        {:ok, ticket_tier}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Delete a ticket tier.
  """
  def delete_ticket_tier(%TicketTier{} = ticket_tier) do
    Repo.delete(ticket_tier)
    |> case do
      {:ok, ticket_tier} ->
        invalidate_event_caches()

        broadcast(%Ysc.MessagePassingEvents.TicketTierDeleted{
          ticket_tier: ticket_tier
        })

        {:ok, ticket_tier}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Count the number of tickets sold for a specific ticket tier.
  """
  def count_tickets_for_tier(ticket_tier_id) do
    Ticket
    |> where(
      [t],
      t.ticket_tier_id == ^ticket_tier_id and t.status == :confirmed
    )
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Count the total number of tickets sold for an event across all ticket tiers.
  """
  def count_total_tickets_sold_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id and t.status == :confirmed)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Count the number of tickets sold for an event excluding donation tiers.
  """
  def count_tickets_sold_excluding_donations(event_id) do
    Ticket
    |> join(:inner, [t], tt in TicketTier, on: t.ticket_tier_id == tt.id)
    |> where([t, tt], t.event_id == ^event_id and t.status == :confirmed)
    |> where([t, tt], tt.type != :donation)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Get a list of unique users who purchased tickets for an event (excluding donation tiers).
  Returns users ordered by first ticket purchase date.
  """
  def list_unique_attendees_for_event(event_id) do
    event_id
    |> attendee_ticket_data_for_event()
    |> Map.fetch!(:ticket_buyers)
  end

  @doc """
  Get a map of user_id => ticket_count for an event (excluding donation tiers).
  Returns a map where keys are user IDs and values are the number of tickets purchased.
  """
  def get_ticket_counts_per_user(event_id) do
    event_id
    |> non_donation_ticket_stats_by_user()
    |> Enum.map(fn %{user_id: user_id, ticket_count: count} ->
      {user_id, count}
    end)
    |> Map.new()
  end

  @doc """
  Sums confirmed ticket sales across non-donation tiers.

  Accepts the maps returned by `list_ticket_tiers_for_event/1`.
  """
  def non_donation_sold_count_from_tiers(ticket_tiers_with_counts)
      when is_list(ticket_tiers_with_counts) do
    ticket_tiers_with_counts
    |> Enum.reject(fn tier ->
      tier_type = Map.get(tier, :type) || Map.get(tier, "type")
      tier_type == :donation or tier_type == "donation"
    end)
    |> Enum.reduce(0, fn tier, acc ->
      sold =
        Map.get(tier, :sold_tickets_count) ||
          Map.get(tier, "sold_tickets_count") ||
          0

      acc + sold
    end)
  end

  @doc """
  Loads attendee ticket data for an event in two queries instead of three.

  Returns sold ticket count, per-user ticket counts, and ticket buyers ordered
  by first purchase (excluding donation tiers).
  """
  def attendee_ticket_data_for_event(event_id) do
    stats = non_donation_ticket_stats_by_user(event_id)

    sold_count =
      Enum.reduce(stats, 0, fn %{ticket_count: count}, acc -> acc + count end)

    ticket_counts =
      Map.new(stats, fn %{user_id: id, ticket_count: count} ->
        {id, count}
      end)

    user_ids = Enum.map(stats, & &1.user_id)

    ticket_buyers =
      if Enum.empty?(user_ids) do
        []
      else
        order_map = user_ids |> Enum.with_index() |> Map.new()

        from(u in User,
          where: u.id in ^user_ids,
          preload: [:current_avatar]
        )
        |> Repo.all()
        |> Enum.sort_by(fn user -> Map.get(order_map, user.id, 999_999) end)
      end

    %{
      sold_count: sold_count,
      ticket_counts: ticket_counts,
      ticket_buyers: ticket_buyers
    }
  end

  defp non_donation_ticket_stats_by_user(event_id) do
    Ticket
    |> join(:inner, [t], tt in TicketTier, on: t.ticket_tier_id == tt.id)
    |> where([t, tt], t.event_id == ^event_id and t.status == :confirmed)
    |> where([t, tt], tt.type != :donation)
    |> group_by([t], t.user_id)
    |> select([t], %{
      user_id: t.user_id,
      ticket_count: count(t.id),
      first_purchase: min(t.inserted_at)
    })
    |> order_by([t], asc: min(t.inserted_at))
    |> Repo.all()
  end

  @doc """
  Check if an event is selling fast based on recent ticket sales.

  An event is considered "selling fast" if it has sold 10 or more tickets
  in the last 3 days.

  ## Parameters:
  - `event_id`: The ID of the event to check

  ## Returns:
  - `true` if the event is selling fast
  - `false` otherwise
  """
  def event_selling_fast?(event_id) do
    three_days_ago = DateTime.add(DateTime.utc_now(), -3, :day)

    recent_ticket_count =
      Ticket
      |> join(:inner, [t], tt in TicketTier, on: t.ticket_tier_id == tt.id)
      |> where([t, tt], t.event_id == ^event_id and t.status == :confirmed)
      |> where([t, tt], t.inserted_at >= ^three_days_ago)
      |> where([t, tt], tt.type != :donation)
      |> Repo.aggregate(:count, :id)

    recent_ticket_count >= 5
  end

  @doc """
  Get the count of tickets sold in the last 3 days for an event.

  ## Parameters:
  - `event_id`: The ID of the event to check

  ## Returns:
  - Integer count of tickets sold in the last 3 days
  """
  def count_recent_tickets_sold(event_id) do
    three_days_ago = DateTime.add(DateTime.utc_now(), -3, :day)

    Ticket
    |> join(:inner, [t], tt in TicketTier, on: t.ticket_tier_id == tt.id)
    |> where([t, tt], t.event_id == ^event_id and t.status == :confirmed)
    |> where([t, tt], t.inserted_at >= ^three_days_ago)
    |> where([t, tt], tt.type != :donation)
    |> Repo.aggregate(:count, :id)
  end

  # Ticket Management Functions

  @doc """
  List all tickets for an event with user and ticket tier information.
  """
  def list_tickets_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id)
    |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
    |> join(:left, [t], u in assoc(t, :user), as: :user)
    |> preload([ticket_tier: tt, user: u], ticket_tier: tt, user: u)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Get all tickets for an event for CSV export.
  Includes ticket_tier, user (purchaser), and ticket_detail (attendee registration) preloads.
  Both purchaser and attendee information are maintained for export.
  """
  def list_tickets_for_export(event_id) do
    tickets =
      Ticket
      |> where([t], t.event_id == ^event_id and t.status == :confirmed)
      |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
      |> join(:left, [t], u in assoc(t, :user), as: :user)
      |> preload([ticket_tier: tt, user: u], ticket_tier: tt, user: u)
      |> order_by([t], asc: t.inserted_at)
      |> Repo.all()

    # Load ticket details (attendee registration) for each ticket (only if there are tickets)
    ticket_details_map =
      if Enum.empty?(tickets) do
        %{}
      else
        ticket_ids = Enum.map(tickets, & &1.id)

        TicketDetail
        |> where([td], td.ticket_id in ^ticket_ids)
        |> Repo.all()
        |> Enum.group_by(& &1.ticket_id)
        |> Enum.map(fn {ticket_id, [detail | _]} -> {ticket_id, detail} end)
        |> Map.new()
      end

    # Attach ticket details to tickets while maintaining user (purchaser) information
    Enum.map(tickets, fn ticket ->
      ticket_detail = Map.get(ticket_details_map, ticket.id)
      # Ensure both user (purchaser) and ticket_detail (attendee) are available
      ticket
      |> Map.put(:ticket_detail, ticket_detail)

      # User is already preloaded, so it's already available
    end)
  end

  @doc """
  Get ticket purchase summary for an event.
  """
  def get_ticket_purchase_summary(event_id) do
    from(t in Ticket,
      where: t.event_id == ^event_id and t.status == :confirmed,
      join: tt in assoc(t, :ticket_tier),
      join: u in assoc(t, :user),
      group_by: [
        tt.id,
        tt.name,
        u.id,
        u.first_name,
        u.last_name,
        u.email,
        tt.price
      ],
      select: %{
        ticket_tier_id: tt.id,
        ticket_tier_name: tt.name,
        user_id: u.id,
        user_name: fragment("? || ' ' || ?", u.first_name, u.last_name),
        user_email: u.email,
        ticket_count: count(t.id),
        ticket_tier_price: tt.price
      }
    )
    |> Repo.all()
    |> Enum.map(fn purchase ->
      # Calculate total amount by multiplying price by count
      total_amount =
        try do
          case purchase.ticket_tier_price do
            %Money{amount: amount} ->
              Money.new(
                Decimal.mult(amount, Decimal.new(purchase.ticket_count)),
                :USD
              )

            _ ->
              Money.new(0, :USD)
          end
        rescue
          _ ->
            Money.new(0, :USD)
        end

      purchase
      |> Map.put(:total_amount, total_amount)
      |> Map.delete(:ticket_tier_price)
    end)
  end

  @doc """
  Create a new ticket with validation.
  """
  def create_ticket(attrs \\ %{}) do
    %Ticket{}
    |> Ticket.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, ticket} ->
        invalidate_event_caches()
        broadcast(%Ysc.MessagePassingEvents.TicketCreated{ticket: ticket})
        {:ok, ticket}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  List all tickets for a specific user with event and ticket tier information.
  """
  def list_tickets_for_user(user_id) do
    Ticket
    |> where([t], t.user_id == ^user_id)
    |> join(:left, [t], e in assoc(t, :event), as: :event)
    |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
    |> join(:left, [t], to in assoc(t, :ticket_order), as: :ticket_order)
    |> preload([event: e, ticket_tier: tt, ticket_order: to],
      event: e,
      ticket_tier: tt,
      ticket_order: to
    )
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns confirmed tickets for `user_id` with event, tier, and order preloaded.

  Uses start of today in `America/Los_Angeles` as a coarse `start_date` filter so
  callers (e.g. the member home page) avoid loading the user's full ticket history.
  Finer "event has not started yet" filtering should happen in the caller when needed.

  ## Options

    * `:row_limit` - max rows from the database (default `100`)
  """
  def list_upcoming_confirmed_tickets_for_user(user_id, opts \\ []) do
    row_limit = Keyword.get(opts, :row_limit, 100)
    start_of_today_pst_utc = start_of_today_in_pst_as_utc()

    Ticket
    |> where([t], t.user_id == ^user_id and t.status == :confirmed)
    |> join(:inner, [t], e in assoc(t, :event), as: :event)
    |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
    |> join(:left, [t], to in assoc(t, :ticket_order), as: :ticket_order)
    |> where([event: e], not is_nil(e.start_date))
    |> where([event: e], e.start_date >= ^start_of_today_pst_utc)
    |> preload([event: e, ticket_tier: tt, ticket_order: to],
      event: e,
      ticket_tier: tt,
      ticket_order: to
    )
    |> order_by([event: e], asc: e.start_date)
    |> limit(^row_limit)
    |> Repo.all()
  end

  defp start_of_today_in_pst_as_utc do
    "America/Los_Angeles"
    |> DateTime.now!()
    |> DateTime.to_date()
    |> DateTime.new!(~T[00:00:00], "America/Los_Angeles")
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp order_records_by_ids(records, ids) do
    by_id = Map.new(records, &{&1.id, &1})

    Enum.flat_map(ids, fn id ->
      case Map.fetch(by_id, id) do
        {:ok, record} -> [record]
        :error -> []
      end
    end)
  end

  @doc """
  Loads events by id in one query. Returns records in the same order as `ids`
  (skipping missing ids).

  ## Options

    * `:preloads` - association preloads (default `[]`)
  """
  def list_events_by_ids(ids, opts \\ []) when is_list(ids) do
    preloads = Keyword.get(opts, :preloads, [])
    ids = Enum.uniq(Enum.reject(ids, &is_nil/1))

    if ids == [] do
      []
    else
      from(e in Event, where: e.id in ^ids)
      |> preload(^preloads)
      |> Repo.all()
      |> order_records_by_ids(ids)
    end
  end

  @doc """
  List upcoming events that a user has tickets for.
  """
  def list_upcoming_events_for_user(user_id) do
    Ticket
    |> where([t], t.user_id == ^user_id)
    |> join(:left, [t], e in assoc(t, :event), as: :event)
    |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
    |> where([event: e], e.start_date > ^DateTime.utc_now())
    |> where([event: e], e.state in [:published, :cancelled])
    |> preload([event: e, ticket_tier: tt],
      event: {e, :cover_image},
      ticket_tier: tt
    )
    |> order_by([event: e], asc: e.start_date)
    |> Repo.all()
  end

  @doc """
  Create a ticket detail for a ticket.
  """
  def create_ticket_detail(attrs \\ %{}) do
    %TicketDetail{}
    |> TicketDetail.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Create multiple ticket details for a list of tickets.
  Returns {:ok, list} on success, {:error, reason} on failure.
  """
  def create_ticket_details(ticket_details_list)
      when is_list(ticket_details_list) do
    Repo.transaction(fn ->
      ticket_details_list
      |> Enum.map(&insert_ticket_detail/1)
    end)
  end

  defp insert_ticket_detail(attrs) do
    case %TicketDetail{}
         |> TicketDetail.changeset(attrs)
         |> Repo.insert() do
      {:ok, ticket_detail} -> ticket_detail
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Get ticket detail for a ticket.
  """
  def get_ticket_detail_for_ticket(ticket_id) do
    Repo.get_by(TicketDetail, ticket_id: ticket_id)
  end

  @doc """
  Batch-load ticket registration details for many tickets in one query.

  Returns a map of `ticket_id => %TicketDetail{}`.
  """
  def list_ticket_details_for_ticket_ids(ticket_ids) when is_list(ticket_ids) do
    ticket_ids = ticket_ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    if ticket_ids == [] do
      %{}
    else
      TicketDetail
      |> where([td], td.ticket_id in ^ticket_ids)
      |> Repo.all()
      |> Map.new(&{&1.ticket_id, &1})
    end
  end

  # Registration Management Functions

  @doc """
  Create a registration (ticket detail) for a ticket.

  ## Parameters
  - `attrs`: Map containing `ticket_id`, `first_name`, `last_name`, and `email`

  ## Returns
  - `{:ok, registration}` on success
  - `{:error, changeset}` on failure
  """
  def create_registration(attrs \\ %{}) do
    %TicketDetail{}
    |> TicketDetail.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an existing registration.

  ## Parameters
  - `registration`: The TicketDetail struct to update
  - `attrs`: Map containing fields to update (`first_name`, `last_name`, `email`)

  ## Returns
  - `{:ok, registration}` on success
  - `{:error, changeset}` on failure
  """
  def update_registration(%TicketDetail{} = registration, attrs) do
    registration
    |> TicketDetail.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Get registration for a ticket.

  This is an alias for `get_ticket_detail_for_ticket/1` for clarity.

  ## Parameters
  - `ticket_id`: The ID of the ticket

  ## Returns
  - `%TicketDetail{}` if found
  - `nil` if not found
  """
  def get_registration_for_ticket(ticket_id) do
    get_ticket_detail_for_ticket(ticket_id)
  end

  @doc """
  Delete a registration.

  ## Parameters
  - `registration`: The TicketDetail struct to delete

  ## Returns
  - `{:ok, registration}` on success
  - `{:error, changeset}` on failure
  """
  def delete_registration(%TicketDetail{} = registration) do
    Repo.delete(registration)
  end

  @doc """
  Check if registration is required for a ticket based on its ticket tier.

  ## Parameters
  - `ticket`: The Ticket struct or ticket_id

  ## Returns
  - `true` if registration is required
  - `false` otherwise

  ## Examples

      iex> registration_required?(ticket)
      true

      iex> registration_required?(ticket_id)
      false
  """
  def registration_required?(%Ticket{} = ticket) do
    # Handle case where ticket_tier is not preloaded
    ticket_tier =
      case ticket.ticket_tier do
        %Ecto.Association.NotLoaded{} ->
          if ticket.ticket_tier_id do
            get_ticket_tier(ticket.ticket_tier_id)
          else
            nil
          end

        tier ->
          tier
      end

    case ticket_tier do
      %TicketTier{requires_registration: true} -> true
      %TicketTier{requires_registration: false} -> false
      _ -> false
    end
  end

  def registration_required?(ticket_id) when is_binary(ticket_id) do
    case Repo.get(Ticket, ticket_id) do
      nil -> false
      ticket -> registration_required?(ticket)
    end
  end

  def registration_required?(_), do: false

  # Ticket Reservation Management Functions

  @doc """
  Create a new ticket reservation.
  """
  def create_ticket_reservation(attrs \\ %{}) do
    %TicketReservation{}
    |> TicketReservation.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, reservation} ->
        invalidate_event_caches()

        broadcast(%Ysc.MessagePassingEvents.TicketReservationCreated{
          ticket_reservation: reservation,
          event_id: reservation_event_id(reservation.ticket_tier_id)
        })

        schedule_ticket_reservation_created_notification(reservation)

        {:ok, reservation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Schedules the member-facing email for a newly created ticket reservation (admin hold).

  Best-effort: failures are logged and do not affect the reservation insert.
  """
  def schedule_ticket_reservation_created_notification(
        %TicketReservation{} = reservation
      ) do
    require Ysc.Logging

    reservation =
      Repo.preload(reservation, [:user, :created_by, ticket_tier: :event])

    cond do
      is_nil(reservation.user) ->
        Ysc.Logging.debug("Skipping ticket reservation email: missing user",
          ticket_reservation_id: reservation.id
        )

        :skipped

      reservation.user.email in [nil, ""] ->
        Ysc.Logging.debug(
          "Skipping ticket reservation email: user has no email",
          ticket_reservation_id: reservation.id,
          user_id: reservation.user_id
        )

        :skipped

      true ->
        try do
          email_mod = YscWeb.Emails.TicketReservationCreated
          email_data = email_mod.prepare_email_data(reservation)
          subject = email_mod.get_subject(email_data)
          idempotency_key = "ticket_reservation_created_#{reservation.id}"

          case YscWeb.Emails.Notifier.schedule_email(
                 reservation.user.email,
                 idempotency_key,
                 subject,
                 email_mod.get_template_name(),
                 email_data,
                 "",
                 reservation.user_id
               ) do
            %Oban.Job{} = job ->
              Ysc.Logging.info(
                "Ticket reservation notification email scheduled",
                ticket_reservation_id: reservation.id,
                user_id: reservation.user_id,
                oban_job_id: job.id
              )

              {:ok, job}

            {:error, reason} = error ->
              Ysc.Logging.error(
                "Failed to schedule ticket reservation notification email",
                error: inspect(reason),
                extra: %{
                  ticket_reservation_id: reservation.id,
                  user_id: reservation.user_id
                },
                tags: %{
                  "operation" =>
                    "schedule_ticket_reservation_created_notification"
                }
              )

              error
          end
        rescue
          error ->
            Ysc.Logging.error(
              "Failed to prepare ticket reservation notification email",
              error: error,
              stacktrace: __STACKTRACE__,
              extra: %{
                ticket_reservation_id: reservation.id,
                user_id: reservation.user_id
              },
              tags: %{
                "operation" =>
                  "schedule_ticket_reservation_created_notification"
              }
            )

            {:error, :email_prepare_failed}
        end
    end
  end

  @doc """
  Get a ticket reservation by ID.
  """
  def get_ticket_reservation!(id) do
    Repo.get!(TicketReservation, id)
    |> Repo.preload([:ticket_tier, :user, :created_by, :ticket_order])
  end

  @doc """
  Get a ticket reservation by ID, returns nil if not found.
  """
  def get_ticket_reservation(id) do
    case Repo.get(TicketReservation, id) do
      nil ->
        nil

      reservation ->
        Repo.preload(reservation, [
          :ticket_tier,
          :user,
          :created_by,
          :ticket_order
        ])
    end
  end

  @doc """
  List all ticket reservations for a ticket tier.
  """
  def list_ticket_reservations_for_tier(tier_id) do
    TicketReservation
    |> where([tr], tr.ticket_tier_id == ^tier_id)
    |> order_by([tr], desc: tr.inserted_at)
    |> Repo.all()
    |> Repo.preload([:ticket_tier, :user, :created_by, :ticket_order])
  end

  @doc """
  Scopes a `TicketReservation` query to rows that still count as an active hold.

  `status` must be `"active"` and, when `expires_at` is set, it must be strictly
  after `DateTime.utc_now/0` (same rule as checkout, capacity, and fulfillment).
  """
  def where_ticket_reservation_hold_active(query) do
    now = DateTime.utc_now()

    where(
      query,
      [tr],
      tr.status == "active" and (is_nil(tr.expires_at) or tr.expires_at > ^now)
    )
  end

  @doc """
  List ticket reservations for a user for a specific event.

  Only returns holds that are still valid for pricing (`expires_at` unset or in the future).
  """
  def list_ticket_reservations_for_user(user_id, event_id) do
    TicketReservation
    |> join(:inner, [tr], tt in TicketTier, on: tr.ticket_tier_id == tt.id)
    |> where([tr, tt], tr.user_id == ^user_id and tt.event_id == ^event_id)
    |> where_ticket_reservation_hold_active()
    |> order_by([tr], desc: tr.inserted_at)
    |> Repo.all()
    |> Repo.preload([:ticket_tier, :user, :created_by, :ticket_order])
  end

  @doc """
  Active ticket holds for a member: `status` is `\"active\"` and the hold window
  is still open (`expires_at` unset or in the future). These apply at checkout.

  Fulfilled, cancelled, or lapsed holds are excluded.
  """
  def list_active_ticket_holds_for_user(user_id) do
    TicketReservation
    |> where([tr], tr.user_id == ^user_id)
    |> where_ticket_reservation_hold_active()
    |> order_by([tr], desc: tr.inserted_at)
    |> preload(ticket_tier: :event)
    |> Repo.all()
  end

  @doc """
  Lists every ticket reservation for the member (`user_id`), in any status,
  newest first.

  Preloads `ticket_tier` (with `event`) for account settings and similar UIs.
  """
  def list_all_ticket_reservations_for_user(user_id) do
    TicketReservation
    |> where([tr], tr.user_id == ^user_id)
    |> order_by([tr], desc: tr.inserted_at)
    |> preload(ticket_tier: :event)
    |> Repo.all()
  end

  @doc """
  List reservations for a tier that still count toward holds and discounts.

  Excludes `status: "active"` rows whose `expires_at` is in the past (those remain
  in the database until fulfilled or cancelled; see `list_expired_active_reservations_for_tier/1`).
  """
  @ticket_reservation_detail_preloads [:ticket_tier, :user, :created_by]

  def list_active_reservations_for_tier(tier_id) do
    tier_id
    |> List.wrap()
    |> list_active_reservations_for_tiers()
    |> Map.get(tier_id, [])
  end

  @doc """
  Batch version of `list_active_reservations_for_tier/1`.

  Returns a map of `tier_id => [reservations]` so the admin tickets tab can load
  holds for every tier in two queries instead of 2×N per-tier round trips.
  """
  def list_active_reservations_for_tiers(tier_ids) when is_list(tier_ids) do
    tier_ids = Enum.uniq(tier_ids)

    if tier_ids == [] do
      %{}
    else
      TicketReservation
      |> where([tr], tr.ticket_tier_id in ^tier_ids)
      |> where_ticket_reservation_hold_active()
      |> order_by([tr], desc: tr.inserted_at)
      |> Repo.all()
      |> Repo.preload(@ticket_reservation_detail_preloads)
      |> Enum.group_by(& &1.ticket_tier_id)
      |> reservations_by_tier(tier_ids)
    end
  end

  @doc """
  Active `status` reservations whose `expires_at` is set and not after now.

  Used so admins can see lapsed holds that still occupy a row until cancelled or fulfilled.
  """
  def list_expired_active_reservations_for_tier(tier_id) do
    tier_id
    |> List.wrap()
    |> list_expired_active_reservations_for_tiers()
    |> Map.get(tier_id, [])
  end

  @doc """
  Batch version of `list_expired_active_reservations_for_tier/1`.

  See `list_active_reservations_for_tiers/1`.
  """
  def list_expired_active_reservations_for_tiers(tier_ids)
      when is_list(tier_ids) do
    tier_ids = Enum.uniq(tier_ids)
    now = DateTime.utc_now()

    if tier_ids == [] do
      %{}
    else
      TicketReservation
      |> where([tr], tr.ticket_tier_id in ^tier_ids and tr.status == "active")
      |> where([tr], not is_nil(tr.expires_at) and tr.expires_at <= ^now)
      |> order_by([tr], desc: tr.inserted_at)
      |> Repo.all()
      |> Repo.preload(@ticket_reservation_detail_preloads)
      |> Enum.group_by(& &1.ticket_tier_id)
      |> reservations_by_tier(tier_ids)
    end
  end

  defp reservations_by_tier(grouped, tier_ids) do
    Map.new(tier_ids, fn tier_id -> {tier_id, Map.get(grouped, tier_id, [])} end)
  end

  @doc """
  Fulfill a ticket reservation by linking it to a ticket order.
  """
  def fulfill_ticket_reservation(
        %TicketReservation{} = reservation,
        ticket_order_id
      ) do
    now = DateTime.utc_now()

    case Repo.update_all(
           from(tr in TicketReservation,
             where: tr.id == ^reservation.id,
             where: tr.status == "active",
             where: is_nil(tr.expires_at) or tr.expires_at > ^now
           ),
           set: [
             status: "fulfilled",
             fulfilled_at: now,
             ticket_order_id: ticket_order_id
           ]
         ) do
      {1, _} ->
        reservation = Repo.get!(TicketReservation, reservation.id)
        invalidate_event_caches()

        broadcast(%Ysc.MessagePassingEvents.TicketReservationFulfilled{
          ticket_reservation: reservation,
          event_id: reservation_event_id(reservation.ticket_tier_id)
        })

        {:ok, reservation}

      {0, _} ->
        {:error, :reservation_not_active}
    end
  end

  @doc """
  Cancel a ticket reservation.

  Only rows still `active` are cancelled. A conditional update prevents a race
  where checkout fulfills the hold concurrently — a plain changeset update could
  overwrite `fulfilled` with `cancelled` while leaving `ticket_order_id` set.
  """
  def cancel_ticket_reservation(%TicketReservation{} = reservation) do
    now = DateTime.utc_now()

    case Repo.update_all(
           from(tr in TicketReservation,
             where: tr.id == ^reservation.id,
             where: tr.status == "active"
           ),
           set: [status: "cancelled", cancelled_at: now]
         ) do
      {1, _} ->
        reservation = Repo.get!(TicketReservation, reservation.id)
        invalidate_event_caches()

        broadcast(%Ysc.MessagePassingEvents.TicketReservationCancelled{
          ticket_reservation: reservation,
          event_id: reservation_event_id(reservation.ticket_tier_id)
        })

        {:ok, reservation}

      {0, _} ->
        {:error, :reservation_not_active}
    end
  end

  @doc """
  Cancels active ticket reservations whose `expires_at` has passed.

  Only rows with `status: \"active\"`, a non-nil `expires_at`, and
  `expires_at <= DateTime.utc_now/0` are processed (same rows as
  `list_expired_active_reservations_for_tier/1`). Indefinite holds are skipped.

  Atomically cancels each candidate row only if it is still `active` and past
  `expires_at`. That avoids a race where checkout fulfills the hold after the
  expiry job selected the id but before cancellation — `Repo.get/1` plus
  `cancel_ticket_reservation/1` could otherwise overwrite `fulfilled` with
  `cancelled`.

  Successful cancellations broadcast `TicketReservationCancelled` like
  `cancel_ticket_reservation/1`.

  ## Options

  - `:limit` — max reservations to process in one run (default `500`).

  Returns `{:ok, %{cancelled: integer, failed: integer, total_pending: integer,
  backlog_remaining: integer}}` where `total_pending` is the count of rows
  matching the expiry criteria before this batch, and `backlog_remaining` is
  `max(0, total_pending - cancelled)` (rows still to clear on later runs,
  including failed attempts and any not yet processed due to `:limit`).
  """
  def expire_passed_ticket_reservations(opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)
    now = DateTime.utc_now()

    pending_query =
      from(tr in TicketReservation,
        where: tr.status == "active",
        where: not is_nil(tr.expires_at) and tr.expires_at <= ^now
      )

    total_pending =
      pending_query
      |> select([tr], count(tr.id))
      |> Repo.one()

    ids =
      pending_query
      |> order_by([tr], asc: tr.expires_at)
      |> limit(^limit)
      |> select([tr], tr.id)
      |> Repo.all()

    {cancelled, failed} =
      Enum.reduce(ids, {0, 0}, fn id, {c_acc, f_acc} ->
        case cancel_expired_ticket_reservation_atomically(id, now) do
          {:ok, _} -> {c_acc + 1, f_acc}
          :skipped -> {c_acc, f_acc}
        end
      end)

    backlog_remaining = max(0, total_pending - cancelled)

    {:ok,
     %{
       cancelled: cancelled,
       failed: failed,
       total_pending: total_pending,
       backlog_remaining: backlog_remaining
     }}
  end

  defp cancel_expired_ticket_reservation_atomically(reservation_id, now) do
    case Repo.update_all(
           from(tr in TicketReservation,
             where: tr.id == ^reservation_id,
             where: tr.status == "active",
             where: not is_nil(tr.expires_at) and tr.expires_at <= ^now
           ),
           set: [status: "cancelled", cancelled_at: now]
         ) do
      {1, _} ->
        reservation = Repo.get!(TicketReservation, reservation_id)

        invalidate_event_caches()

        broadcast(%Ysc.MessagePassingEvents.TicketReservationCancelled{
          ticket_reservation: reservation,
          event_id: reservation_event_id(reservation.ticket_tier_id)
        })

        {:ok, reservation}

      {0, _} ->
        :skipped
    end
  end

  @doc """
  Batch count of reserved tickets per tier (active, non-expired holds only).

  Returns `%{tier_id => reserved_quantity}`.
  """
  def batch_count_reserved_tickets_for_tiers(tier_ids) when is_list(tier_ids) do
    tier_ids = Enum.uniq(tier_ids)

    if tier_ids == [] do
      %{}
    else
      TicketReservation
      |> where([tr], tr.ticket_tier_id in ^tier_ids)
      |> where_ticket_reservation_hold_active()
      |> group_by([tr], tr.ticket_tier_id)
      |> select([tr], {tr.ticket_tier_id, sum(tr.quantity)})
      |> Repo.all()
      |> Map.new(fn {tier_id, count} -> {tier_id, count || 0} end)
    end
  end

  @doc """
  Sums active reservation holds across non-donation tiers.

  `reserved_counts` is typically from `batch_count_reserved_tickets_for_tiers/1`.
  """
  def non_donation_reserved_count_from_tiers(ticket_tiers, reserved_counts)
      when is_list(ticket_tiers) and is_map(reserved_counts) do
    ticket_tiers
    |> Enum.reject(fn tier ->
      tier_type = Map.get(tier, :type) || Map.get(tier, "type")
      tier_type == :donation or tier_type == "donation"
    end)
    |> Enum.reduce(0, fn tier, acc ->
      tier_id = Map.get(tier, :id) || Map.get(tier, "id")
      acc + Map.get(reserved_counts, tier_id, 0)
    end)
  end

  @doc """
  Count total reserved tickets for a tier (active, non-expired reservations only).
  """
  def count_reserved_tickets_for_tier(tier_id) do
    TicketReservation
    |> where([tr], tr.ticket_tier_id == ^tier_id)
    |> where_ticket_reservation_hold_active()
    |> select([tr], sum(tr.quantity))
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  @doc """
  Get the quantity of tickets reserved for a specific user and tier (hold still valid).
  """
  def get_user_reserved_quantity(tier_id, user_id) do
    TicketReservation
    |> where([tr], tr.ticket_tier_id == ^tier_id and tr.user_id == ^user_id)
    |> where_ticket_reservation_hold_active()
    |> select([tr], sum(tr.quantity))
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  @doc """
  Subscribe a user to a notification type for an event.
  Safe to call multiple times — duplicate subscriptions are silently ignored.
  """
  def subscribe_to_event_notification(
        %Event{} = event,
        user_id,
        notification_type
      ) do
    %EventNotificationSubscription{}
    |> EventNotificationSubscription.changeset(%{
      event_id: event.id,
      user_id: user_id,
      notification_type: notification_type
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:event_id, :user_id, :notification_type]
    )
  end

  @doc """
  Unsubscribe a user from a notification type for an event.
  """
  def unsubscribe_from_event_notification(
        %Event{} = event,
        user_id,
        notification_type
      ) do
    from(s in EventNotificationSubscription,
      where: s.event_id == ^event.id,
      where: s.user_id == ^user_id,
      where: s.notification_type == ^notification_type
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Check if a user is subscribed to a notification type for an event.
  Returns false if user_id is nil.
  """
  def subscribed_to_event_notification?(_event, nil, _notification_type),
    do: false

  def subscribed_to_event_notification?(
        %Event{} = event,
        user_id,
        notification_type
      ) do
    from(s in EventNotificationSubscription,
      where: s.event_id == ^event.id,
      where: s.user_id == ^user_id,
      where: s.notification_type == ^notification_type
    )
    |> Repo.exists?()
  end

  @doc """
  Get all users subscribed to a notification type for an event.
  """
  def get_event_notification_subscribers(event_id, notification_type) do
    from(s in EventNotificationSubscription,
      join: u in assoc(s, :user),
      where: s.event_id == ^event_id,
      where: s.notification_type == ^notification_type,
      select: u
    )
    |> Repo.all()
  end

  @doc """
  Delete all subscriptions for an event and notification type.
  Called after notifications have been sent.
  """
  def delete_event_notification_subscriptions(event_id, notification_type) do
    from(s in EventNotificationSubscription,
      where: s.event_id == ^event_id,
      where: s.notification_type == ^notification_type
    )
    |> Repo.delete_all()

    :ok
  end

  defp schedule_save_the_date_notifications(%Event{} = event) do
    require Ysc.Logging
    scheduled_at = DateTime.add(DateTime.utc_now(), 3600, :second)

    case %{"event_id" => event.id}
         |> YscWeb.Workers.SaveTheDateNotificationWorker.new(
           scheduled_at: scheduled_at
         )
         |> Oban.insert() do
      {:ok, job} ->
        Ysc.Logging.info("Scheduled save-the-date notifications",
          event_id: event.id,
          scheduled_at: job.scheduled_at
        )

      {:error, reason} ->
        Ysc.Logging.error("Failed to schedule save-the-date notifications",
          event_id: event.id,
          error: inspect(reason)
        )
    end
  end

  # --- Event Updates ---

  @doc """
  Creates an event update and enqueues the notification worker.
  """
  def create_event_update(event, attrs) do
    result =
      %EventUpdate{}
      |> EventUpdate.changeset(attrs)
      |> Ecto.Changeset.put_assoc(:event, event)
      |> Ecto.Changeset.put_change(
        :sent_by_id,
        attrs[:sent_by_id] || attrs["sent_by_id"]
      )
      |> Repo.insert()

    case result do
      {:ok, event_update} ->
        broadcast(%Ysc.MessagePassingEvents.EventUpdateCreated{
          event_update: event_update,
          event_id: event.id
        })

        {:ok, event_update}

      error ->
        error
    end
  end

  @doc """
  Returns all updates for an event, newest first (admin view).
  """
  def list_event_updates(event_id) do
    EventUpdate
    |> where([u], u.event_id == ^event_id)
    |> order_by([u], desc: u.inserted_at)
    |> preload(:sent_by)
    |> Repo.all()
  end

  @doc """
  Returns updates visible on the public event page, newest first.
  """
  def list_visible_event_updates(event_id) do
    EventUpdate
    |> where([u], u.event_id == ^event_id and u.show_on_event_page == true)
    |> order_by([u], desc: u.inserted_at)
    |> preload(:sent_by)
    |> Repo.all()
  end

  @doc """
  Collects deduplicated recipient email addresses for an event.

  Returns emails from both ticket purchasers (User.email) and
  registrants (TicketDetail.email) for all confirmed tickets.
  """
  def list_event_update_recipients(event_id) do
    purchaser_recipients =
      from t in Ticket,
        join: tt in TicketTier,
        on: t.ticket_tier_id == tt.id,
        join: u in User,
        on: t.user_id == u.id,
        where:
          t.event_id == ^event_id and t.status == :confirmed and
            tt.type != :donation,
        where: not is_nil(u.email) and u.email != "",
        select: %{
          email: u.email,
          first_name: u.first_name,
          normalized: fragment("lower(?)", u.email),
          priority: 1
        }

    detail_recipients =
      from t in Ticket,
        join: tt in TicketTier,
        on: t.ticket_tier_id == tt.id,
        join: td in TicketDetail,
        on: td.ticket_id == t.id,
        where:
          t.event_id == ^event_id and t.status == :confirmed and
            tt.type != :donation,
        where: not is_nil(td.email) and td.email != "",
        select: %{
          email: td.email,
          first_name: td.first_name,
          normalized: fragment("lower(?)", td.email),
          priority: 2
        }

    union_query = union(purchaser_recipients, ^detail_recipients)

    from(r in subquery(union_query),
      distinct: r.normalized,
      order_by: [asc: r.normalized, asc: r.priority],
      select: %{email: r.email, first_name: r.first_name}
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of unique recipients for an event update.

  Uses a single SQL query with `UNION` and `COUNT(DISTINCT …)` so the admin
  Updates tab does not load every ticket, user, and ticket detail just to show
  a recipient count.
  """
  def count_event_update_recipients(event_id) do
    purchaser_emails =
      from t in Ticket,
        join: tt in TicketTier,
        on: t.ticket_tier_id == tt.id,
        join: u in User,
        on: t.user_id == u.id,
        where:
          t.event_id == ^event_id and t.status == :confirmed and
            tt.type != :donation,
        where: not is_nil(u.email) and u.email != "",
        select: %{email: fragment("lower(?)", u.email)}

    detail_emails =
      from t in Ticket,
        join: tt in TicketTier,
        on: t.ticket_tier_id == tt.id,
        join: td in TicketDetail,
        on: td.ticket_id == t.id,
        where:
          t.event_id == ^event_id and t.status == :confirmed and
            tt.type != :donation,
        where: not is_nil(td.email) and td.email != "",
        select: %{email: fragment("lower(?)", td.email)}

    union_query = union(purchaser_emails, ^detail_emails)

    from(e in subquery(union_query), select: count(e.email, :distinct))
    |> Repo.one()
  end

  @doc """
  Returns true when `email` belongs to a confirmed, non-donation event attendee.

  Checks purchaser (`User.email`) and registrant (`TicketDetail.email`) addresses
  with a single indexed `EXISTS` query instead of loading every recipient.
  """
  def event_update_recipient_email?(event_id, email)
      when is_binary(event_id) and is_binary(email) and email != "" do
    normalized = String.downcase(email)

    purchaser_match =
      from t in Ticket,
        join: tt in TicketTier,
        on: t.ticket_tier_id == tt.id,
        join: u in User,
        on: t.user_id == u.id,
        where:
          t.event_id == ^event_id and t.status == :confirmed and
            tt.type != :donation,
        where: fragment("lower(?)", u.email) == ^normalized

    detail_match =
      from t in Ticket,
        join: tt in TicketTier,
        on: t.ticket_tier_id == tt.id,
        join: td in TicketDetail,
        on: td.ticket_id == t.id,
        where:
          t.event_id == ^event_id and t.status == :confirmed and
            tt.type != :donation,
        where: fragment("lower(?)", td.email) == ^normalized

    Repo.exists?(purchaser_match) or Repo.exists?(detail_match)
  end

  def event_update_recipient_email?(_event_id, _email), do: false

  @doc """
  Returns the number of ticket tiers configured for an event.
  """
  def count_ticket_tiers_for_event(event_id) do
    TicketTier
    |> where([tt], tt.event_id == ^event_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Marks an event update as sent with the given recipient count.
  """
  def mark_event_update_sent(event_update, recipient_count) do
    result =
      event_update
      |> Ecto.Changeset.change(%{
        sent_at: DateTime.truncate(DateTime.utc_now(), :second),
        recipient_count: recipient_count
      })
      |> Repo.update()

    case result do
      {:ok, updated} ->
        broadcast(%Ysc.MessagePassingEvents.EventUpdateSent{
          event_update: updated,
          event_id: updated.event_id
        })

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Marks an event's publication notification as sent with the given recipient count.
  """
  def mark_event_notification_sent(%Event{} = event, recipient_count) do
    event
    |> Ecto.Changeset.change(%{
      notification_sent_at: DateTime.truncate(DateTime.utc_now(), :second),
      notification_recipient_count: recipient_count
    })
    |> Repo.update()
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Ysc.PubSub, topic(), {__MODULE__, event})
  end

  defp reservation_event_id(ticket_tier_id) do
    TicketTier
    |> where([tt], tt.id == ^ticket_tier_id)
    |> select([tt], tt.event_id)
    |> Repo.one()
  end

  @doc """
  Invalidates event list, pricing, and public upcoming-event caches.

  Call after ticket inventory or public event list data changes (sales, holds, tiers).
  """
  def invalidate_event_caches do
    Ysc.Events.EventPricingCache.invalidate()
    :ok
  end

  @doc false
  def ci_query_explain_query, do: upcoming_events_with_preload_query()
end
