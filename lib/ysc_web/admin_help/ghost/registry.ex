defmodule YscWeb.AdminHelp.Ghost.Registry do
  @moduledoc """
  Allowlisted ghost preview slugs for admin help illustrations.
  """

  @previews %{
    "getting-started-login" => %{active_page: nil, public?: true},
    "getting-started-dashboard" => %{active_page: :dashboard},
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
    "check-in-desk" => %{active_page: :events, sidebar?: false},
    "scanner" => %{active_page: :scanner, sidebar?: false},
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

  @doc """
  Basename for a print asset file (without extension).

  Scroll variants use `slug--scroll-target`, e.g.
  `newsletter-compose--ghost-newsletter-preview-panel`.
  """
  def print_asset_basename(slug, scroll_to \\ nil)

  def print_asset_basename(slug, scroll_to)
      when is_binary(slug) and (is_nil(scroll_to) or scroll_to == "") do
    slug
  end

  def print_asset_basename(slug, scroll_to)
      when is_binary(slug) and is_binary(scroll_to) do
    "#{slug}--#{scroll_to}"
  end

  @doc """
  Unique ghost pages to capture for print/PDF, derived from guide steps plus
  every registered preview slug (base image only).
  """
  def capture_targets do
    guide_targets =
      YscWeb.AdminHelp.Registry.all()
      |> Enum.flat_map(& &1.steps())
      |> Enum.flat_map(&capture_targets_for_step/1)

    base_targets = Enum.map(all(), &%{slug: &1, scroll_to: nil})

    (guide_targets ++ base_targets)
    |> Enum.uniq_by(fn %{slug: slug, scroll_to: scroll_to} ->
      {slug, scroll_to}
    end)
    |> Enum.sort_by(fn %{slug: slug, scroll_to: scroll_to} ->
      {slug, scroll_to || ""}
    end)
  end

  @doc "Maps `ghost:slug` guide images to static print fallbacks."
  def print_image_path(image, opts \\ [])

  def print_image_path("ghost:" <> slug, opts) when is_binary(slug) do
    scroll_to = Keyword.get(opts, :scroll_to)
    dir = print_images_dir()

    scroll_to
    |> print_path_candidates(slug)
    |> resolve_print_path(dir)
  end

  def print_image_path(path, _opts) when is_binary(path), do: path

  defp capture_targets_for_step(step) do
    step_targets(step[:image], step[:image_scroll]) ++
      step_targets(step[:public_image], step[:public_image_scroll])
  end

  defp step_targets(nil, _scroll), do: []

  defp step_targets("ghost:" <> slug, scroll) when is_binary(slug) do
    base = [%{slug: slug, scroll_to: nil}]

    if is_binary(scroll) and scroll != "" do
      base ++ [%{slug: slug, scroll_to: scroll}]
    else
      base
    end
  end

  defp step_targets(_image, _scroll), do: []

  defp print_path_candidates(nil, slug), do: [slug]
  defp print_path_candidates("", slug), do: [slug]

  defp print_path_candidates(scroll_to, slug) do
    [print_asset_basename(slug, scroll_to), slug]
  end

  defp resolve_print_path(candidates, dir) do
    Enum.find_value(candidates, fn basename ->
      cond do
        File.exists?(Path.join(dir, "#{basename}.png")) ->
          "/images/admin-help/#{basename}.png"

        File.exists?(Path.join(dir, "#{basename}.svg")) ->
          "/images/admin-help/#{basename}.svg"

        true ->
          nil
      end
    end) || "/images/admin-help/#{hd(candidates)}.png"
  end

  defp print_images_dir do
    Path.join([
      Application.app_dir(:ysc, "priv"),
      "static",
      "images",
      "admin-help"
    ])
  end
end
