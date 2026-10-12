defmodule Ysc.Events.PricingDisplay do
  @moduledoc """
  Shared public-event pricing copy.

  Returns the `%{display_text, has_free_tiers, lowest_price}` map attached as
  `:pricing_info` on listings and the event page.
  """

  alias Ysc.Events.TicketTierHelpers
  alias Ysc.MoneyHelper

  @tickets_coming_soon "Tickets Coming Soon"

  @doc """
  Pricing info for an event given its ticket tiers.

  When `tickets_tbd` is true, returns the coming-soon placeholder regardless
  of loaded tiers.
  """
  def pricing_info(event, ticket_tiers) do
    if Map.get(event, :tickets_tbd) do
      %{
        display_text: @tickets_coming_soon,
        has_free_tiers: false,
        lowest_price: nil
      }
    else
      from_tiers(ticket_tiers)
    end
  end

  @doc """
  Pricing info from ticket tiers only (ignores `tickets_tbd`).

  Use `pricing_info/2` when the event may still be in coming-soon mode.
  """
  def from_tiers([]),
    do: %{display_text: "Free", has_free_tiers: true, lowest_price: nil}

  def from_tiers(ticket_tiers) do
    has_free_tiers = Enum.any?(ticket_tiers, &TicketTierHelpers.free_tier?/1)

    paid_tiers =
      Enum.filter(ticket_tiers, fn tier ->
        (tier.type == :paid or tier.type == "paid") && tier.price != nil
      end)

    case {has_free_tiers, paid_tiers} do
      {true, []} ->
        %{display_text: "Free", has_free_tiers: true, lowest_price: nil}

      {true, _paid_tiers} ->
        %{display_text: "From $0.00", has_free_tiers: true, lowest_price: nil}

      {false, []} ->
        %{display_text: "Free", has_free_tiers: false, lowest_price: nil}

      {false, paid_tiers} ->
        lowest_price =
          Enum.min_by(paid_tiers, & &1.price.amount, fn -> nil end)

        display_text =
          if length(paid_tiers) == 1 do
            MoneyHelper.format_price(lowest_price.price)
          else
            "From #{MoneyHelper.format_price(lowest_price.price)}"
          end

        %{
          display_text: display_text,
          has_free_tiers: false,
          lowest_price: lowest_price
        }
    end
  end
end
