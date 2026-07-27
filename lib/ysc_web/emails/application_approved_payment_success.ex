defmodule YscWeb.Emails.ApplicationApprovedPaymentSuccess do
  @moduledoc """
  Email template for membership payment confirmation after application approval.

  Sent when membership activates with a successful charge — either immediately
  on admin approval (saved payment method) or later when the member completes
  payment from account setup / settings after approve-without-PM.
  """
  use MjmlEEx,
    mjml_template: "templates/application_approved_payment_success.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: []

  def get_template_name() do
    "application_approved_payment_success"
  end

  def get_subject() do
    "Velkommen! Your YSC Membership is Active! 🎉"
  end

  def dashboard_url(), do: YscWeb.Emails.Helpers.home_url()

  def upcoming_events_url(), do: YscWeb.Emails.Helpers.upcoming_events_url()

  @doc """
  Schedules the payment-success email. Idempotent per user via
  `approved_payment_success_<user_id>`.
  """
  def schedule(%Ysc.Accounts.User{} = user) do
    YscWeb.Emails.Notifier.schedule_email(
      user.email,
      "approved_payment_success_#{user.id}",
      get_subject(),
      get_template_name(),
      %{first_name: user.first_name},
      """
      ==============================

      Hi #{user.email},

      Your application has been approved and your membership payment has been processed! 🎉

      Your membership is now active. Welcome to the Young Scandinavians Club!

      Visit: #{YscWeb.Endpoint.url()}

      If you have any questions, please don't hesitate to contact us at memberships@ysc.org.

      Velkommen!

      Young Scandinavians Club

      ==============================
      """,
      user.id
    )
  end

  @doc """
  Schedules only when activation newly succeeded (`:activated`).
  Skips `:already_active` and other statuses to avoid duplicate sends.
  """
  def maybe_schedule(%Ysc.Accounts.User{} = user, :activated),
    do: schedule(user)

  def maybe_schedule(_user, _status), do: :ok
end
