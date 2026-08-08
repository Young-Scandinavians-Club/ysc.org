defmodule YscWeb.Emails.MembershipEnded do
  @moduledoc """
  Re-engagement email sent when a membership ends because automatic renewal
  was turned off and the membership period has lapsed.

  Not sent for payment-failure cancellations or immediate admin cancellations
  (those do not have a scheduled `ends_at` from turning off auto-renewal).
  """
  use MjmlEEx,
    mjml_template: "templates/membership_ended.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  require Ysc.Logging

  import YscWeb.Emails.Helpers,
    only: [
      member_greeting_name: 1,
      membership_url: 0,
      upcoming_events_url: 0,
      format_date: 1
    ]

  alias YscWeb.Emails.Notifier

  def get_template_name() do
    "membership_ended"
  end

  def get_subject(_email_data \\ %{}) do
    "Your YSC Membership Has Ended"
  end

  @doc """
  Builds template assigns for a user and ended subscription.
  """
  def prepare_email_data(user, subscription) do
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    if is_nil(subscription) do
      raise ArgumentError, "Subscription cannot be nil"
    end

    end_date = end_date_for(subscription)

    %{
      first_name: member_greeting_name(user),
      end_date: format_date(end_date),
      membership_url: membership_url(),
      upcoming_events_url: upcoming_events_url()
    }
  end

  @doc """
  Schedules the membership-ended email when the subscription ended because
  auto-renewal was turned off (`ends_at` was set).

  Idempotent per user and end date. Returns `:ok`, `:skipped`, or `{:error, reason}`.
  """
  def maybe_schedule(user, %{ends_at: %DateTime{}} = subscription)
      when not is_nil(user) do
    schedule(user, subscription)
  end

  def maybe_schedule(_user, _subscription), do: :skipped

  defp schedule(user, subscription) do
    email_data = prepare_email_data(user, subscription)
    subject = get_subject(email_data)
    template_name = get_template_name()
    end_date = end_date_for(subscription) |> DateTime.to_date()
    idempotency_key = "membership_ended_#{user.id}_#{end_date}"

    Ysc.Logging.info("Sending membership ended re-engagement email",
      user_id: user.id,
      email: user.email,
      subscription_id: Map.get(subscription, :id),
      end_date: end_date
    )

    case Notifier.schedule_email(
           user.email,
           idempotency_key,
           subject,
           template_name,
           email_data,
           "",
           user.id
         ) do
      %Oban.Job{} ->
        Ysc.Logging.info(
          "Membership ended email scheduled successfully",
          user_id: user.id,
          subscription_id: Map.get(subscription, :id)
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.error(
          "Failed to schedule membership ended email",
          user_id: user.id,
          subscription_id: Map.get(subscription, :id),
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp end_date_for(%{ends_at: %DateTime{} = ends_at}), do: ends_at

  defp end_date_for(%{current_period_end: %DateTime{} = period_end}),
    do: period_end

  defp end_date_for(_), do: DateTime.utc_now()
end
