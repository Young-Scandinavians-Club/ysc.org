defmodule YscWeb.Emails.MembershipRenewalSuccess do
  @moduledoc """
  Email template for membership renewal success notification.

  Notifies users when their membership renewal payment succeeds.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_renewal_success.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "membership_renewal_success"
  end

  def get_subject() do
    "Your YSC Membership Has Been Renewed! 🎉"
  end

  def prepare_email_data(user, membership_type, amount, renewal_date) do
    # Validate input
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    # Ensure user has required fields
    first_name = user.first_name || "Valued Member"
    membership_type_name = get_membership_type_name(membership_type)

    # Format amount
    amount_str = format_money(amount)

    # Format renewal date
    renewal_date_str = format_date(renewal_date)

    %{
      first_name: first_name,
      membership_type: membership_type_name,
      amount: amount_str,
      renewal_date: renewal_date_str
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
