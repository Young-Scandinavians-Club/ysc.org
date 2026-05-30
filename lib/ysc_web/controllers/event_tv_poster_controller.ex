defmodule YscWeb.EventTvPosterController do
  @moduledoc """
  Serves HTML previews of 16:9 TV event posters for layout iteration.

  Future ChromicPDF screenshot capture will render the same template.
  """
  use YscWeb, :controller

  alias Ysc.Events
  alias YscWeb.Emails.Helpers

  def show(conn, %{"id" => id}) do
    case Events.get_event_for_tv_poster(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"404")

      event ->
        sold_out = event_sold_out?(event)
        selling_fast = Map.get(event, :selling_fast, false)

        conn
        |> put_root_layout(html: {YscWeb.Layouts, :tv_poster_root})
        |> put_layout(false)
        |> assign(:page_title, "#{event.title} · TV Poster")
        |> render(:show,
          event: event,
          event_url: Helpers.absolute_url("/events/#{event.id}"),
          sold_out: sold_out,
          selling_fast: selling_fast
        )
    end
  end

  defp event_sold_out?(event) do
    now = DateTime.utc_now()
    ticket_tiers = Map.get(event, :ticket_tiers) || []

    non_donation_tiers =
      Enum.reject(ticket_tiers, fn tier ->
        Map.get(tier, :type) in [:donation, "donation"]
      end)

    if non_donation_tiers == [] do
      false
    else
      relevant_tiers =
        Enum.filter(non_donation_tiers, fn tier ->
          tier_on_sale?(tier, now) || tier_sale_ended?(tier, now)
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

  defp tier_on_sale?(ticket_tier, now) do
    start_date = Map.get(ticket_tier, :start_date)
    end_date = Map.get(ticket_tier, :end_date)

    sale_started =
      case start_date do
        nil -> true
        sd -> DateTime.compare(now, sd) != :lt
      end

    sale_ended =
      case end_date do
        nil -> false
        ed -> DateTime.compare(now, ed) == :gt
      end

    sale_started && !sale_ended
  end

  defp tier_sale_ended?(ticket_tier, now) do
    case Map.get(ticket_tier, :end_date) do
      nil -> false
      ed -> DateTime.compare(now, ed) == :gt
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
