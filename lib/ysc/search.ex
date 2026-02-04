defmodule Ysc.Search do
  @moduledoc """
  Context module for global search functionality across multiple entities.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Events.{Event, Ticket}
  alias Ysc.Posts.Post
  alias Ysc.Accounts.User
  alias Ysc.Bookings.Booking

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
      tickets: search_tickets(search_term, search_like, limit),
      users: search_users(search_term, search_like, limit),
      bookings: search_bookings(search_term, search_like, limit)
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

  defp search_tickets(search_term, search_like, limit) do
    from(t in Ticket,
      join: e in assoc(t, :event),
      join: u in assoc(t, :user),
      where:
        ilike(t.reference_id, ^search_like) or
          fragment("SIMILARITY(?, ?) > 0.2", u.email, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term),
      preload: [event: e, user: u],
      order_by: [desc: t.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload([:ticket_tier])
  end

  defp search_users(search_term, _search_like, limit) do
    phone_like = "%#{search_term}%"

    from(u in User,
      where:
        fragment("SIMILARITY(?, ?) > 0.2", u.email, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term) or
          ilike(u.phone_number, ^phone_like),
      order_by: [desc: u.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp search_bookings(search_term, search_like, limit) do
    phone_like = "%#{search_term}%"

    from(b in Booking,
      join: u in assoc(b, :user),
      where:
        ilike(b.reference_id, ^search_like) or
          fragment("SIMILARITY(?, ?) > 0.2", u.email, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term) or
          ilike(u.phone_number, ^phone_like),
      preload: [user: u],
      order_by: [desc: b.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end
end
