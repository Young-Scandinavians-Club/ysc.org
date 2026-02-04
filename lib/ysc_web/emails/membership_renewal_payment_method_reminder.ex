defmodule YscWeb.Emails.MembershipRenewalPaymentMethodReminder do
  @moduledoc """
  Email template for membership renewal payment method reminder.

  Sent to users 14 days before their membership renewal date if they don't have
  a payment method on file. This is common for users who paid with cash or other
  offline methods initially.
  """
  use MjmlEEx,
    mjml_template:
      "templates/membership_renewal_payment_method_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "membership_renewal_payment_method_reminder"
  end

  def get_subject() do
    "Action Required: Add Payment Method for Membership Renewal"
  end

  def payment_methods_url() do
    YscWeb.Endpoint.url() <> "/users/payment-methods"
  end

  def membership_url() do
    YscWeb.Endpoint.url() <> "/users/membership"
  end

  def prepare_email_data(user, subscription) do
    # Validate input
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    if is_nil(subscription) do
      raise ArgumentError, "Subscription cannot be nil"
    end

    # Ensure user has required fields
    # Handle both nil and empty string cases
    first_name =
      case user.first_name do
        nil -> "Valued Member"
        "" -> "Valued Member"
        name -> name
      end

    # Format renewal date
    renewal_date =
      subscription.current_period_end
      |> DateTime.to_date()
      |> Calendar.strftime("%B %d, %Y")

    %{
      first_name: first_name,
      renewal_date: renewal_date,
      payment_methods_url: payment_methods_url(),
      membership_url: membership_url()
    }
  end
end
