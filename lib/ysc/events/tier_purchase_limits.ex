defmodule Ysc.Events.TierPurchaseLimits do
  @moduledoc """
  Per-buyer ticket count limits on a ticket tier (`max_per_buyer`).

  An event manager can cap how many tickets of one tier a single buyer may hold
  for the event, e.g. "members can buy member tickets, but only 1 guest ticket
  (+1)" is a member-only tier with no limit plus a guest tier with
  `max_per_buyer: 1`.

  The limit counts the tickets the buyer already holds (confirmed) for the
  tier plus the quantity in the current selection. `nil` means no limit.
  Donation tiers are never limited. It is independent of, and combines with,
  the plan rules in `Ysc.Events.MemberOnlyTickets`.

  All functions accept `TicketTier` structs or plain maps with atom or string
  keys, so they work with the enriched tier maps used on the public event page.
  """

  alias Ysc.Events.TicketTierHelpers

  @doc "The tier's per-buyer limit as a positive integer, or `nil` when unlimited."
  @spec limit(map() | nil) :: pos_integer() | nil
  def limit(tier) when is_map(tier) do
    with false <- TicketTierHelpers.donation_tier?(tier),
         n when is_integer(n) and n > 0 <- get(tier, :max_per_buyer) do
      n
    else
      _ -> nil
    end
  end

  def limit(_), do: nil

  @doc "Returns true when `tier` has a per-buyer limit."
  @spec limited?(map() | nil) :: boolean()
  def limited?(tier), do: limit(tier) != nil

  @doc "Returns true when any tier in `ticket_tiers` has a per-buyer limit."
  def any_limited?(ticket_tiers) when is_list(ticket_tiers) do
    Enum.any?(ticket_tiers, &limited?/1)
  end

  @doc "Ids of the tiers in `ticket_tiers` that have a per-buyer limit."
  def limited_tier_ids(ticket_tiers) when is_list(ticket_tiers) do
    for tier <- ticket_tiers, limited?(tier), do: get(tier, :id)
  end

  @doc """
  Tickets of `tier` the buyer can still add, or `:unlimited` when the tier has
  no limit. `owned` is how many of this tier the buyer already holds.
  """
  @spec remaining(map(), map(), non_neg_integer()) ::
          non_neg_integer() | :unlimited
  def remaining(tier, selected_tickets, owned \\ 0) do
    case limit(tier) do
      nil ->
        :unlimited

      n ->
        max(n - owned - selected_quantity(selected_tickets, get(tier, :id)), 0)
    end
  end

  @doc """
  Whether the buyer may add one more ticket for `tier`.

  `owned` is the number of tickets of this tier the buyer already holds
  (confirmed) for the event. Unlimited tiers always return true.
  """
  @spec can_add?(map(), map(), non_neg_integer()) :: boolean()
  def can_add?(tier, selected_tickets, owned \\ 0) do
    remaining(tier, selected_tickets, owned) != 0
  end

  @doc """
  Validates a whole `selected_tickets` map (`tier_id => quantity`).

  `owned_by_tier` maps `tier_id => tickets already held`; missing ids count as
  zero. Returns `:ok` or `{:error, :tier_purchase_limit_exceeded}`.
  """
  def validate_selection(selected_tickets, ticket_tiers, owned_by_tier \\ %{})
      when is_map(selected_tickets) and is_list(ticket_tiers) do
    exceeded? =
      Enum.any?(ticket_tiers, fn tier ->
        case limit(tier) do
          nil ->
            false

          n ->
            id = get(tier, :id)

            Map.get(owned_by_tier, id, 0) +
              selected_quantity(selected_tickets, id) > n
        end
      end)

    if exceeded?, do: {:error, :tier_purchase_limit_exceeded}, else: :ok
  end

  @doc "Quantity selected for `tier_id`; non-integer values count as zero."
  def selected_quantity(selected_tickets, tier_id)
      when is_map(selected_tickets) do
    normalize_quantity(Map.get(selected_tickets, tier_id))
  end

  defp normalize_quantity(n) when is_integer(n) and n > 0, do: n

  defp normalize_quantity(n) when is_binary(n) do
    case Integer.parse(n) do
      {int, _} when int > 0 -> int
      _ -> 0
    end
  end

  defp normalize_quantity(_), do: 0

  defp get(tier, key) when is_map(tier) do
    Map.get(tier, key) || Map.get(tier, Atom.to_string(key))
  end
end
