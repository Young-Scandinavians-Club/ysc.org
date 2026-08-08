defmodule YscWeb.EventTvPosterController do
  @moduledoc """
  Serves HTML and raster image previews of 16:9 TV event posters for layout iteration
  and Google Photos upload validation.
  """
  use YscWeb, :controller

  alias Ysc.Events
  alias Ysc.Events.{EventHelpers, TvPosterImage}
  alias YscWeb.Emails.Helpers

  def show(conn, %{"id" => id}) do
    with_event_poster(conn, id, fn conn, assigns ->
      conn
      |> put_root_layout(html: {YscWeb.Layouts, :tv_poster_root})
      |> put_layout(false)
      |> assign(:page_title, "#{assigns.event.title} · TV Poster")
      |> render(:show, assigns)
    end)
  end

  # Poster bytes and MIME type come from TvPosterImage (validated format), not request input.
  # sobelow_skip ["XSS.SendResp", "XSS.ContentType"]
  def image(conn, %{"id" => id} = params) do
    format = TvPosterImage.normalize_format(params["format"])

    with_event_poster(conn, id, fn conn, assigns ->
      case TvPosterImage.capture(assigns, format: format) do
        {:ok, binary} ->
          filename = poster_filename(assigns.event, format)

          conn
          |> put_resp_content_type(TvPosterImage.mime_type(format))
          |> put_resp_header(
            "content-disposition",
            ~s(inline; filename="#{filename}")
          )
          |> send_resp(200, binary)

        {:error, reason} ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(
            503,
            "Could not generate poster image (#{inspect(reason)}). " <>
              "Ensure Chrome/Chromium is available for ChromicPDF."
          )
      end
    end)
  end

  defp with_event_poster(conn, id, fun) do
    case Events.get_event_for_tv_poster(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"404")

      event ->
        fun.(conn, poster_assigns(event))
    end
  end

  defp poster_assigns(event) do
    %{
      event: event,
      event_url: Helpers.absolute_url("/events/#{event.id}"),
      asset_base_url: Helpers.origin() <> "/",
      sold_out: EventHelpers.event_sold_out?(event),
      selling_fast: Map.get(event, :selling_fast, false)
    }
  end

  defp poster_filename(event, format) do
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
end
