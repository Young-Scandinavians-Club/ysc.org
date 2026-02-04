defmodule Ysc.Subscriptions.ExpirationWorker do
  @moduledoc """
  Background worker for handling subscription expiration.

  This worker runs periodically to:
  - Find subscriptions with status "active" or "trialing" that have expired
  - Check if current_period_end or ends_at has passed
  - Sync with Stripe to get the latest status
  - Update local subscription status and invalidate membership cache
  - Ensure users without active memberships lose access immediately
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  require Logger

  alias Ysc.Accounts.MembershipCache
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription

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

    Logger.info("Found potentially expired subscriptions",
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
    require Logger

    Logger.info("Processing expired subscription",
      subscription_id: subscription.id,
      stripe_id: subscription.stripe_id,
      user_id: subscription.user_id,
      current_period_end: subscription.current_period_end,
      ends_at: subscription.ends_at,
      stripe_status: subscription.stripe_status
    )

    # Sync with Stripe to get the latest status
    case sync_subscription_from_stripe(subscription) do
      {:ok, updated_subscription} ->
        # Check if subscription is still expired after sync
        if Subscriptions.cancelled?(updated_subscription) or
             not Subscriptions.active?(updated_subscription) do
          # Invalidate membership cache to ensure immediate access revocation
          if updated_subscription.user_id do
            MembershipCache.invalidate_user(updated_subscription.user_id)

            Logger.info("Expired subscription processed and cache invalidated",
              subscription_id: updated_subscription.id,
              user_id: updated_subscription.user_id,
              stripe_status: updated_subscription.stripe_status
            )
          end

          :ok
        else
          # Subscription was renewed or reactivated in Stripe
          Logger.info("Subscription was renewed in Stripe, no action needed",
            subscription_id: updated_subscription.id,
            stripe_status: updated_subscription.stripe_status
          )

          :ok
        end

      {:error, reason} ->
        Logger.error("Failed to sync subscription from Stripe",
          subscription_id: subscription.id,
          stripe_id: subscription.stripe_id,
          error: inspect(reason)
        )

        # Even if Stripe sync fails, if the subscription is clearly expired locally,
        # we should still invalidate the cache to be defensive
        if subscription.user_id do
          # Double-check expiration locally
          if Subscriptions.cancelled?(subscription) or
               not Subscriptions.active?(subscription) do
            MembershipCache.invalidate_user(subscription.user_id)

            Logger.warning(
              "Expired subscription detected locally, cache invalidated despite Stripe sync failure",
              subscription_id: subscription.id,
              user_id: subscription.user_id
            )
          end
        end

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

  defp sync_subscription_from_stripe(%Subscription{} = subscription) do
    require Logger

    case subscription_retriever().retrieve(subscription.stripe_id) do
      {:ok, stripe_subscription} ->
        # Update local subscription with latest data from Stripe
        attrs = %{
          stripe_status: stripe_subscription.status,
          start_date:
            stripe_subscription.start_date &&
              DateTime.from_unix!(stripe_subscription.start_date),
          current_period_start:
            stripe_subscription.current_period_start &&
              DateTime.from_unix!(stripe_subscription.current_period_start),
          current_period_end:
            stripe_subscription.current_period_end &&
              DateTime.from_unix!(stripe_subscription.current_period_end),
          trial_ends_at:
            stripe_subscription.trial_end &&
              DateTime.from_unix!(stripe_subscription.trial_end),
          ends_at:
            stripe_subscription.ended_at &&
              DateTime.from_unix!(stripe_subscription.ended_at)
        }

        # Add cancellation info if present
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

        case Subscriptions.update_subscription(subscription, attrs) do
          {:ok, updated_subscription} ->
            {:ok, updated_subscription}

          {:error, changeset} ->
            Logger.error("Failed to update subscription after Stripe sync",
              subscription_id: subscription.id,
              errors: inspect(changeset.errors)
            )

            {:error, changeset}
        end

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Stripe API error when retrieving subscription",
          subscription_id: subscription.id,
          stripe_id: subscription.stripe_id,
          error: error.message
        )

        {:error, error}

      {:error, reason} ->
        Logger.error(
          "Unexpected error when retrieving subscription from Stripe",
          subscription_id: subscription.id,
          stripe_id: subscription.stripe_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Job timeout after 120 seconds (may need to process multiple subscriptions and sync with Stripe)
    120_000
  end
end
