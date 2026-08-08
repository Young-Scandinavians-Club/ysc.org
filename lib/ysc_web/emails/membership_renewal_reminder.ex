defmodule YscWeb.Emails.MembershipRenewalReminder do
  @moduledoc """
  Courtesy email sent to members within 7 days of their membership auto-renewing.

  Subject and headline reflect the actual days remaining (today, tomorrow, or
  N days) so copy stays accurate when the reminder is sent inside the window
  (e.g. after an admin billing-anchor change), not only on the 7-day cron.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_renewal_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [member_greeting_name: 1, membership_url: 0, format_date: 1]

  def get_template_name() do
    "membership_renewal_reminder"
  end

  @doc """
  Builds the email subject from prepared email data.

  Falls back to the 7-day wording when `days_until_renewal` is missing (e.g.
  callers that only need a static example subject).
  """
  def get_subject(email_data \\ %{})

  def get_subject(%{days_until_renewal: days}) when is_integer(days) do
    "Your YSC Membership Renews #{timing_phrase(days, :title)}"
  end

  def get_subject(_email_data) do
    get_subject(%{days_until_renewal: 7})
  end

  def prepare_email_data(user, subscription) do
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    if is_nil(subscription) do
      raise ArgumentError, "Subscription cannot be nil"
    end

    first_name = member_greeting_name(user)
    renewal_date = format_date(subscription.current_period_end)
    days = days_until_renewal(subscription.current_period_end)

    %{
      first_name: first_name,
      renewal_date: renewal_date,
      membership_url: membership_url(),
      days_until_renewal: days,
      headline: "Your Membership Renews #{timing_phrase(days, :title)}"
    }
  end

  @doc """
  Calendar days from today (UTC) until the renewal date.
  """
  def days_until_renewal(%DateTime{} = period_end) do
    Date.diff(DateTime.to_date(period_end), Date.utc_today())
  end

  def days_until_renewal(%Date{} = period_end) do
    Date.diff(period_end, Date.utc_today())
  end

  # :title → "Today" / "Tomorrow" / "in 3 Days" (for subject + headline)
  defp timing_phrase(0, :title), do: "Today"
  defp timing_phrase(1, :title), do: "Tomorrow"

  defp timing_phrase(days, :title) when is_integer(days) and days > 1 do
    "in #{days} Days"
  end

  defp timing_phrase(_days, :title), do: "Soon"
end
