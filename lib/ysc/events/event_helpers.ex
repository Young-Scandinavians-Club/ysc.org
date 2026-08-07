defmodule Ysc.Events.EventHelpers do
  @moduledoc """
  Shared event-level display predicates for the web layer.
  """

  alias Ysc.Events
  alias Ysc.Events.TicketTierHelpers
  alias Ysc.Tickets

  @doc """
  Returns true when all relevant non-donation ticket tiers are sold out or the
  event has reached `max_attendees` capacity.

  Works with Event structs and plain maps. Uses preloaded `:ticket_tiers` when
  present; otherwise loads tiers for the event. Uses preloaded `:ticket_count`
  when present; otherwise queries via `Tickets.event_at_capacity?/1` when
  `max_attendees` is set.
  """
  def event_sold_out?(event, now \\ DateTime.utc_now()) do
    ticket_tiers = ticket_tiers_for_event(event)

    non_donation_tiers =
      Enum.reject(ticket_tiers, &TicketTierHelpers.donation_tier?/1)

    if Enum.empty?(non_donation_tiers) do
      false
    else
      relevant_tiers =
        Enum.filter(non_donation_tiers, fn tier ->
          TicketTierHelpers.tier_on_sale?(tier, now) ||
            TicketTierHelpers.tier_sale_ended?(tier, now)
        end)

      if Enum.empty?(relevant_tiers) do
        false
      else
        all_tiers_sold_out =
          Enum.all?(relevant_tiers, fn tier ->
            tier_available_quantity(tier) == 0
          end)

        all_tiers_sold_out || event_at_capacity?(event)
      end
    end
  end

  defp ticket_tiers_for_event(event) do
    case get_field(event, :ticket_tiers) do
      nil ->
        event_id = get_field(event, :id)

        if event_id do
          Events.list_ticket_tiers_for_event(event_id)
        else
          []
        end

      tiers ->
        tiers
    end
  end

  defp event_at_capacity?(event) do
    case get_field(event, :max_attendees) do
      nil ->
        false

      max_attendees ->
        case get_field(event, :ticket_count) do
          nil ->
            Tickets.event_at_capacity?(event)

          ticket_count ->
            ticket_count >= max_attendees
        end
    end
  end

  defp tier_available_quantity(ticket_tier) do
    quantity = get_field(ticket_tier, :quantity)
    sold_count = get_field(ticket_tier, :sold_tickets_count) || 0

    case quantity do
      nil -> :unlimited
      0 -> :unlimited
      qty -> max(0, qty - sold_count)
    end
  end

  defp get_field(map, field) do
    Map.get(map, field) || Map.get(map, Atom.to_string(field))
  end
end
