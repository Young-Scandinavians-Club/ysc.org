defmodule Ysc.Events.TvPosterImage do
  @moduledoc """
  Renders TV event poster HTML to a raster image (PNG/JPEG/WebP) for preview and upload.
  """

  alias Ysc.Events.EventHelpers
  alias YscWeb.Emails.Helpers

  @poster_width 1920
  @poster_height 1080
  @formats ~w(png jpeg webp)

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

  defp impl do
    Application.get_env(
      :ysc,
      :tv_poster_image_module,
      Ysc.Events.TvPosterImage.Chromic
    )
  end
end
