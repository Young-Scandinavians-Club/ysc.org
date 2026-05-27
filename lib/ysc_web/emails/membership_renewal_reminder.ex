defmodule YscWeb.Emails.MembershipRenewalReminder do
  @moduledoc """
  Courtesy email sent to members 7 days before their membership auto-renews.

  This gives members a chance to cancel before the renewal charge is made if
  they no longer wish to continue their membership.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_renewal_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [member_greeting_name: 1, membership_url: 0]

  def get_template_name() do
    "membership_renewal_reminder"
  end

  def get_subject() do
    "Your YSC Membership Renews in 7 Days"
  end

  def prepare_email_data(user, subscription) do
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    if is_nil(subscription) do
      raise ArgumentError, "Subscription cannot be nil"
    end

    first_name = member_greeting_name(user)

    renewal_date =
      subscription.current_period_end
      |> DateTime.to_date()
      |> Calendar.strftime("%B %d, %Y")

    %{
      first_name: first_name,
      renewal_date: renewal_date,
      membership_url: membership_url()
    }
  end
end
