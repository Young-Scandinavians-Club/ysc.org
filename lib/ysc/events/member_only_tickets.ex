defmodule Ysc.Events.MemberOnlyTickets do
  @moduledoc """
  Purchasing rules for ticket tiers flagged as "member only".

  The rules are intentionally simple for now and depend only on the buyer's
  membership plan type (`:single`, `:family`, `:lifetime`, or `nil`):

    * `:single`  — may hold at most **one** member-only ticket per event, across
      all member-only tiers combined.
    * `:family` / `:lifetime` — no restriction on member-only tiers.
    * anyone else (no active paid membership) — cannot buy member-only tiers at
      all and must pick from the regular tiers.

  Regular (non member-only) tiers are never affected by these rules.

  All functions accept `TicketTier` structs or plain maps with atom or string
  keys, so they work with the enriched tier maps used on the public event page.
  """

  alias Ysc.Events.TicketTierHelpers

  @single_event_limit 1

  @typedoc "A membership plan type as returned by `Ysc.Accounts.MembershipCache.get_membership_plan_type/1`."
  @type plan_type :: :single | :family | :lifetime | atom() | nil

  @typedoc "Number of member-only tickets a buyer may hold for one event."
  @type limit :: non_neg_integer() | :unlimited

  @doc """
  Returns true when `tier` is a member-only tier.

  Donation tiers are never treated as member-only even if the flag is set.
  """
  def member_only?(tier) when is_map(tier) do
    truthy?(get(tier, :member_only)) and
      not TicketTierHelpers.donation_tier?(tier)
  end

  def member_only?(_), do: false

  @doc "Returns true when any tier in `ticket_tiers` is member-only."
  def any_member_only?(ticket_tiers) when is_list(ticket_tiers) do
    Enum.any?(ticket_tiers, &member_only?/1)
  end

  @doc """
  Max number of member-only tickets the given plan may hold for one event.

  `0` means the buyer is not eligible for member-only tiers at all.
  """
  @spec event_limit(plan_type()) :: limit()
  def event_limit(:single), do: @single_event_limit
  def event_limit(:family), do: :unlimited
  def event_limit(:lifetime), do: :unlimited
  def event_limit(nil), do: 0

  # Unknown but present plan type: be permissive rather than block a paying member.
  def event_limit(_other), do: :unlimited

  @doc "Returns true when the plan may buy at least one member-only ticket."
  @spec eligible?(limit()) :: boolean()
  def eligible?(:unlimited), do: true
  def eligible?(n) when is_integer(n), do: n > 0

  @doc """
  Number of member-only tickets in a `selected_tickets` map (`tier_id => quantity`).

  Non-integer quantities (e.g. donation amounts) count as zero.
  """
  def selected_count(selected_tickets, ticket_tiers)
      when is_map(selected_tickets) and is_list(ticket_tiers) do
    ids = member_only_tier_ids(ticket_tiers)

    Enum.reduce(selected_tickets, 0, fn {tier_id, quantity}, acc ->
      if MapSet.member?(ids, tier_id),
        do: acc + normalize_quantity(quantity),
        else: acc
    end)
  end

  @doc """
  Whether the buyer may add one more ticket for `tier`.

  `already_owned` is the number of member-only tickets the buyer already holds
  (confirmed) for this event. Regular tiers always return true.
  """
  def can_add?(tier, selected_tickets, ticket_tiers, limit, already_owned \\ 0)

  def can_add?(tier, selected_tickets, ticket_tiers, limit, already_owned) do
    if member_only?(tier) do
      case limit do
        :unlimited ->
          true

        n when is_integer(n) ->
          already_owned + selected_count(selected_tickets, ticket_tiers) < n
      end
    else
      true
    end
  end

  @doc """
  Validates a whole `selected_tickets` map against the buyer's plan.

  Returns `:ok`, `{:error, :member_only_not_eligible}` when the plan cannot buy
  member-only tiers at all, or `{:error, :member_only_limit_exceeded}` when the
  selection (plus `already_owned`) would exceed the plan's per-event limit.
  """
  def validate_selection(
        selected_tickets,
        ticket_tiers,
        limit,
        already_owned \\ 0
      ) do
    requested = selected_count(selected_tickets, ticket_tiers)

    cond do
      requested == 0 ->
        :ok

      not eligible?(limit) ->
        {:error, :member_only_not_eligible}

      within_limit?(already_owned + requested, limit) ->
        :ok

      true ->
        {:error, :member_only_limit_exceeded}
    end
  end

  defp within_limit?(_count, :unlimited), do: true
  defp within_limit?(count, n) when is_integer(n), do: count <= n

  defp member_only_tier_ids(ticket_tiers) do
    for tier <- ticket_tiers,
        member_only?(tier),
        into: MapSet.new(),
        do: get(tier, :id)
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

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
end
