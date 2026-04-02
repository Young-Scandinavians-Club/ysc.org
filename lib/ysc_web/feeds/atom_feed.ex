defmodule YscWeb.Feeds.AtomFeed do
  @moduledoc false

  alias Atomex.{Feed, Entry}

  @site_author "Young Scandinavians Club"

  @doc """
  Atom 1.0 document for upcoming public events.
  """
  def events_feed(events) do
    base = endpoint_url()
    feed_url = base <> "/feeds/events.atom"
    alternate_url = base <> "/events"
    updated = events_feed_updated(events)

    entries =
      Enum.map(events, fn event ->
        entry_url = base <> "/events/#{event.id}"
        updated_at = datetime(event.updated_at)
        published_at = event_published_at(event)

        entry =
          Entry.new(entry_url, updated_at, event.title || "Event")
          |> Entry.link(entry_url, rel: "alternate", type: "text/html")
          |> maybe_entry_summary(event.description)
          |> maybe_entry_html_content(event.rendered_details)
          |> Entry.published(published_at)

        Entry.build(entry)
      end)

    Feed.new(feed_url, updated, "YSC Events")
    |> Feed.author(@site_author)
    |> Feed.link(feed_url, rel: "self", type: "application/atom+xml")
    |> Feed.link(alternate_url,
      rel: "alternate",
      type: "text/html",
      title: "Events"
    )
    |> Feed.generator()
    |> Feed.entries(entries)
    |> Feed.build()
    |> Atomex.generate_document()
  end

  @doc """
  Atom 1.0 document for recently published posts (club news).
  """
  def posts_feed(posts) do
    base = endpoint_url()
    feed_url = base <> "/feeds/posts.atom"
    alternate_url = base <> "/news"

    entries =
      Enum.map(posts, fn post ->
        slug = post.url_name || to_string(post.id)
        entry_url = base <> "/posts/#{slug}"
        updated_at = datetime(post.updated_at)
        published_at = datetime(post.published_on || post.inserted_at)

        entry =
          Entry.new(entry_url, updated_at, post.title || "Post")
          |> Entry.link(entry_url, rel: "alternate", type: "text/html")
          |> maybe_entry_summary(post.preview_text)
          |> maybe_entry_html_content(post.rendered_body)
          |> Entry.published(published_at)
          |> maybe_post_author(post)

        Entry.build(entry)
      end)

    updated = posts_feed_updated(posts)

    Feed.new(feed_url, updated, "YSC Club News")
    |> Feed.author(@site_author)
    |> Feed.link(feed_url, rel: "self", type: "application/atom+xml")
    |> Feed.link(alternate_url,
      rel: "alternate",
      type: "text/html",
      title: "Club News"
    )
    |> Feed.generator()
    |> Feed.entries(entries)
    |> Feed.build()
    |> Atomex.generate_document()
  end

  defp events_feed_updated([]), do: DateTime.utc_now()

  defp events_feed_updated(events) do
    events
    |> Enum.map(&datetime(&1.updated_at))
    |> Enum.max(DateTime)
  end

  defp posts_feed_updated([]), do: DateTime.utc_now()

  defp posts_feed_updated(posts) do
    posts
    |> Enum.map(&datetime(&1.updated_at))
    |> Enum.max(DateTime)
  end

  defp event_published_at(event) do
    cond do
      event.published_at -> datetime(event.published_at)
      event.start_date -> datetime(event.start_date)
      true -> DateTime.utc_now()
    end
  end

  defp maybe_entry_summary(entry, text) when text in [nil, ""], do: entry

  defp maybe_entry_summary(entry, text) do
    Entry.summary(entry, text, "text")
  end

  defp maybe_entry_html_content(entry, html) when html in [nil, ""], do: entry

  defp maybe_entry_html_content(entry, html) do
    Entry.content(entry, html, type: "html")
  end

  defp maybe_post_author(entry, post) do
    case post.author do
      %{first_name: f, last_name: l} = _ ->
        name =
          [Ysc.title_case(f || ""), Ysc.title_case(l || "")]
          |> Enum.join(" ")
          |> String.trim()

        if name != "" do
          Entry.author(entry, name)
        else
          entry
        end

      _ ->
        entry
    end
  end

  defp datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp datetime(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp datetime(nil), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp endpoint_url, do: String.trim_trailing(YscWeb.Endpoint.url(), "/")
end
