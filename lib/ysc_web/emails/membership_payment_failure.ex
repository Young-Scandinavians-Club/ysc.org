defmodule YscWeb.Emails.MembershipPaymentFailure do
  @moduledoc """
  Email template for membership payment failure notification.

  Notifies users when a membership payment fails, including renewals.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_payment_failure.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "membership_payment_failure"
  end

  def get_subject() do
    "Action Needed: YSC Membership Payment Issue"
  end

  def pay_membership_url() do
    YscWeb.Endpoint.url() <> "/users/membership"
  end

  def retry_payment_url(invoice_id) when is_binary(invoice_id) do
    YscWeb.Endpoint.url() <>
      "/users/membership?" <>
      URI.encode_query(%{retry_invoice: invoice_id})
  end

  def retry_payment_url(_), do: nil

  def prepare_email_data(
        user,
        membership_type,
        is_renewal \\ false,
        invoice_id \\ nil
      ) do
    # Validate input
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    # Ensure user has required fields
    first_name = user.first_name || "Valued Member"
    membership_type_name = get_membership_type_name(membership_type)

    retry_url =
      if invoice_id do
        retry_payment_url(invoice_id)
      else
        nil
      end

    %{
      first_name: first_name,
      membership_type: membership_type_name,
      is_renewal: is_renewal,
      invoice_id: invoice_id,
      pay_membership_url: pay_membership_url(),
      retry_payment_url: retry_url
    }
  end

  defp get_membership_type_name(:single), do: "Single"
  defp get_membership_type_name(:family), do: "Family"
  defp get_membership_type_name("single"), do: "Single"
  defp get_membership_type_name("family"), do: "Family"
  defp get_membership_type_name(_), do: "Membership"
end
