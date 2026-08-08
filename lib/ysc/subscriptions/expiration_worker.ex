defmodule Ysc.Subscriptions.ExpirationWorker do
  @moduledoc """
  Background worker for handling subscription expiration.

  This worker runs periodically to:
  - Find subscriptions with status "active" or "trialing" that have expired
  - Check if current_period_end or ends_at has passed
  - Sync with Stripe to get the latest status
  - Update local subscription status and invalidate membership cache
  - Ensure users without active memberships lose access immediately
  - Schedule the membership-ended re-engagement email for voluntary lapses
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  require Ysc.Logging

  alias Ecto.Multi
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Stripe.SubscriptionHelpers
  alias YscWeb.Emails.MembershipEnded

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {expired_count, failed_count} = check_and_expire_subscriptions()

    {:ok,
     "Checked subscriptions: #{expired_count} expired, #{failed_count} failed"}
  end

  @doc """
  Manually trigger expiration check for expired subscriptions.
  This can be called from a cron job or scheduled task.
  """
  def check_and_expire_subscriptions do
    now = DateTime.utc_now()

    # Find subscriptions that appear active but may have expired
    expired_subscriptions =
      Subscription
      |> where([s], s.stripe_status in ["active", "trialing"])
      |> where(
        [s],
        (not is_nil(s.current_period_end) and s.current_period_end < ^now) or
          (not is_nil(s.ends_at) and s.ends_at < ^now)
      )
      |> preload(:user)
      |> Repo.all()

    Ysc.Logging.info("Found potentially expired subscriptions",
      count: length(expired_subscriptions)
    )

    {expired_count, failed_count} =
      Enum.reduce(expired_subscriptions, {0, 0}, fn subscription,
                                                    {expired, failed} ->
        case process_expired_subscription(subscription) do
          :ok ->
            {expired + 1, failed}

          {:error, _reason} ->
            {expired, failed + 1}
        end
      end)

    {expired_count, failed_count}
  end

  defp process_expired_subscription(%Subscription{} = subscription) do
    require Ysc.Logging

    Ysc.Logging.info("Processing expired subscription",
      subscription_id: subscription.id,
      stripe_id: subscription.stripe_id,
      user_id: subscription.user_id,
      current_period_end: subscription.current_period_end,
      ends_at: subscription.ends_at,
      cancel_at_period_end: subscription.cancel_at_period_end,
      stripe_status: subscription.stripe_status
    )

    case fetch_stripe_subscription(subscription) do
      {:ok, stripe_subscription} ->
        attrs = sync_attrs_from_stripe(subscription, stripe_subscription)

        case apply_expiration_transition(subscription, attrs) do
          {:ok, updated_subscription} ->
            if Subscriptions.cancelled?(updated_subscription) or
                 not Subscriptions.active?(updated_subscription) do
              if updated_subscription.user_id do
                MembershipCache.invalidate_user(updated_subscription.user_id)

                Ysc.Logging.info(
                  "Expired subscription processed and cache invalidated",
                  subscription_id: updated_subscription.id,
                  user_id: updated_subscription.user_id,
                  stripe_status: updated_subscription.stripe_status
                )
              end

              :ok
            else
              Ysc.Logging.info(
                "Subscription was renewed in Stripe, no action needed",
                subscription_id: updated_subscription.id,
                stripe_status: updated_subscription.stripe_status
              )

              :ok
            end

          {:error, reason} ->
            Ysc.Logging.error(
              "Failed to apply subscription expiration transition",
              subscription_id: subscription.id,
              error: inspect(reason)
            )

            {:error, reason}
        end

      {:error, reason} ->
        Ysc.Logging.error("Failed to sync subscription from Stripe",
          subscription_id: subscription.id,
          stripe_id: subscription.stripe_id,
          error: inspect(reason)
        )

        # Even if Stripe sync fails, if the subscription is clearly expired locally,
        # we should still invalidate the cache to be defensive
        if subscription.user_id do
          if Subscriptions.cancelled?(subscription) or
               not Subscriptions.active?(subscription) do
            MembershipCache.invalidate_user(subscription.user_id)

            Ysc.Logging.warning(
              "Expired subscription detected locally, cache invalidated despite Stripe sync failure",
              subscription_id: subscription.id,
              user_id: subscription.user_id
            )
          end
        end

        {:error, reason}
    end
  end

  # Persist Stripe sync and (when voluntary and actually ending) the
  # membership-ended email in one transaction so a failed Oban insert does not
  # leave the subscription expired without a retryable email job.
  defp apply_expiration_transition(%Subscription{} = subscription, attrs) do
    user = Ysc.Accounts.get_user(subscription.user_id)
    changeset = Subscription.changeset(subscription, attrs)

    preview =
      struct(subscription, Map.take(attrs, Subscription.__schema__(:fields)))

    ending? =
      Subscriptions.cancelled?(preview) or not Subscriptions.active?(preview)

    multi =
      Multi.new()
      |> then(fn multi ->
        if ending? do
          MembershipEnded.maybe_schedule_email_multi(
            multi,
            :membership_ended_email,
            user,
            subscription
          )
        else
          multi
        end
      end)
      |> Multi.update(:subscription, changeset)

    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{subscription: updated}} ->
        {:ok, updated}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  defp subscription_retriever do
    Application.get_env(
      :ysc,
      :stripe_subscription_retriever,
      Stripe.Subscription
    )
  end

  defp fetch_stripe_subscription(%Subscription{} = subscription) do
    require Ysc.Logging

    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           subscription_retriever().retrieve(subscription.stripe_id)
         end) do
      {:ok, stripe_subscription} ->
        {:ok, stripe_subscription}

      {:error, %Stripe.Error{} = error} ->
        Ysc.Logging.error("Stripe API error when retrieving subscription",
          subscription_id: subscription.id,
          stripe_id: subscription.stripe_id,
          error: error.message
        )

        {:error, error}

      {:error, reason} ->
        Ysc.Logging.error(
          "Unexpected error when retrieving subscription from Stripe",
          subscription_id: subscription.id,
          stripe_id: subscription.stripe_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp sync_attrs_from_stripe(
         %Subscription{} = subscription,
         stripe_subscription
       ) do
    attrs = %{
      stripe_status: stripe_subscription.status,
      start_date:
        stripe_subscription.start_date &&
          DateTime.from_unix!(stripe_subscription.start_date),
      current_period_start:
        case SubscriptionHelpers.current_period_start(stripe_subscription) do
          nil -> nil
          timestamp -> DateTime.from_unix!(timestamp)
        end,
      current_period_end:
        case SubscriptionHelpers.current_period_end(stripe_subscription) do
          nil -> nil
          timestamp -> DateTime.from_unix!(timestamp)
        end,
      trial_ends_at:
        stripe_subscription.trial_end &&
          DateTime.from_unix!(stripe_subscription.trial_end),
      ends_at:
        stripe_subscription.ended_at &&
          DateTime.from_unix!(stripe_subscription.ended_at)
    }

    attrs =
      if stripe_subscription.cancel_at do
        Map.put(
          attrs,
          :ends_at,
          DateTime.from_unix!(stripe_subscription.cancel_at)
        )
      else
        attrs
      end

    # Preserve a local voluntary-lapse marker once set; Stripe clears
    # cancel_at_period_end after the subscription reaches a terminal state.
    cancel_at_period_end =
      subscription.cancel_at_period_end == true or
        stripe_subscription.cancel_at_period_end == true

    Map.put(attrs, :cancel_at_period_end, cancel_at_period_end)
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Job timeout after 120 seconds (may need to process multiple subscriptions and sync with Stripe)
    120_000
  end

  @doc false
  def ci_query_explain_query do
    now = DateTime.utc_now()

    from(s in Subscription,
      where: s.stripe_status in ["active", "trialing"],
      where:
        (not is_nil(s.current_period_end) and s.current_period_end < ^now) or
          (not is_nil(s.ends_at) and s.ends_at < ^now),
      preload: :user
    )
  end
end
