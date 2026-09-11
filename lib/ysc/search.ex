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

  # Magic-search dropdown fields. Omits hashed_password, board_bio, event/post
  # body HTML, booking JSON, and unused ticket_tier rows — the admin typeahead
  # only renders titles, names, emails, and reference ids.
  @search_user_fields [:id, :email, :first_name, :last_name]
  @search_event_fields [:id, :title, :reference_id, :organizer_id]
  @search_post_fields [:id, :title, :user_id]
  @search_ticket_fields [:id, :reference_id, :event_id, :user_id]
  @search_booking_fields [
    :id,
    :reference_id,
    :property,
    :checkin_date,
    :checkout_date,
    :user_id
  ]

  @doc """
  Performs a global search across Events, Posts, Tickets, Users, and Bookings.
  Returns results grouped by type.

  Each category is a slim `select: struct` load (name/title/reference only).
  Do not JOIN full `users` / `events` / `posts` rows — the dropdown never
  renders password hashes, bios, or body HTML.
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
    search_term
    |> search_events_query(search_like, limit)
    |> Repo.all()
  end

  defp search_events_query(search_term, search_like, limit) do
    organizer_query = search_user_preload_query()

    from(e in Event,
      where:
        fragment("SIMILARITY(?, ?) > 0.2", e.title, ^search_term) or
          ilike(e.title, ^search_like) or
          ilike(e.description, ^search_like) or
          ilike(e.reference_id, ^search_like),
      select: struct(e, ^@search_event_fields),
      preload: [organizer: ^organizer_query],
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
  end

  defp search_posts(search_term, search_like, limit) do
    search_term
    |> search_posts_query(search_like, limit)
    |> Repo.all()
  end

  defp search_posts_query(search_term, search_like, limit) do
    author_query = search_user_preload_query()

    from(p in Post,
      where:
        fragment("SIMILARITY(?, ?) > 0.2", p.title, ^search_term) or
          ilike(p.title, ^search_like) or
          ilike(p.preview_text, ^search_like),
      select: struct(p, ^@search_post_fields),
      preload: [author: ^author_query],
      order_by: [desc: p.inserted_at],
      limit: ^limit
    )
  end

  defp search_tickets(search_term, search_like, limit) do
    search_term
    |> search_tickets_query(search_like, limit)
    |> Repo.all()
  end

  defp search_tickets_query(search_term, search_like, limit) do
    user_query = search_user_preload_query()
    event_query = search_event_preload_query()

    from(t in Ticket,
      join: u in assoc(t, :user),
      where:
        ilike(t.reference_id, ^search_like) or
          fragment("SIMILARITY(?::text, ?) > 0.2", u.email, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term),
      select: struct(t, ^@search_ticket_fields),
      preload: [event: ^event_query, user: ^user_query],
      order_by: [desc: t.inserted_at],
      limit: ^limit
    )
  end

  defp search_users(search_term, _search_like, limit) do
    search_term
    |> search_users_query(limit)
    |> Repo.all()
  end

  defp search_users_query(search_term, limit) do
    phone_like = "%#{search_term}%"

    from(u in User,
      where:
        fragment("SIMILARITY(?::text, ?) > 0.2", u.email, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term) or
          ilike(u.phone_number, ^phone_like),
      select: struct(u, ^@search_user_fields),
      order_by: [desc: u.inserted_at],
      limit: ^limit
    )
  end

  defp search_bookings(search_term, search_like, limit) do
    search_term
    |> search_bookings_query(search_like, limit)
    |> Repo.all()
  end

  defp search_bookings_query(search_term, search_like, limit) do
    user_query = search_user_preload_query()
    phone_like = "%#{search_term}%"

    from(b in Booking,
      join: u in assoc(b, :user),
      where:
        ilike(b.reference_id, ^search_like) or
          fragment("SIMILARITY(?::text, ?) > 0.2", u.email, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term) or
          ilike(u.phone_number, ^phone_like),
      select: struct(b, ^@search_booking_fields),
      preload: [user: ^user_query],
      order_by: [desc: b.inserted_at],
      limit: ^limit
    )
  end

  defp search_user_preload_query do
    from(u in User, select: struct(u, ^@search_user_fields))
  end

  defp search_event_preload_query do
    from(e in Event, select: struct(e, ^@search_event_fields))
  end

  @doc false
  def ci_query_explain_events_query do
    search_events_query("ci", "%ci%", 5)
  end

  @doc false
  def ci_query_explain_tickets_query do
    search_tickets_query("ci", "%ci%", 5)
  end

  @doc false
  def ci_query_explain_users_query do
    search_users_query("ci", 5)
  end

  @doc false
  def ci_query_explain_posts_query do
    search_posts_query("ci", "%ci%", 5)
  end

  @doc false
  def ci_query_explain_bookings_query do
    search_bookings_query("ci", "%ci%", 5)
  end

  @doc false
  def ci_query_explain_query, do: ci_query_explain_events_query()
end
