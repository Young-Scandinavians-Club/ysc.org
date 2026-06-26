defmodule Ysc.Tickets.Display do
  @moduledoc """
  Formats ticket tier names and quantity summaries for UI and ledger copy.

  Centralizes the "2x VIP, 1x General Admission" pattern used in payment
  history, ledger descriptions, and similar summaries.
  """

  @default_tier_name "General Admission"

  @doc """
  Returns a tier display name, defaulting missing names to #{@default_tier_name}.
  """
  def tier_name(nil), do: @default_tier_name
  def tier_name(name) when is_binary(name), do: name

  @doc """
  Groups tickets by tier and returns a comma-separated quantity summary.

  ## Options

    * `:exclude_cancelled` - when true, omits tickets with status `:cancelled`
  """
  def format_tier_quantities(tickets, opts \\ []) when is_list(tickets) do
    tickets
    |> tickets_for_summary(opts)
    |> Enum.group_by(&tier_name_from_ticket/1)
    |> Enum.map_join(", ", fn {tier_name, tier_tickets} ->
      "#{length(tier_tickets)}x #{tier_name(tier_name)}"
    end)
  end

  @doc """
  Payment-history summary for a ticket order's tickets.

  Returns `"No ticket details"` when tickets are nil, `"All tickets refunded"`
  when every ticket is cancelled, and appends `(N refunded)` when applicable.
  """
  def format_order_ticket_summary(nil), do: "No ticket details"

  def format_order_ticket_summary(tickets) when is_list(tickets) do
    refunded_count = Enum.count(tickets, &cancelled?/1)
    active_tickets = Enum.reject(tickets, &cancelled?/1)

    ticket_summary =
      if active_tickets == [] do
        "All tickets refunded"
      else
        format_tier_quantities(active_tickets)
      end

    if refunded_count > 0 do
      "#{ticket_summary} (#{refunded_count} refunded)"
    else
      ticket_summary
    end
  end

  @doc """
  Ledger description for complimentary ticket orders.
  """
  def format_ledger_order_description(ticket_order) do
    event_title =
      if ticket_order.event, do: ticket_order.event.title, else: "Event"

    case ticket_order.tickets do
      tickets when is_list(tickets) and tickets != [] ->
        ticket_summary = format_tier_quantities(tickets)
        "Free Tickets: #{event_title} (#{ticket_summary})"

      _ ->
        "Free Tickets: #{event_title}"
    end
  end

  defp tickets_for_summary(tickets, opts) do
    if Keyword.get(opts, :exclude_cancelled, false) do
      Enum.reject(tickets, &cancelled?/1)
    else
      tickets
    end
  end

  defp tier_name_from_ticket(%{ticket_tier: %{name: name}}), do: name
  defp tier_name_from_ticket(%{ticket_tier: nil}), do: nil
  defp tier_name_from_ticket(%{ticket_tier: %Ecto.Association.NotLoaded{}}), do: nil
  defp tier_name_from_ticket(_), do: nil

  defp cancelled?(%{status: :cancelled}), do: true
  defp cancelled?(_), do: false
end
