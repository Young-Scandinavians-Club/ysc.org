defmodule YscWeb.Emails.MembershipEnded do
  @moduledoc """
  Re-engagement email sent when a membership ends because automatic renewal
  was turned off and the membership period has lapsed.

  Gated on `cancel_at_period_end` (set when auto-renewal is disabled at period
  end). Not sent for payment-failure cancellations or immediate admin
  cancellations.
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
  Returns true when the subscription ended because auto-renewal was turned off.
  """
  def voluntary_lapse?(%{cancel_at_period_end: true}), do: true
  def voluntary_lapse?(_), do: false

  @doc """
  Schedules the membership-ended email when the subscription ended because
  auto-renewal was turned off (`cancel_at_period_end`).

  Idempotent per user and end date. Returns `:ok`, `:skipped`, or `{:error, reason}`.
  """
  def maybe_schedule(user, subscription)
      when not is_nil(user) and is_map(subscription) do
    if voluntary_lapse?(subscription) do
      schedule(user, subscription)
    else
      :skipped
    end
  end

  def maybe_schedule(_user, _subscription), do: :skipped

  @doc """
  Adds the membership-ended email job to an `Ecto.Multi` when applicable.

  Returns the multi unchanged when the subscription is not a voluntary lapse
  or the user is missing.
  """
  def maybe_schedule_email_multi(multi, operation_name, user, subscription)
      when not is_nil(user) and is_map(subscription) do
    if voluntary_lapse?(subscription) do
      Notifier.schedule_email_multi(
        multi,
        operation_name,
        schedule_attrs(user, subscription)
      )
    else
      multi
    end
  end

  def maybe_schedule_email_multi(multi, _operation_name, _user, _subscription),
    do: multi

  defp schedule(user, subscription) do
    attrs = schedule_attrs(user, subscription)

    Ysc.Logging.info("Sending membership ended re-engagement email",
      user_id: user.id,
      email: user.email,
      subscription_id: Map.get(subscription, :id),
      end_date: attrs.idempotency_key
    )

    case Notifier.schedule_email(
           attrs.recipient,
           attrs.idempotency_key,
           attrs.subject,
           attrs.template,
           attrs.variables,
           attrs.text_body,
           attrs.user_id
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

  defp schedule_attrs(user, subscription) do
    email_data = prepare_email_data(user, subscription)
    end_date = end_date_for(subscription) |> DateTime.to_date()

    %{
      recipient: user.email,
      idempotency_key: "membership_ended_#{user.id}_#{end_date}",
      subject: get_subject(email_data),
      template: get_template_name(),
      variables: email_data,
      text_body: "",
      user_id: user.id
    }
  end

  defp end_date_for(%{ends_at: %DateTime{} = ends_at}), do: ends_at

  defp end_date_for(%{current_period_end: %DateTime{} = period_end}),
    do: period_end

  defp end_date_for(_), do: DateTime.utc_now()
end
