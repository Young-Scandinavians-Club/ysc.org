defmodule Ysc.Events.Picker do
  @moduledoc """
  Lookups behind the admin event picker (`<.admin_event_autocomplete>`).

  Pickers return slim maps (`id`, `title`, `start_date`, `state`) instead of
  full events, since the picker only shows a title and a date.

    * `suggestions/1` - what to offer before anyone types: the next upcoming
      events (soonest first), then the most recent past ones.
    * `search/2` - typo-tolerant title search (`pg_trgm`) that also matches
      reference ids.
  """
  import Ecto.Query

  alias Ysc.Events.Event
  alias Ysc.Repo

  @upcoming_suggestions 8
  @recent_suggestions 4
  @default_search_limit 10
  # Below this `word_similarity`, a title is not close enough to the query.
  @min_similarity 0.3

  @doc """
  Events to offer before a search: up to #{@upcoming_suggestions} upcoming
  (soonest first) followed by up to #{@recent_suggestions} recent past ones
  (latest first). Deleted events are never offered.
  """
  def suggestions(now \\ DateTime.utc_now()) do
    cutoff = today_start(now)
    Repo.all(upcoming_query(cutoff)) ++ Repo.all(recent_query(cutoff))
  end

  @doc """
  The first instant of today's California calendar day, as stored on events.

  Event dates are calendar days kept at midnight UTC, so an event happening
  today sits *before* the current instant. Comparing against this cutoff keeps
  today's events in the upcoming group.
  """
  def today_start(now \\ DateTime.utc_now()) do
    today =
      now
      |> DateTime.shift_zone!("America/Los_Angeles")
      |> DateTime.to_date()

    DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
  end

  @doc "True when the event is today or later (California calendar day)."
  def upcoming?(event, now \\ DateTime.utc_now())

  def upcoming?(%{start_date: %DateTime{} = start_date}, now),
    do: DateTime.compare(start_date, today_start(now)) != :lt

  def upcoming?(_event, _now), do: true

  @doc """
  Events whose title or reference id matches `query`, best match first.

  Titles match on a substring or, for typos and word-order slips, on trigram
  similarity. Ties go to the event closest to now: upcoming events beat past
  ones, since an order is most likely for something that has not happened yet.
  """
  def search(query, opts \\ []) when is_binary(query) do
    cutoff = opts |> Keyword.get(:now, DateTime.utc_now()) |> today_start()
    limit = Keyword.get(opts, :limit, @default_search_limit)

    query
    |> search_query(cutoff, limit)
    |> Repo.all()
  end

  @doc "The picker's summary of a single event, or `nil` when it is gone."
  def get(id) do
    visible_events()
    |> where([e], e.id == ^id)
    |> summarize()
    |> Repo.one()
  end

  defp upcoming_query(cutoff) do
    visible_events()
    |> where([e], e.start_date >= ^cutoff)
    |> order_by([e], asc: e.start_date)
    |> limit(@upcoming_suggestions)
    |> summarize()
  end

  defp recent_query(cutoff) do
    visible_events()
    |> where([e], e.start_date < ^cutoff)
    |> order_by([e], desc: e.start_date)
    |> limit(@recent_suggestions)
    |> summarize()
  end

  defp search_query(query, cutoff, limit) do
    like = "%" <> escape_like(String.trim(query)) <> "%"
    term = String.trim(query)

    visible_events()
    |> where(
      [e],
      ilike(e.title, ^like) or ilike(e.reference_id, ^like) or
        fragment("word_similarity(?, ?) > ?", ^term, e.title, ^@min_similarity)
    )
    |> order_by([e],
      desc: ilike(e.title, ^like) or ilike(e.reference_id, ^like),
      desc: fragment("word_similarity(?, ?)", ^term, e.title),
      desc: e.start_date >= ^cutoff,
      asc: fragment("abs(extract(epoch from ? - ?))", e.start_date, ^cutoff)
    )
    |> limit(^limit)
    |> summarize()
  end

  defp visible_events do
    from(e in Event, where: e.state != :deleted)
  end

  defp summarize(query) do
    select(query, [e], %{
      id: e.id,
      title: e.title,
      start_date: e.start_date,
      state: e.state
    })
  end

  defp escape_like(term), do: String.replace(term, ~r/([\\%_])/, "\\\\\\1")

  @doc false
  def ci_query_explain_query, do: search_query("happy", today_start(), 10)

  @doc false
  def ci_query_explain_suggestions_query, do: upcoming_query(today_start())
end
