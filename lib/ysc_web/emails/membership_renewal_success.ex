defmodule YscWeb.Emails.MembershipRenewalSuccess do
  @moduledoc """
  Email template for membership renewal success notification.

  Notifies users when their membership renewal payment succeeds.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_renewal_success.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias YscWeb.MembershipHelpers

  import YscWeb.Emails.Helpers,
    only: [
      format_date: 1,
      format_membership_money: 1,
      membership_member_assigns: 2
    ]

  def get_template_name() do
    "membership_renewal_success"
  end

  def get_subject(email_data \\ %{}) do
    cond do
      # New proration-based detection
      email_data[:is_upgrade] ->
        "Your YSC Membership Has Been Upgraded! 🎉"

      email_data[:is_downgrade] ->
        "Your YSC Membership Has Been Updated"

      # Legacy Single to Family upgrade detection (without proration details)
      email_data[:is_single_to_family_upgrade] ->
        "Your YSC Membership Has Been Upgraded to Family! 🎉"

      true ->
        "Your YSC Membership Has Been Renewed! 🎉"
    end
  end

  def prepare_email_data(
        user,
        membership_type,
        amount,
        renewal_date,
        billing_reason \\ nil,
        proration_details \\ nil
      ) do
    {is_upgrade, is_downgrade, old_membership_type_name, has_proration} =
      if proration_details do
        old_type_name =
          if proration_details.old_membership_type do
            MembershipHelpers.membership_type_name(
              proration_details.old_membership_type
            )
          else
            nil
          end

        is_up = proration_details.is_upgrade == true
        is_down = proration_details.is_upgrade == false

        {is_up, is_down, old_type_name, true}
      else
        {false, false, nil, false}
      end

    # Legacy: Single to Family upgrade detection (for backward compatibility)
    is_single_to_family_upgrade =
      billing_reason in ["subscription_update", :subscription_update] and
        membership_type in [:family, "family"] and not has_proration

    user
    |> membership_member_assigns(membership_type)
    |> Map.merge(%{
      amount: format_membership_money(amount),
      renewal_date: format_date(renewal_date),
      is_single_to_family_upgrade: is_single_to_family_upgrade,
      is_upgrade: is_upgrade,
      is_downgrade: is_downgrade,
      old_membership_type: old_membership_type_name,
      has_proration: has_proration
    })
  end
end
