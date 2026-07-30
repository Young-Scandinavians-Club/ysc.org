defmodule YscWeb.EventTvPosterController do
  @moduledoc """
  Serves HTML and raster image previews of 16:9 TV event posters for layout iteration
  and Google Photos upload validation.
  """
  use YscWeb, :controller

  alias Ysc.Events
  alias Ysc.Events.{TicketTierHelpers, TvPosterImage}
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
      sold_out: event_sold_out?(event),
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

  defp event_sold_out?(event) do
    now = DateTime.utc_now()
    ticket_tiers = Map.get(event, :ticket_tiers) || []

    non_donation_tiers =
      Enum.reject(ticket_tiers, &TicketTierHelpers.donation_tier?/1)

    if non_donation_tiers == [] do
      false
    else
      relevant_tiers =
        Enum.filter(non_donation_tiers, fn tier ->
          TicketTierHelpers.tier_on_sale?(tier, now) ||
            TicketTierHelpers.tier_sale_ended?(tier, now)
        end)

      if relevant_tiers == [] do
        false
      else
        all_tiers_sold_out =
          Enum.all?(relevant_tiers, fn tier ->
            get_available_quantity(tier) == 0
          end)

        event_at_capacity =
          case Map.get(event, :max_attendees) do
            nil ->
              false

            max_attendees ->
              (Map.get(event, :ticket_count) || 0) >= max_attendees
          end

        all_tiers_sold_out || event_at_capacity
      end
    end
  end

  defp get_available_quantity(ticket_tier) do
    quantity = Map.get(ticket_tier, :quantity)

    sold_count = Map.get(ticket_tier, :sold_tickets_count) || 0

    case quantity do
      nil -> :unlimited
      0 -> :unlimited
      qty -> max(0, qty - sold_count)
    end
  end
end
