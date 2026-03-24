defmodule YscWeb.MembershipHelpers do
  @moduledoc """
  Shared helpers for building membership-related display data used across
  LiveViews such as HomeLive and UserSettingsLive.
  """

  @doc """
  Builds a map of display details for the "My Membership QR" modal.

  Returns a map with type_label, plan_type, member_since, renewal_date,
  is_sub_account, and primary_name — or nil if assigns don't include a
  logged-in user with a current membership.
  """
  def build_membership_qr_details(%{
        current_user: user,
        current_membership: membership,
        is_sub_account: is_sub_account,
        primary_user: primary_user
      }) do
    plan_type = YscWeb.UserAuth.get_membership_plan_type(membership)
    renewal_date = YscWeb.UserAuth.get_membership_renewal_date(membership)

    type_label =
      case plan_type do
        :lifetime ->
          "Lifetime Membership"

        nil ->
          "Active Membership"

        other ->
          other
          |> Atom.to_string()
          |> String.split("_")
          |> List.first()
          |> String.capitalize()
          |> then(&"#{&1} Membership")
      end

    member_since =
      cond do
        is_struct(membership) && membership.type == :lifetime &&
            not is_nil(membership.awarded_at) ->
          membership.awarded_at

        is_struct(membership) && not is_nil(membership.start_date) ->
          membership.start_date

        not is_nil(user.inserted_at) ->
          user.inserted_at

        true ->
          nil
      end

    primary_name =
      if is_sub_account && primary_user do
        "#{primary_user.first_name} #{primary_user.last_name}"
      end

    %{
      type_label: type_label,
      plan_type: plan_type,
      member_since: member_since,
      renewal_date: renewal_date,
      is_sub_account: is_sub_account,
      primary_name: primary_name
    }
  end

  def build_membership_qr_details(_assigns), do: nil
end
