defmodule YscWeb.AdminHelp.Ghost.Registry do
  @moduledoc """
  Allowlisted ghost preview slugs for admin help illustrations.
  """

  @previews %{
    "getting-started-dashboard" => %{active_page: nil, public?: true},
    "getting-started-sidebar" => %{active_page: :dashboard},
    "posts-list" => %{active_page: :news},
    "posts-editor" => %{active_page: :news},
    "posts-settings" => %{active_page: :news},
    "posts-publish" => %{active_page: :news},
    "newsletter-compose" => %{active_page: :newsletters},
    "newsletter-subscribers" => %{active_page: :newsletters},
    "events-list" => %{active_page: :events},
    "events-edit" => %{active_page: :events},
    "events-tickets" => %{active_page: :events},
    "events-updates" => %{active_page: :events},
    "media-gallery" => %{active_page: :media},
    "check-in-desk" => %{active_page: :events},
    "scanner" => %{active_page: :scanner},
    "public-news-list" => %{active_page: nil, public?: true},
    "public-news-pinned" => %{active_page: nil, public?: true},
    "public-news-article" => %{active_page: nil, public?: true},
    "public-events-list" => %{active_page: nil, public?: true},
    "public-event-page" => %{active_page: nil, public?: true},
    "public-event-agenda" => %{active_page: nil, public?: true},
    "public-event-tickets" => %{active_page: nil, public?: true},
    "public-event-ticket-tiers" => %{active_page: nil, public?: true},
    "public-event-tickets-tbd" => %{active_page: nil, public?: true},
    "public-event-updates" => %{active_page: nil, public?: true},
    "public-newsletter-archive" => %{active_page: nil, public?: true},
    "public-newsletter-edition" => %{active_page: nil, public?: true}
  }

  def all, do: Map.keys(@previews)

  def fetch(slug) when is_binary(slug) do
    case Map.fetch(@previews, slug) do
      :error -> :error
      {:ok, meta} -> {:ok, Map.put(meta, :slug, slug)}
    end
  end

  def valid?(slug), do: Map.has_key?(@previews, slug)

  @doc "Maps `ghost:slug` guide images to static print fallbacks."
  def print_image_path("ghost:" <> slug) when is_binary(slug) do
    dir =
      Path.join([
        Application.app_dir(:ysc, "priv"),
        "static",
        "images",
        "admin-help"
      ])

    cond do
      File.exists?(Path.join(dir, "#{slug}.png")) ->
        "/images/admin-help/#{slug}.png"

      File.exists?(Path.join(dir, "#{slug}.svg")) ->
        "/images/admin-help/#{slug}.svg"

      true ->
        "/images/admin-help/#{slug}.svg"
    end
  end

  def print_image_path(path) when is_binary(path), do: path
end
