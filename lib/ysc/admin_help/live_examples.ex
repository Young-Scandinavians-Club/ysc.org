defmodule Ysc.AdminHelp.LiveExamples do
  @moduledoc """
  Read-only live-data snapshots for the admin help assistant.

  Alongside the markdown knowledge base, the assistant can request real
  examples from the database — recent posts, events, and newsletter editions —
  so answers can reference what actually exists on the site ("your last
  newsletter went to 312 subscribers", "the Midsummer event is still a draft").

  Only the allowlisted snapshots below can be fetched, they are capped at
  ten rows, and they expose titles/states/dates only — never member names,
  emails, or other personal data.
  """

  alias Ysc.Events
  alias Ysc.Newsletter
  alias Ysc.Posts

  @limit 10

  @doc "Lists available snapshots in the same shape as the knowledge base index."
  def index do
    [
      %{
        slug: "live-recent-posts",
        title: "Live data: recent posts",
        summary:
          "The #{@limit} most recently created news posts on this site with state, dates, and public URLs."
      },
      %{
        slug: "live-recent-events",
        title: "Live data: recent events",
        summary:
          "The #{@limit} most recently created events on this site with state, start date, capacity, and registration setup."
      },
      %{
        slug: "live-recent-newsletters",
        title: "Live data: recent newsletters",
        summary:
          "The #{@limit} most recent newsletter editions on this site with status, send time, and emails sent."
      }
    ]
  end

  @doc "Compact index for an LLM system prompt — one line per snapshot."
  def index_for_llm do
    Enum.map_join(index(), "\n", fn %{
                                      slug: slug,
                                      title: title,
                                      summary: summary
                                    } ->
      "- #{slug}: #{title} — #{summary}"
    end)
  end

  @doc """
  Fetches a snapshot by slug. Returns `{:ok, text}` or `:error`.
  """
  def fetch("live-recent-posts"), do: posts_snapshot()
  def fetch("live-recent-events"), do: events_snapshot()
  def fetch("live-recent-newsletters"), do: newsletters_snapshot()
  def fetch(_), do: :error

  defp posts_snapshot do
    case Posts.list_posts_paginated(%{page_size: @limit}, []) do
      {:ok, {posts, _meta}} ->
        {:ok,
         snapshot(
           "the #{@limit} most recently created posts (newest first, deleted excluded)",
           Enum.map_join(posts, "\n", &post_line/1)
         )}

      _ ->
        :error
    end
  end

  defp events_snapshot do
    case Events.list_events_paginated(%{page_size: @limit}, []) do
      {:ok, {events, _meta}} ->
        {:ok,
         snapshot(
           "the #{@limit} most recently created events (newest first, deleted excluded)",
           Enum.map_join(events, "\n", &event_line/1)
         )}

      _ ->
        :error
    end
  end

  defp newsletters_snapshot do
    case Newsletter.list_paginated_editions(%{page_size: @limit}) do
      {:ok, {editions, _meta}} ->
        {:ok,
         snapshot(
           "the #{@limit} most recent newsletter editions (newest first)",
           Enum.map_join(editions, "\n", &edition_line/1)
         )}

      _ ->
        :error
    end
  end

  defp snapshot(what, ""), do: header(what) <> "(none yet)"
  defp snapshot(what, lines), do: header(what) <> lines

  defp header(what) do
    """
    Live snapshot of #{what}, taken #{format_datetime(DateTime.utc_now())}.
    Real data from this site — use it for concrete examples, never invent entries.

    """
  end

  defp post_line(post) do
    case to_string(post.state) do
      "published" ->
        ~s(- "#{post.title}" — published #{format_date(post.published_on)}, public URL: /posts/#{post.url_name})

      state ->
        ~s(- "#{post.title}" — #{state}, created #{format_date(post.inserted_at)})
    end
  end

  defp event_line(event) do
    start =
      case event.start_date do
        nil -> "no date set yet"
        date -> "starts #{format_datetime(date)}"
      end

    ~s(- "#{event.title}" — #{event.state}, #{start}, #{event_capacity(event)}, registration: #{event_registration(event)})
  end

  defp event_capacity(%{max_attendees: max})
       when is_integer(max) and max > 0,
       do: "max #{max} attendees"

  defp event_capacity(_), do: "unlimited capacity"

  defp event_registration(%{partiful_link: link})
       when is_binary(link) and link != "",
       do: "external via Partiful"

  defp event_registration(%{tickets_tbd: true}), do: "tickets TBD"
  defp event_registration(_), do: "built-in ticketing"

  defp edition_line(edition) do
    detail =
      case to_string(edition.status) do
        "sent" ->
          "sent #{format_datetime(edition.sent_at)} to #{edition.sent_count || 0} recipients"

        "sending" ->
          "sending right now"

        "scheduled" ->
          "scheduled for #{format_datetime(edition.scheduled_at)}"

        status ->
          "#{status}, created #{format_date(edition.inserted_at)}"
      end

    ~s(- "#{edition.title}" — subject: "#{edition.subject}", #{detail})
  end

  defp format_date(nil), do: "unknown date"
  defp format_date(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")

  defp format_datetime(nil), do: "unknown time"

  defp format_datetime(datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
end
