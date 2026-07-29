defmodule Ysc.Events.TicketTierHelpers do
  @moduledoc """
  Shared predicates and sale-window checks for ticket tiers.

  Works with `TicketTier` structs, plain maps (atom or string keys), and raw
  tier types.
  """

  alias Ysc.Events.TicketTier

  @donation_types [:donation, "donation"]

  @doc """
  Returns true when the tier or type represents a donation tier.
  """
  def donation_tier?(type) when type in @donation_types, do: true
  def donation_tier?(%TicketTier{type: type}), do: donation_tier?(type)
  def donation_tier?(%{type: type}), do: donation_tier?(type)
  def donation_tier?(%{"type" => type}), do: donation_tier?(type)
  def donation_tier?(_), do: false

  @doc """
  Returns true when a ticket's tier is a donation tier.
  """
  def donation_ticket?(%{ticket_tier: tier}), do: donation_tier?(tier)
  def donation_ticket?(_), do: false

  @doc """
  Returns true when the tier sale has started (ignores end date).

  Booking validation uses this check; sale end is not enforced there today.
  """
  def tier_sale_started?(tier, now \\ DateTime.utc_now()) do
    case tier_start_date(tier) do
      nil -> true
      start_date -> DateTime.compare(now, start_date) != :lt
    end
  end

  @doc """
  Returns true when the tier is currently on sale (started and not ended).
  """
  def tier_on_sale?(tier, now \\ DateTime.utc_now()) do
    tier_sale_started?(tier, now) and not tier_sale_ended?(tier, now)
  end

  @doc """
  Returns true when the tier sale window has ended.
  """
  def tier_sale_ended?(tier, now \\ DateTime.utc_now()) do
    case tier_end_date(tier) do
      nil -> false
      end_date -> DateTime.compare(now, end_date) == :gt
    end
  end

  defp tier_start_date(%TicketTier{start_date: start_date}), do: start_date
  defp tier_start_date(tier) when is_map(tier), do: get_field(tier, :start_date)

  defp tier_end_date(%TicketTier{end_date: end_date}), do: end_date
  defp tier_end_date(tier) when is_map(tier), do: get_field(tier, :end_date)

  defp get_field(map, field) do
    Map.get(map, field) || Map.get(map, Atom.to_string(field))
  end
end
