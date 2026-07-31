defmodule YscWeb.Workers.MembershipRenewalQuery do
  @moduledoc """
  Shared queries for membership renewal reminder workers.

  Both the 7-day renewal reminder and the 14-day payment-method checker use the
  same subscription window query against `current_period_end`.

  Eligible statuses:
  - `active` (normal auto-renewing memberships)
  - `trialing` only when the user is WP-migrated (`newsletter_subscribers.source =
    "wp_migration"`). Migrated Stripe subs stay `trialing` until renewal via
    `trial_end`; organic trials are excluded from these reminders.
  """

  import Ecto.Query

  alias Ysc.Newsletter.Subscriber
  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription

  @wp_migration_source "wp_migration"

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
  True when the user was loaded via WP migration (`newsletter_subscribers.source`).
  """
  def wp_migrated_user?(user_id) when is_binary(user_id) do
    from(ns in Subscriber,
      where: ns.user_id == ^user_id,
      where: ns.source == ^@wp_migration_source,
      select: 1,
      limit: 1
    )
    |> Repo.exists?()
  end

  def wp_migrated_user?(_), do: false

  @doc """
  Whether a subscription's Stripe status is eligible for renewal reminders.

  Active always qualifies. Trialing qualifies only for WP-migrated users.
  """
  def renewal_status_eligible?(%Subscription{} = subscription) do
    case subscription.stripe_status do
      "active" -> true
      "trialing" -> wp_migrated_user?(subscription.user_id)
      _ -> false
    end
  end

  @doc """
  Lists eligible subscriptions (not scheduled to end) whose `current_period_end`
  falls on the given calendar day (UTC).
  """
  def list_subscriptions_renewing_on(%Date{} = date) do
    {day_start, day_end} = utc_day_bounds(date)

    renewing_subscriptions_query()
    |> where([s], s.current_period_end >= ^day_start)
    |> where([s], s.current_period_end <= ^day_end)
    |> preload([:user])
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
  Lists eligible subscriptions (not scheduled to end) whose renewal falls on
  any calendar day from today through `days` days from now (inclusive), UTC.

  Same eligibility as `list_subscriptions_renewing_on/1`: `active`, or
  `trialing` only for WP-migrated users.
  """
  def list_subscriptions_renewing_within_days(days)
      when is_integer(days) and days >= 0 do
    today = Date.utc_today()
    {day_start, _} = utc_day_bounds(today)
    {_, day_end} = utc_day_bounds(Date.add(today, days))

    renewing_subscriptions_query()
    |> where([s], s.current_period_end >= ^day_start)
    |> where([s], s.current_period_end <= ^day_end)
    |> preload([:user])
    |> Repo.all()
  end

  defp renewing_subscriptions_query do
    from(s in Subscription,
      as: :s,
      where: is_nil(s.ends_at),
      where:
        s.stripe_status == "active" or
          (s.stripe_status == "trialing" and
             exists(
               from(ns in Subscriber,
                 where: ns.user_id == parent_as(:s).user_id,
                 where: ns.source == ^@wp_migration_source
               )
             ))
    )
  end
end
