defmodule Ysc.Events.TierAudience do
  @moduledoc """
  Who a ticket tier is sold to (`TicketTier.sale_audience`).

    * `:member_guests` — the default. Sold to active members, typically for the
      guests they bring. This is how every tier worked before public sales.
    * `:members_only` — sold to active members for themselves, subject to the
      per-plan limits in `Ysc.Events.MemberOnlyTickets`.
    * `:public` — sold to anyone, no membership required.

  `member_only` on the tier is kept in sync with `:members_only` so the
  member-only rules keep working unchanged.

  All functions accept `TicketTier` structs or plain maps with atom or string
  keys, so they work with the enriched tier maps used on the public event page.
  """

  alias Ysc.Events.MemberOnlyTickets
  alias Ysc.Events.TicketTierHelpers

  @audiences [:member_guests, :members_only, :public]

  @typedoc "The kind of visitor looking at a tier."
  @type viewer :: :anonymous | :non_member | :member

  @typedoc "Whether a viewer can buy a tier now, or what they must do first."
  @type access :: :available | :sign_in_required | :membership_required

  @doc "All audiences, in the order shown in the admin form."
  def audiences, do: @audiences

  @doc "Options for the admin form's \"Who can buy\" select."
  def options do
    [
      {"Members buying for guests", "member_guests"},
      {"Members only", "members_only"},
      {"Public — anyone can buy", "public"}
    ]
  end

  @doc "Short label for an audience, used in admin badges."
  def label(:public), do: "Public"
  def label(:members_only), do: "Members only"
  def label(:member_guests), do: "Member guests"

  @doc """
  The tier's audience.

  Falls back to the legacy `member_only` flag when `sale_audience` is missing,
  so maps built before the column existed keep their meaning. Donation tiers
  are never members-only (see `MemberOnlyTickets.member_only?/1`).
  """
  @spec audience(map()) :: :member_guests | :members_only | :public
  def audience(tier) when is_map(tier) do
    case normalize(get(tier, :sale_audience)) do
      :public ->
        :public

      :members_only ->
        if TicketTierHelpers.donation_tier?(tier),
          do: :member_guests,
          else: :members_only

      :member_guests ->
        :member_guests

      nil ->
        if MemberOnlyTickets.member_only?(tier),
          do: :members_only,
          else: :member_guests
    end
  end

  @doc "Returns true when anyone may buy `tier`, membership or not."
  def public?(tier) when is_map(tier), do: audience(tier) == :public
  def public?(_), do: false

  @doc "Returns true when any tier in `tiers` is sold to the public."
  def any_public?(tiers) when is_list(tiers), do: Enum.any?(tiers, &public?/1)

  @doc """
  Returns true when `tiers` is non-empty and every tier is sold to the public.

  A checkout may skip the membership requirement only in this case.
  """
  def all_public?([]), do: false
  def all_public?(tiers) when is_list(tiers), do: Enum.all?(tiers, &public?/1)

  @doc """
  Whether `viewer` can buy `tier` now, or what they have to do first.

  Plan-specific member-only limits are not considered here; see
  `Ysc.Events.MemberOnlyTickets`.
  """
  @spec access(map(), viewer()) :: access()
  def access(tier, viewer) do
    cond do
      public?(tier) -> :available
      viewer == :member -> :available
      viewer == :anonymous -> :sign_in_required
      true -> :membership_required
    end
  end

  defp normalize(value) when value in @audiences, do: value

  defp normalize(value) when is_binary(value) do
    Enum.find(@audiences, &(Atom.to_string(&1) == value))
  end

  defp normalize(_), do: nil

  defp get(tier, key),
    do: Map.get(tier, key) || Map.get(tier, Atom.to_string(key))
end
