defmodule YscWeb.Workers.MembershipRenewalQuery do
  @moduledoc """
  Shared queries for membership renewal reminder workers.

  Both the 7-day renewal reminder and the 14-day payment-method checker use the
  same subscription window query against `current_period_end`. Matches
  `active` and `trialing` Stripe statuses (WP-migrated subs stay trialing until
  renewal).
  """

  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription

  @doc """
  Returns the calendar date N days from now (UTC).
  """
  def renewal_date_from_now(days) when is_integer(days) and days >= 0 do
    DateTime.utc_now()
    |> DateTime.add(days, :day)
    |> DateTime.to_date()
  end

  @doc """
  Returns inclusive UTC datetime bounds for a calendar day.
  """
  def utc_day_bounds(%Date{} = date) do
    {
      DateTime.new!(date, ~T[00:00:00], "Etc/UTC"),
      DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    }
  end

  @doc """
  Lists active or trialing subscriptions (not scheduled to end) whose
  `current_period_end` falls on the given calendar day (UTC).

  Includes `trialing` so WP-migrated Stripe subscriptions (created with
  `trial_end` set to the renewal date) receive renewal reminders.
  """
  def list_subscriptions_renewing_on(%Date{} = date) do
    {day_start, day_end} = utc_day_bounds(date)

    from(s in Subscription,
      where: s.current_period_end >= ^day_start,
      where: s.current_period_end <= ^day_end,
      where: s.stripe_status in ["active", "trialing"],
      where: is_nil(s.ends_at),
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Lists subscriptions renewing N days from now.
  """
  def list_subscriptions_renewing_in_days(days)
      when is_integer(days) and days >= 0 do
    days
    |> renewal_date_from_now()
    |> list_subscriptions_renewing_on()
  end

  @doc """
  Lists subscriptions whose renewal falls on any calendar day from today
  through `days` days from now (inclusive), UTC.
  """
  def list_subscriptions_renewing_within_days(days)
      when is_integer(days) and days >= 0 do
    today = Date.utc_today()
    {day_start, _} = utc_day_bounds(today)
    {_, day_end} = utc_day_bounds(Date.add(today, days))

    from(s in Subscription,
      where: s.current_period_end >= ^day_start,
      where: s.current_period_end <= ^day_end,
      where: s.stripe_status in ["active", "trialing"],
      where: is_nil(s.ends_at),
      preload: [:user]
    )
    |> Repo.all()
  end
end
