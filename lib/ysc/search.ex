defmodule Ysc.Search do
  @moduledoc """
  Context module for global search functionality across multiple entities.
  """
  import Ecto.Query, warn: false

  alias Ysc.Accounts
  alias Ysc.Repo
  alias Ysc.Events.{Event, Ticket}
  alias Ysc.Posts.Post
  alias Ysc.Accounts.User
  alias Ysc.Bookings.Booking

  @min_staff_name_search_length 3

  @doc """
  Performs a global search across Events, Posts, Tickets, Users, and Bookings.
  Returns results grouped by type.
  """
  def global_search(search_term, limit \\ 5)

  def global_search(search_term, limit)
      when is_binary(search_term) and search_term != "" do
    search_like = "%#{search_term}%"

    %{
      events: search_events(search_term, search_like, limit),
      posts: search_posts(search_term, search_like, limit),
      tickets: search_tickets(search_term, limit),
      users: search_users(search_term, limit),
      bookings: search_bookings(search_term, limit)
    }
  end

  def global_search(_search_term, _limit),
    do: %{events: [], posts: [], tickets: [], users: [], bookings: []}

  defp search_events(search_term, search_like, limit) do
    from(e in Event,
      where:
        fragment("SIMILARITY(?, ?) > 0.2", e.title, ^search_term) or
          ilike(e.title, ^search_like) or
          ilike(e.description, ^search_like) or
          ilike(e.reference_id, ^search_like),
      preload: [:organizer],
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp search_posts(search_term, search_like, limit) do
    from(p in Post,
      where:
        fragment("SIMILARITY(?, ?) > 0.2", p.title, ^search_term) or
          ilike(p.title, ^search_like) or
          ilike(p.preview_text, ^search_like),
      preload: [:author],
      order_by: [desc: p.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp search_tickets(search_term, limit) do
    trimmed = String.trim(search_term)

    cond do
      staff_lookup_full_email?(trimmed) ->
        email_lower = String.downcase(trimmed)

        from(t in Ticket,
          join: e in assoc(t, :event),
          join: u in assoc(t, :user),
          where: fragment("lower(?)", u.email) == ^email_lower,
          preload: [event: e, user: u],
          order_by: [desc: t.inserted_at],
          limit: ^limit
        )
        |> Repo.all()
        |> Repo.preload([:ticket_tier])

      staff_reference_query?(trimmed, "TKT") ->
        search_like = "%#{trimmed}%"

        from(t in Ticket,
          join: e in assoc(t, :event),
          join: u in assoc(t, :user),
          where: ilike(t.reference_id, ^search_like),
          preload: [event: e, user: u],
          order_by: [desc: t.inserted_at],
          limit: ^limit
        )
        |> Repo.all()
        |> Repo.preload([:ticket_tier])

      String.length(trimmed) < @min_staff_name_search_length ->
        []

      true ->
        search_like = "%#{trimmed}%"

        from(t in Ticket,
          join: e in assoc(t, :event),
          join: u in assoc(t, :user),
          where:
            ilike(t.reference_id, ^search_like) or
              fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^trimmed) or
              fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^trimmed),
          preload: [event: e, user: u],
          order_by: [desc: t.inserted_at],
          limit: ^limit
        )
        |> Repo.all()
        |> Repo.preload([:ticket_tier])
    end
  end

  defp search_users(search_term, limit) do
    Accounts.search_users_for_staff_lookup(search_term, limit: limit)
  end

  defp search_bookings(search_term, limit) do
    trimmed = String.trim(search_term)

    cond do
      staff_lookup_full_email?(trimmed) ->
        email_lower = String.downcase(trimmed)

        from(b in Booking,
          join: u in assoc(b, :user),
          where: fragment("lower(?)", u.email) == ^email_lower,
          preload: [user: u],
          order_by: [desc: b.inserted_at],
          limit: ^limit
        )
        |> Repo.all()

      staff_reference_query?(trimmed, "BKG") ->
        search_like = "%#{trimmed}%"

        from(b in Booking,
          join: u in assoc(b, :user),
          where: ilike(b.reference_id, ^search_like),
          preload: [user: u],
          order_by: [desc: b.inserted_at],
          limit: ^limit
        )
        |> Repo.all()

      String.length(trimmed) < @min_staff_name_search_length ->
        []

      true ->
        search_like = "%#{trimmed}%"

        from(b in Booking,
          join: u in assoc(b, :user),
          where:
            ilike(b.reference_id, ^search_like) or
              fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^trimmed) or
              fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^trimmed),
          preload: [user: u],
          order_by: [desc: b.inserted_at],
          limit: ^limit
        )
        |> Repo.all()
    end
  end

  defp staff_lookup_full_email?(query) do
    String.contains?(query, "@") and
      String.match?(query, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
  end

  defp staff_reference_query?(query, prefix) do
    String.match?(query, ~r/^(?i)#{prefix}-/)
  end

  @doc false
  def ci_query_explain_events_query do
    search_term = "ci"
    search_like = "%ci%"
    limit = 5

    from(e in Event,
      where:
        fragment("SIMILARITY(?, ?) > 0.2", e.title, ^search_term) or
          ilike(e.title, ^search_like) or
          ilike(e.description, ^search_like) or
          ilike(e.reference_id, ^search_like),
      preload: [:organizer],
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
  end

  @doc false
  def ci_query_explain_tickets_query do
    search_like = "%ci%"
    limit = 5
    trimmed = "ci"

    from(t in Ticket,
      join: e in assoc(t, :event),
      join: u in assoc(t, :user),
      where:
        ilike(t.reference_id, ^search_like) or
          fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^trimmed) or
          fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^trimmed),
      preload: [event: e, user: u],
      order_by: [desc: t.inserted_at],
      limit: ^limit
    )
  end

  @doc false
  def ci_query_explain_users_query do
    search_like = "%ci%"
    limit = 5

    from(u in User,
      where: u.state == :active,
      where:
        ilike(u.first_name, ^search_like) or
          ilike(u.last_name, ^search_like) or
          ilike(
            fragment("? || ' ' || ?", u.first_name, u.last_name),
            ^search_like
          ),
      order_by: [asc: u.last_name, asc: u.first_name],
      limit: ^limit
    )
  end

  @doc false
  def ci_query_explain_query, do: ci_query_explain_events_query()
end
