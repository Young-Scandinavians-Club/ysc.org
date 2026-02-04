defmodule Ysc.Events do
  @moduledoc """
  Context module for managing events and tickets.

  Provides functions for creating, updating, and querying events, ticket tiers,
  tickets, and related data.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Events.Event
  alias Ysc.Events.TicketTier
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketDetail
  alias Ysc.Events.TicketReservation

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
  List all events, optionally with filters.
  """
  def list_events(filters \\ %{}) do
    Event
    |> apply_filters(filters)
    |> Repo.all()
    |> Repo.preload(:organizer)
  end

  def list_events_paginated(params) do
    Event
    |> where([e], e.state not in ["deleted"])
    |> join(:left, [p], u in assoc(p, :organizer), as: :organizer)
    |> preload([organizer: p], organizer: p)
    |> Flop.validate_and_run(params, for: Event)
  end

  @doc """
  Insert a new event into the database.
  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        broadcast(%Ysc.MessagePassingEvents.EventAdded{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Update an existing event with new attributes.
  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, event} ->
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})
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
  Fetch past events (events that have already occurred), optionally limited.
  Optimized to batch load ticket tiers and ticket counts to avoid N+1 queries.
  """
  def list_past_events(limit \\ 20) do
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
    if events == [] do
      []
    else
      enrich_events_with_pricing_info(events)
    end
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
    pricing_info = calculate_event_pricing(ticket_tiers)
    image = get_event_image(event, images_by_id)

    event
    |> Map.put(:pricing_info, pricing_info)
    |> Map.put(:ticket_tiers, ticket_tiers)
    |> Map.put(:ticket_count, ticket_count)
    |> Map.put(:image, image)
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

  # Batch load ticket counts for multiple events
  defp batch_load_ticket_counts(event_ids) when is_list(event_ids) do
    if event_ids == [] do
      %{}
    else
      from(t in Ticket,
        where: t.event_id in ^event_ids and t.status == :confirmed,
        group_by: t.event_id,
        select: {t.event_id, count(t.id)}
      )
      |> Repo.all()
      |> Enum.into(%{}, fn {event_id, count} -> {event_id, count} end)
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

  @doc """
  Publish an event by updating its state and setting `published_at`.
  """
  def publish_event(%Event{} = event) do
    now = DateTime.utc_now()

    event
    |> Event.changeset(%{state: "published", published_at: now})
    |> Repo.update()
    |> case do
      {:ok, event} ->
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})

        # Schedule event notification emails (1 hour after publish)
        schedule_event_notifications(event, now)

        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp schedule_event_notifications(event, published_at) do
    require Logger

    try do
      YscWeb.Workers.EventNotificationWorker.schedule_notifications(
        event.id,
        published_at
      )

      Logger.info("Scheduled event notification emails",
        event_id: event.id,
        published_at: published_at
      )
    rescue
      error ->
        Logger.error("Failed to schedule event notification emails",
          event_id: event.id,
          error: Exception.message(error)
        )
    end
  end

  def unpublish_event(%Event{} = event) do
    event
    |> Event.changeset(%{state: "draft", published_at: nil})
    |> Repo.update()
    |> case do
      {:ok, event} ->
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
  Create a new ticket tier.
  """
  def create_ticket_tier(attrs \\ %{}) do
    %TicketTier{}
    |> TicketTier.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, ticket_tier} ->
        broadcast(%Ysc.MessagePassingEvents.TicketTierAdded{
          ticket_tier: ticket_tier
        })

        {:ok, ticket_tier}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Update an existing ticket tier.
  """
  def update_ticket_tier(%TicketTier{} = ticket_tier, attrs) do
    ticket_tier
    |> TicketTier.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, ticket_tier} ->
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
    import Ecto.Query
    alias Ysc.Accounts.User

    # First, get distinct user IDs with their first ticket purchase date
    user_ids_with_dates =
      Ticket
      |> join(:inner, [t], tt in TicketTier, on: t.ticket_tier_id == tt.id)
      |> where([t, tt], t.event_id == ^event_id and t.status == :confirmed)
      |> where([t, tt], tt.type != :donation)
      |> group_by([t], t.user_id)
      |> select([t], %{user_id: t.user_id, first_purchase: min(t.inserted_at)})
      |> order_by([t], asc: min(t.inserted_at))
      |> Repo.all()

    # Extract user IDs
    user_ids = Enum.map(user_ids_with_dates, & &1.user_id)

    # Fetch users in the same order
    if Enum.empty?(user_ids) do
      []
    else
      # Create a map for ordering
      order_map = user_ids |> Enum.with_index() |> Map.new()

      from(u in User,
        where: u.id in ^user_ids
      )
      |> Repo.all()
      |> Enum.sort_by(fn user -> Map.get(order_map, user.id, 999_999) end)
    end
  end

  @doc """
  Get a map of user_id => ticket_count for an event (excluding donation tiers).
  Returns a map where keys are user IDs and values are the number of tickets purchased.
  """
  def get_ticket_counts_per_user(event_id) do
    Ticket
    |> join(:inner, [t], tt in TicketTier, on: t.ticket_tier_id == tt.id)
    |> where([t, tt], t.event_id == ^event_id and t.status == :confirmed)
    |> where([t, tt], tt.type != :donation)
    |> group_by([t], t.user_id)
    |> select([t], %{user_id: t.user_id, ticket_count: count(t.id)})
    |> Repo.all()
    |> Enum.map(fn %{user_id: user_id, ticket_count: count} ->
      {user_id, count}
    end)
    |> Map.new()
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
    |> where([t], t.event_id == ^event_id and t.status == :confirmed)
    |> where([t], t.inserted_at >= ^three_days_ago)
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
  List upcoming events that a user has tickets for.
  """
  def list_upcoming_events_for_user(user_id) do
    Ticket
    |> where([t], t.user_id == ^user_id)
    |> join(:left, [t], e in assoc(t, :event), as: :event)
    |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
    |> where([event: e], e.start_date > ^DateTime.utc_now())
    |> where([event: e], e.state in [:published, :cancelled])
    |> preload([event: e, ticket_tier: tt], event: e, ticket_tier: tt)
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
        broadcast(%Ysc.MessagePassingEvents.TicketReservationCreated{
          ticket_reservation: reservation
        })

        {:ok, reservation}

      {:error, changeset} ->
        {:error, changeset}
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
  List ticket reservations for a user for a specific event.
  """
  def list_ticket_reservations_for_user(user_id, event_id) do
    TicketReservation
    |> join(:inner, [tr], tt in TicketTier, on: tr.ticket_tier_id == tt.id)
    |> where([tr, tt], tr.user_id == ^user_id and tt.event_id == ^event_id)
    |> where([tr], tr.status == "active")
    |> order_by([tr], desc: tr.inserted_at)
    |> Repo.all()
    |> Repo.preload([:ticket_tier, :user, :created_by, :ticket_order])
  end

  @doc """
  List only active reservations for a ticket tier.
  """
  def list_active_reservations_for_tier(tier_id) do
    TicketReservation
    |> where([tr], tr.ticket_tier_id == ^tier_id and tr.status == "active")
    |> order_by([tr], desc: tr.inserted_at)
    |> Repo.all()
    |> Repo.preload([:ticket_tier, :user, :created_by])
  end

  @doc """
  Fulfill a ticket reservation by linking it to a ticket order.
  """
  def fulfill_ticket_reservation(
        %TicketReservation{} = reservation,
        ticket_order_id
      ) do
    reservation
    |> TicketReservation.changeset(%{
      status: "fulfilled",
      fulfilled_at: DateTime.utc_now(),
      ticket_order_id: ticket_order_id
    })
    |> Repo.update()
    |> case do
      {:ok, reservation} ->
        broadcast(%Ysc.MessagePassingEvents.TicketReservationFulfilled{
          ticket_reservation: reservation
        })

        {:ok, reservation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Cancel a ticket reservation.
  """
  def cancel_ticket_reservation(%TicketReservation{} = reservation) do
    reservation
    |> TicketReservation.changeset(%{
      status: "cancelled",
      cancelled_at: DateTime.utc_now()
    })
    |> Repo.update()
    |> case do
      {:ok, reservation} ->
        broadcast(%Ysc.MessagePassingEvents.TicketReservationCancelled{
          ticket_reservation: reservation
        })

        {:ok, reservation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Count total reserved tickets for a tier (active reservations only).
  """
  def count_reserved_tickets_for_tier(tier_id) do
    TicketReservation
    |> where([tr], tr.ticket_tier_id == ^tier_id and tr.status == "active")
    |> select([tr], sum(tr.quantity))
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  @doc """
  Get the quantity of tickets reserved for a specific user and tier.
  """
  def get_user_reserved_quantity(tier_id, user_id) do
    TicketReservation
    |> where(
      [tr],
      tr.ticket_tier_id == ^tier_id and tr.user_id == ^user_id and
        tr.status == "active"
    )
    |> select([tr], sum(tr.quantity))
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Ysc.PubSub, topic(), {__MODULE__, event})
  end
end
