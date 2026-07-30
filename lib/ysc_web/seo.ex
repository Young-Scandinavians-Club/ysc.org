defmodule YscWeb.SEO do
  @moduledoc """
  Helpers for public page SEO and social link previews (Open Graph / Twitter Cards).

  LiveViews assign `:page_title`, `:meta_description`, and optional `:og_*` values;
  `YscWeb.Layouts.root` emits the corresponding `<head>` tags so external sites
  (Slack, iMessage, Facebook, X, etc.) can show title, description, and image.
  """

  alias Ysc.Media.Image
  alias Ysc.Events.Event
  alias Ysc.Posts.Post

  @default_description "Young Scandinavians Club — community, events, and cabins in California."
  @default_og_image_path "/images/ysc_logo.webp"
  @max_description_length 160

  @doc """
  Default site description used when a page does not set `:meta_description`.
  """
  def default_description, do: @default_description

  @doc """
  Default Open Graph image path (relative) when content has no featured/cover image.

  Uses the YSC logo so link previews stay on-brand when a page has no special
  share image (unlike events/posts with a cover or featured image).
  """
  def default_og_image_path, do: @default_og_image_path

  @doc """
  Absolute default Open Graph image URL (YSC logo).
  """
  def default_og_image_url, do: absolute_image_url(@default_og_image_path)

  @doc """
  Open Graph image URL for a page, falling back to the YSC logo.
  """
  def og_image_or_default(nil), do: default_og_image_url()
  def og_image_or_default(""), do: default_og_image_url()
  def og_image_or_default(url) when is_binary(url), do: url

  @doc """
  Twitter card type for an OG image URL.

  Custom photos use `summary_large_image`; the square logo default uses `summary`.
  """
  def twitter_card_for_image(nil), do: "summary"

  def twitter_card_for_image(url) when is_binary(url) do
    if url == default_og_image_url() or
         String.ends_with?(url, @default_og_image_path) do
      "summary"
    else
      "summary_large_image"
    end
  end

  @doc """
  Builds an absolute public URL for a path that starts with `/`.
  """
  def absolute_url("/" <> _rest = path), do: origin() <> path

  @doc """
  Turns an image path or full URL into an absolute HTTPS URL for `og:image`.

  Returns `nil` for blank input. Paths already starting with `http` are returned as-is.
  Relative paths (with or without a leading `/`) are prefixed with the site origin.
  """
  def absolute_image_url(nil), do: nil
  def absolute_image_url(""), do: nil

  def absolute_image_url("http://" <> _ = url), do: url
  def absolute_image_url("https://" <> _ = url), do: url

  def absolute_image_url("/" <> _ = path), do: absolute_url(path)

  def absolute_image_url(path) when is_binary(path),
    do: absolute_image_url("/" <> path)

  @doc """
  Best absolute image URL for a `Ysc.Media.Image`, or `nil` when missing.
  """
  def image_url(nil), do: nil

  def image_url(%Image{} = image) do
    image
    |> Image.display_path()
    |> absolute_image_url()
  end

  def image_url(%{raw_image_path: _} = image) do
    image
    |> Image.display_path()
    |> absolute_image_url()
  end

  def image_url(_), do: nil

  @doc """
  Truncates description text for meta/OG tags (max #{@max_description_length} chars).

  Blank or nil input returns `nil` so callers can apply their own fallback.
  """
  def truncate_description(nil), do: nil

  def truncate_description(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        nil

      String.length(trimmed) <= @max_description_length ->
        trimmed

      true ->
        trimmed
        |> String.slice(0, @max_description_length - 1)
        |> String.trim_trailing()
        |> Kernel.<>("…")
    end
  end

  @doc """
  SEO assigns for a published (or previewable) post.

  Uses the post title, plain-text preview/body for description, featured image
  as the link poster, and the canonical `/posts/:slug` URL.
  """
  def assigns_for_post(%Post{} = post) do
    description =
      case truncate_description(YscWeb.PlainText.from_post(post)) do
        nil -> "Read this article on the Young Scandinavians Club news feed."
        text -> text
      end

    slug = post.url_name || post.id
    path = "/posts/#{slug}"

    %{
      page_title: post.title,
      meta_description: description,
      og_type: "article",
      og_url: absolute_url(path),
      og_image:
        image_url(loaded_assoc(post, :featured_image)) || default_og_image_url(),
      canonical_url: absolute_url(path)
    }
  end

  @doc """
  SEO assigns for an event detail page.

  Uses the event title, short `description` field, cover image as the link poster,
  and the canonical `/events/:id` URL.
  """
  def assigns_for_event(%Event{} = event) do
    description =
      truncate_description(event.description) ||
        "View event details and purchase tickets on Young Scandinavians Club."

    path = "/events/#{event.id}"

    %{
      page_title: event.title,
      meta_description: description,
      og_type: "website",
      og_url: absolute_url(path),
      og_image:
        image_url(loaded_assoc(event, :cover_image)) || default_og_image_url(),
      canonical_url: absolute_url(path)
    }
  end

  @doc """
  Merges SEO assigns onto a LiveView socket.
  """
  def assign_seo(socket, %{} = seo_assigns) do
    Enum.reduce(seo_assigns, socket, fn {key, value}, acc ->
      Phoenix.Component.assign(acc, key, value)
    end)
  end

  defp origin, do: String.trim_trailing(YscWeb.Endpoint.url(), "/")

  defp loaded_assoc(struct, field) do
    case Map.get(struct, field) do
      %Ecto.Association.NotLoaded{} -> nil
      value -> value
    end
  end
end
