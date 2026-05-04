defmodule Ysc.Sitemap do
  @moduledoc """
  Generates an XML sitemap for search engine crawlers.

  The generated XML is cached for 1 hour via Cachex. Call `invalidate/0`
  to force regeneration on the next request (e.g. after publishing content).
  """

  import Ecto.Query

  alias Ysc.Events.Event
  alias Ysc.Newsletter.Edition
  alias Ysc.Posts.Post
  alias Ysc.Repo

  @cache_key "sitemap:xml"
  @cache_ttl :timer.hours(1)

  @doc """
  Returns the sitemap XML string, using a cached version when available.
  """
  def generate do
    case Cachex.get(:ysc_cache, @cache_key) do
      {:ok, nil} -> build_and_cache()
      {:ok, xml} -> xml
      {:error, _reason} -> build_and_cache()
    end
  end

  @doc """
  Clears the cached sitemap so it will be regenerated on the next request.
  """
  def invalidate do
    Cachex.del(:ysc_cache, @cache_key)
  end

  defp build_and_cache do
    xml = build_xml()
    Cachex.put(:ysc_cache, @cache_key, xml, expire: @cache_ttl)
    xml
  end

  defp build_xml do
    base = YscWeb.Endpoint.url()

    entries =
      (static_urls(base) ++
         event_urls(base) ++ post_urls(base) ++ edition_urls(base))
      |> Enum.map_join("\n", &url_entry/1)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{entries}
    </urlset>
    """
    |> String.trim()
  end

  defp url_entry(url) do
    children =
      [
        {:loc, escape(url.loc)},
        {:lastmod, url[:lastmod] && format_date(url.lastmod)},
        {:changefreq, url[:changefreq]},
        {:priority, url[:priority]}
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.map_join("\n", fn {tag, val} -> "    <#{tag}>#{val}</#{tag}>" end)

    "  <url>\n#{children}\n  </url>"
  end

  defp static_urls(base) do
    [
      %{loc: "#{base}/", changefreq: "daily", priority: 1.0},
      %{loc: "#{base}/events", changefreq: "daily", priority: 0.9},
      %{loc: "#{base}/news", changefreq: "daily", priority: 0.8},
      %{loc: "#{base}/newsletters", changefreq: "weekly", priority: 0.6},
      %{loc: "#{base}/volunteer", changefreq: "monthly", priority: 0.5},
      %{loc: "#{base}/contact", changefreq: "monthly", priority: 0.5},
      %{loc: "#{base}/bookings/tahoe", changefreq: "daily", priority: 0.7},
      %{loc: "#{base}/bookings/clear-lake", changefreq: "daily", priority: 0.7},
      %{loc: "#{base}/history", changefreq: "yearly", priority: 0.4},
      %{loc: "#{base}/board", changefreq: "monthly", priority: 0.4},
      %{loc: "#{base}/bylaws", changefreq: "yearly", priority: 0.3},
      %{loc: "#{base}/code-of-conduct", changefreq: "yearly", priority: 0.3},
      %{loc: "#{base}/privacy-policy", changefreq: "yearly", priority: 0.3},
      %{loc: "#{base}/terms-of-service", changefreq: "yearly", priority: 0.3}
    ]
  end

  defp event_urls(base) do
    from(e in Event,
      where: e.state == :published,
      select: %{id: e.id, updated_at: e.updated_at}
    )
    |> Repo.all()
    |> Enum.map(fn event ->
      %{
        loc: "#{base}/events/#{event.id}",
        lastmod: event.updated_at,
        changefreq: "weekly",
        priority: 0.7
      }
    end)
  end

  defp post_urls(base) do
    from(p in Post,
      where: p.state == :published,
      select: %{url_name: p.url_name, id: p.id, updated_at: p.updated_at}
    )
    |> Repo.all()
    |> Enum.map(fn post ->
      slug = post.url_name || post.id

      %{
        loc: "#{base}/posts/#{slug}",
        lastmod: post.updated_at,
        changefreq: "monthly",
        priority: 0.6
      }
    end)
  end

  defp edition_urls(base) do
    from(e in Edition,
      where: e.status == :sent,
      select: %{id: e.id, sent_at: e.sent_at, updated_at: e.updated_at}
    )
    |> Repo.all()
    |> Enum.map(fn edition ->
      %{
        loc: "#{base}/newsletters/#{edition.id}",
        lastmod: edition.sent_at || edition.updated_at,
        changefreq: "never",
        priority: 0.4
      }
    end)
  end

  defp format_date(%DateTime{} = dt),
    do: dt |> DateTime.to_date() |> Date.to_iso8601()

  defp format_date(%NaiveDateTime{} = ndt),
    do: ndt |> NaiveDateTime.to_date() |> Date.to_iso8601()

  defp format_date(%Date{} = d), do: Date.to_iso8601(d)
  defp format_date(_), do: nil

  defp escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("'", "&apos;")
    |> String.replace("\"", "&quot;")
  end
end
