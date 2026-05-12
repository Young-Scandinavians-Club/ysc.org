defmodule YscWeb.Emails.MembershipRenewalSuccess do
  @moduledoc """
  Email template for membership renewal success notification.

  Notifies users when their membership renewal payment succeeds.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_renewal_success.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [member_greeting_name: 1]

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
    # Validate input
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    # Ensure user has required fields
    first_name = member_greeting_name(user)
    membership_type_name = get_membership_type_name(membership_type)

    # Format amount
    amount_str = format_money(amount)

    # Format renewal date
    renewal_date_str = format_date(renewal_date)

    # Extract proration details if available
    {is_upgrade, is_downgrade, old_membership_type_name, has_proration} =
      if proration_details do
        old_type_name =
          if proration_details.old_membership_type do
            get_membership_type_name(proration_details.old_membership_type)
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

    %{
      first_name: first_name,
      membership_type: membership_type_name,
      amount: amount_str,
      renewal_date: renewal_date_str,
      is_single_to_family_upgrade: is_single_to_family_upgrade,
      is_upgrade: is_upgrade,
      is_downgrade: is_downgrade,
      old_membership_type: old_membership_type_name,
      has_proration: has_proration
    }
  end

  defp get_membership_type_name(:single), do: "Single"
  defp get_membership_type_name(:family), do: "Family"
  defp get_membership_type_name("single"), do: "Single"
  defp get_membership_type_name("family"), do: "Family"
  defp get_membership_type_name(_), do: "Membership"

  defp format_money(%Money{} = money) do
    Money.to_string!(money)
  end

  defp format_money(_), do: "N/A"

  defp format_date(%Date{} = date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_date(_), do: "N/A"
end
