defmodule Ysc.Events.TvPosterImage do
  @moduledoc """
  Renders TV event poster HTML to a raster image (PNG/JPEG/WebP) for preview and upload.
  """

  alias Ysc.Events.DateTimeFormatter
  alias Ysc.Events.EventHelpers
  alias Ysc.Media.Image
  alias YscWeb.Emails.Helpers

  @poster_width 1920
  @poster_height 1080
  @formats ~w(png jpeg webp)

  # Bump when a visual change is not reflected in the poster HEEx sources
  # hashed below (for example a CSS-only or QR-encoder change).
  @fingerprint_version 1

  @poster_component_path Path.expand(
                           "../../ysc_web/components/events/event_tv_poster.ex",
                           __DIR__
                         )
  @capture_document_path Path.expand(
                           "../../ysc_web/controllers/event_tv_poster_html/capture_document.html.heex",
                           __DIR__
                         )

  @external_resource @poster_component_path
  @external_resource @capture_document_path

  @layout_fingerprint Base.encode16(
                        :crypto.hash(
                          :sha256,
                          File.read!(@poster_component_path) <>
                            File.read!(@capture_document_path)
                        ),
                        case: :lower
                      )

  @doc """
  Captures the TV poster for an event as image bytes.

  ## Options

    * `:format` - `"png"` (default), `"jpeg"`, or `"webp"`

  Returns `{:ok, binary}` or `{:error, term}`.
  """
  @spec capture(map(), keyword()) :: {:ok, binary()} | {:error, term()}
  def capture(assigns, opts \\ []) do
    format = normalize_format(Keyword.get(opts, :format, "png"))

    html = build_html(assigns)
    impl().capture_html(html, format: format)
  end

  @doc "Assigns used to render the TV poster for an event loaded for posters."
  def assigns_for_event(event) do
    %{
      event: event,
      event_url: Helpers.event_url(event.id),
      asset_base_url: Helpers.origin() <> "/",
      sold_out: EventHelpers.event_sold_out?(event),
      selling_fast: Map.get(event, :selling_fast, false)
    }
  end

  @doc """
  SHA-256 fingerprint of the values a TV poster shows.

  Google Photos sync uses this to skip Chromic capture and upload when the
  poster would look the same. It hashes the visible assigns (title, date,
  price, cover path, badges, QR URL) plus a compile-time hash of the poster
  template sources, instead of HEEx-rendering the 1920×1080 document for
  every upcoming event on every run.
  """
  def hash_event(event) do
    event
    |> assigns_for_event()
    |> hash_assigns()
  end

  @doc false
  def hash_assigns(assigns) do
    assigns
    |> fingerprint()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc false
  def hash_html(assigns) do
    assigns
    |> build_html()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "Download/upload filename for an event's poster, e.g. `summer-gala-tv-poster.png`."
  def filename(event, format) do
    slug =
      event.title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "event"
        s -> s
      end

    "#{slug}-tv-poster.#{format}"
  end

  @doc "Supported image formats for capture."
  def formats, do: @formats

  @doc "Poster pixel dimensions `{width, height}`."
  def dimensions, do: {@poster_width, @poster_height}

  @doc false
  def build_html(assigns) do
    asset_base_url =
      Map.get(assigns, :asset_base_url) || Helpers.origin() <> "/"

    assigns =
      assigns
      |> Map.put(:asset_base_url, asset_base_url)
      |> Map.put_new(:sold_out, false)
      |> Map.put_new(:selling_fast, false)

    Phoenix.Template.render_to_string(
      YscWeb.EventTvPosterHTML,
      "capture_document",
      "html",
      assigns
    )
  end

  @doc false
  def mime_type("png"), do: "image/png"
  def mime_type("jpeg"), do: "image/jpeg"
  def mime_type("webp"), do: "image/webp"

  @doc false
  def normalize_format(format) when format in @formats, do: format

  def normalize_format(nil), do: "png"

  def normalize_format(format) when is_binary(format) do
    format
    |> String.downcase()
    |> String.trim()
    |> case do
      "jpg" -> "jpeg"
      other when other in @formats -> other
      _ -> "png"
    end
  end

  defp fingerprint(assigns) do
    event = Map.fetch!(assigns, :event)
    image = Map.get(event, :image)

    :erlang.term_to_binary(
      {@fingerprint_version, @layout_fingerprint,
       visible_poster_values(assigns, event, image)}
    )
  end

  defp visible_poster_values(assigns, event, image) do
    {
      Map.get(assigns, :event_url),
      Map.get(assigns, :asset_base_url) || Helpers.origin() <> "/",
      Map.get(assigns, :sold_out, false),
      Map.get(assigns, :selling_fast, false),
      Map.get(event, :id),
      Map.get(event, :title),
      Map.get(event, :description),
      Map.get(event, :location_name),
      DateTimeFormatter.format_event_start(event, separator: " · "),
      Map.get(event, :state),
      Map.get(event, :tickets_tbd),
      Image.display_path_with_fallback(image),
      poster_image_alt(image, event),
      poster_pricing_text(event)
    }
  end

  defp poster_image_alt(image, event) do
    case image do
      %Image{alt_text: alt} when is_binary(alt) and alt != "" ->
        alt

      %Image{title: title} when is_binary(title) and title != "" ->
        title

      _ ->
        Map.get(event, :title) || "Event image"
    end
  end

  defp poster_pricing_text(event) do
    case Map.get(event, :pricing_info) do
      %{display_text: text} when is_binary(text) -> text
      _ -> "See event for details"
    end
  end

  defp impl do
    Application.get_env(
      :ysc,
      :tv_poster_image_module,
      Ysc.Events.TvPosterImage.Chromic
    )
  end
end
