defmodule YscWeb.Api.EventsJSON do
  @moduledoc """
  JSON rendering for the upcoming events mobile API.
  """

  def index(%{events: events, meta: meta}) do
    %{
      data: Enum.map(events, &event/1),
      meta: meta
    }
  end

  defp event(e) do
    %{
      id: to_string(e.id),
      reference_id: e.reference_id,
      state: e.state,
      title: e.title,
      description: e.description,
      start_date: e.start_date && DateTime.to_iso8601(e.start_date),
      start_time: e.start_time && Time.to_iso8601(e.start_time),
      end_date: e.end_date && DateTime.to_iso8601(e.end_date),
      end_time: e.end_time && Time.to_iso8601(e.end_time),
      location_name: e.location_name,
      address: e.address,
      latitude: e.latitude,
      longitude: e.longitude,
      age_restriction: e.age_restriction,
      max_attendees: e.max_attendees,
      tickets_tbd: e.tickets_tbd,
      partiful_link: e.partiful_link,
      selling_fast: e.selling_fast,
      recent_tickets_count: e.recent_tickets_count,
      ticket_count: Map.get(e, :ticket_count),
      pricing_info: pricing_info(Map.get(e, :pricing_info)),
      ticket_tiers: ticket_tiers(Map.get(e, :ticket_tiers, [])),
      cover_image: cover_image(Map.get(e, :image))
    }
  end

  defp pricing_info(nil), do: nil

  defp pricing_info(p) do
    %{
      display_text: p.display_text,
      has_free_tiers: p.has_free_tiers,
      lowest_price: p.lowest_price && Money.to_string!(p.lowest_price.price)
    }
  end

  defp ticket_tiers(tiers) when is_list(tiers) do
    Enum.map(tiers, fn t ->
      %{
        id: to_string(t.id),
        name: t.name,
        description: t.description,
        type: t.type,
        price: t.price && Money.to_string!(t.price),
        quantity: t.quantity,
        tickets_sold: Map.get(t, :tickets_sold, 0),
        available: Map.get(t, :available),
        requires_registration: t.requires_registration,
        start_date: t.start_date && DateTime.to_iso8601(t.start_date),
        end_date: t.end_date && DateTime.to_iso8601(t.end_date)
      }
    end)
  end

  defp ticket_tiers(_), do: []

  defp cover_image(nil), do: nil

  defp cover_image(img) do
    %{
      id: to_string(img.id),
      optimized_path: img.optimized_image_path,
      thumbnail_path: img.thumbnail_path,
      blur_hash: img.blur_hash,
      width: img.width,
      height: img.height,
      alt_text: img.alt_text
    }
  end
end
