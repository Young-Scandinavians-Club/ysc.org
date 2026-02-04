defmodule YscWeb.Emails.MembershipPaymentConfirmation do
  @moduledoc """
  Email template for first-time membership payment confirmation.

  Notifies users when their first membership payment succeeds and their membership is active.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_payment_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "membership_payment_confirmation"
  end

  def get_subject() do
    "Welcome to YSC – Your Membership is Active! 🎉"
  end

  def prepare_email_data(
        user,
        membership_type,
        amount,
        payment_date,
        opts \\ []
      ) do
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    paid_elsewhere = Keyword.get(opts, :paid_elsewhere, false)
    first_name = user.first_name || "Valued Member"
    membership_type_name = get_membership_type_name(membership_type)
    amount_str = format_money(amount)
    payment_date_str = format_date(payment_date)

    %{
      first_name: first_name,
      membership_type: membership_type_name,
      amount: amount_str,
      payment_date: payment_date_str,
      paid_elsewhere: paid_elsewhere
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

  defp format_date(%DateTime{} = datetime) do
    datetime |> DateTime.to_date() |> Calendar.strftime("%B %d, %Y")
  end

  defp format_date(_), do: "N/A"
end
