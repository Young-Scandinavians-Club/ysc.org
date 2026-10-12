defmodule YscWeb.Emails.MembershipPaymentFailure do
  @moduledoc """
  Email template for membership payment failure notification.

  Notifies users when a membership payment fails, including renewals.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_payment_failure.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      membership_member_assigns: 2,
      membership_url: 0,
      require_user!: 1
    ]

  def get_template_name() do
    "membership_payment_failure"
  end

  def get_subject() do
    "Action Needed: YSC Membership Payment Issue"
  end

  def pay_membership_url(), do: membership_url()

  def retry_payment_url(invoice_id) when is_binary(invoice_id) do
    absolute_url(
      "/users/membership?" <>
        URI.encode_query(%{retry_invoice: invoice_id})
    )
  end

  def retry_payment_url(_), do: nil

  def prepare_email_data(
        user,
        membership_type,
        is_renewal \\ false,
        invoice_id \\ nil
      ) do
    user = require_user!(user)

    retry_url =
      if invoice_id do
        retry_payment_url(invoice_id)
      else
        nil
      end

    user
    |> membership_member_assigns(membership_type)
    |> Map.merge(%{
      email: user.email,
      is_renewal: is_renewal,
      invoice_id: invoice_id,
      pay_membership_url: pay_membership_url(),
      retry_payment_url: retry_url
    })
  end
end
