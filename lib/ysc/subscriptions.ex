defmodule Ysc.Subscriptions do
  @moduledoc """
  The Subscriptions context for managing subscriptions and subscription items.
  """

  require Ysc.Logging

  import Ecto.Query, warn: false
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Accounts.UserProfileCache
  alias Ysc.Repo
  alias Ysc.Subscriptions.BoardVolunteerBilling
  alias Ysc.Subscriptions.{Subscription, SubscriptionItem}
  alias Ysc.Stripe.SubscriptionHelpers

  @doc """
  Returns the list of subscriptions for a given user.

  ## Examples

      iex> list_subscriptions(user)
      [%Subscription{}, ...]

  """
  def list_subscriptions(user) do
    Subscription
    |> where([s], s.user_id == ^user.id)
    |> preload(:subscription_items)
    |> Repo.all()
  end

  @doc """
  Gets a single subscription by Stripe ID.

  ## Examples

      iex> get_subscription_by_stripe_id("sub_123")
      %Subscription{}

      iex> get_subscription_by_stripe_id("invalid")
      nil

  """
  def get_subscription_by_stripe_id(stripe_id) do
    Subscription
    |> where([s], s.stripe_id == ^stripe_id)
    |> preload(:subscription_items)
    |> Repo.one()
  end

  @doc """
  Gets a single subscription by ID.

  ## Examples

      iex> get_subscription(123)
      %Subscription{}

      iex> get_subscription(456)
      nil

  """
  def get_subscription(id) do
    Subscription
    |> where([s], s.id == ^id)
    |> preload(:subscription_items)
    |> Repo.one()
  end

  @doc """
  Creates a subscription.

  ## Examples

      iex> create_subscription(%{field: value})
      {:ok, %Subscription{}}

      iex> create_subscription(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_subscription(attrs \\ %{}) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a subscription.

  ## Examples

      iex> update_subscription(subscription, %{field: new_value})
      {:ok, %Subscription{}}

      iex> update_subscription(subscription, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_subscription(%Subscription{} = subscription, attrs) do
    result =
      subscription
      |> Subscription.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_subscription} ->
        if updated_subscription.user_id do
          invalidate_membership_caches(updated_subscription.user_id)
          broadcast_membership_updated(updated_subscription.user_id)
        end

        result

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Deletes a subscription.

  ## Examples

      iex> delete_subscription(subscription)
      {:ok, %Subscription{}}

      iex> delete_subscription(subscription)
      {:error, %Ecto.Changeset{}}

  """
  def delete_subscription(%Subscription{} = subscription) do
    user_id = subscription.user_id
    result = Repo.delete(subscription)

    case result do
      {:ok, _} ->
        if user_id do
          invalidate_membership_caches(user_id)
          broadcast_membership_updated(user_id)
        end

        result

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking subscription changes.

  ## Examples

      iex> change_subscription(subscription)
      %Ecto.Changeset{data: %Subscription{}}

  """
  def change_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end

  @doc """
  Creates a subscription item.

  ## Examples

      iex> create_subscription_item(%{field: value})
      {:ok, %SubscriptionItem{}}

      iex> create_subscription_item(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_subscription_item(attrs \\ %{}) do
    %SubscriptionItem{}
    |> SubscriptionItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a subscription item.

  ## Examples

      iex> update_subscription_item(subscription_item, %{field: new_value})
      {:ok, %SubscriptionItem{}}

      iex> update_subscription_item(subscription_item, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_subscription_item(%SubscriptionItem{} = subscription_item, attrs) do
    subscription_item
    |> SubscriptionItem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a subscription item.

  ## Examples

      iex> delete_subscription_item(subscription_item)
      {:ok, %SubscriptionItem{}}

      iex> delete_subscription_item(subscription_item)
      {:error, %Ecto.Changeset{}}

  """
  def delete_subscription_item(%SubscriptionItem{} = subscription_item) do
    Repo.delete(subscription_item)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking subscription item changes.

  ## Examples

      iex> change_subscription_item(subscription_item)
      %Ecto.Changeset{data: %SubscriptionItem{}}

  """
  def change_subscription_item(
        %SubscriptionItem{} = subscription_item,
        attrs \\ %{}
      ) do
    SubscriptionItem.changeset(subscription_item, attrs)
  end

  # Subscription status and validation functions

  @doc """
  Checks if a subscription is active.

  A subscription is considered active if:
  - The stripe_status is "active" or "trialing"
  - The current_period_end is in the future (subscription hasn't expired)
  - If ends_at is set, it must be in the future (not cancelled/ended)

  ## Examples

      iex> active?(subscription)
      true

      iex> active?(cancelled_subscription)
      false

  """
  def active?(%Subscription{} = subscription) do
    now = DateTime.utc_now()

    # Check status first
    status_valid? =
      case subscription.stripe_status do
        "active" -> true
        "trialing" -> true
        _ -> false
      end

    if status_valid? do
      # Check if current_period_end has passed
      period_valid? =
        case subscription.current_period_end do
          %DateTime{} = period_end ->
            DateTime.compare(period_end, now) == :gt

          _ ->
            # If current_period_end is nil, we can't verify it's active
            # This is a defensive check - if we don't have the date, be conservative
            false
        end

      # Check if ends_at has passed (subscription was cancelled/ended)
      ends_at_valid? =
        case subscription.ends_at do
          %DateTime{} = ends_at ->
            DateTime.compare(ends_at, now) == :gt

          _ ->
            # If ends_at is nil, it's not cancelled/ended
            true
        end

      # Subscription is active only if period is valid AND ends_at is valid
      period_valid? and ends_at_valid?
    else
      false
    end
  end

  @doc """
  Checks if a subscription is valid (active or trialing).

  A subscription is valid if it is active, which includes:
  - Status is "active" or "trialing"
  - current_period_end is in the future
  - ends_at (if set) is in the future

  ## Examples

      iex> valid?(subscription)
      true

      iex> valid?(cancelled_subscription)
      false

  """
  def valid?(%Subscription{} = subscription) do
    active?(subscription)
  end

  @doc """
  Checks if a subscription is cancelled.

  A subscription is considered cancelled if:
  - The stripe_status is "cancelled", OR
  - ends_at is set and has passed (in the past), OR
  - current_period_end has passed (subscription period expired)

  ## Examples

      iex> cancelled?(subscription)
      false

      iex> cancelled?(cancelled_subscription)
      true

      iex> cancelled?(nil)
      false

  """
  def cancelled?(%Subscription{} = subscription) do
    now = DateTime.utc_now()

    case subscription do
      %Subscription{stripe_status: "cancelled"} ->
        true

      %Subscription{ends_at: %DateTime{} = ends_at} ->
        # Subscription is cancelled if ends_at is in the past
        DateTime.compare(ends_at, now) != :gt

      %Subscription{current_period_end: %DateTime{} = period_end} ->
        # If current_period_end has passed, subscription is effectively cancelled/expired
        DateTime.compare(period_end, now) != :gt

      _ ->
        false
    end
  end

  def cancelled?(nil), do: false

  @doc """
  Checks if a subscription is scheduled for cancellation at the end of the current period.

  ## Examples

      iex> scheduled_for_cancellation?(subscription)
      true

  """
  def scheduled_for_cancellation?(%Subscription{} = subscription) do
    case subscription do
      %Subscription{stripe_status: status, ends_at: %DateTime{} = ends_at}
      when status in ["active", "trialing"] ->
        DateTime.compare(ends_at, DateTime.utc_now()) == :gt

      _ ->
        false
    end
  end

  def scheduled_for_cancellation?(%{type: :lifetime}), do: false

  def scheduled_for_cancellation?(nil), do: false

  @doc """
  Returns info about a scheduled downgrade if the subscription has one.

  When a user schedules a downgrade (e.g. Family → Single at renewal), the
  subscription has a Stripe schedule with two phases. This fetches that info.

  ## Returns

  - `nil` - No scheduled downgrade
  - `%{target_plan: :single, effective_date: DateTime}` - Downgrade to Single on date
  - `%{target_plan: :family, effective_date: DateTime}` - Downgrade to Family on date
    (unusual but possible if plans were reordered)

  ## Examples

      iex> get_scheduled_downgrade_info(subscription)
      %{target_plan: :single, effective_date: ~U[2025-02-15 00:00:00Z]}

      iex> get_scheduled_downgrade_info(subscription)
      nil

  """
  def get_scheduled_downgrade_info(nil), do: nil

  def get_scheduled_downgrade_info(%{type: :lifetime}), do: nil

  def get_scheduled_downgrade_info(%Subscription{} = subscription) do
    case Application.get_env(:ysc, :get_scheduled_downgrade_info_callback) do
      callback when is_function(callback, 1) ->
        callback.(subscription)

      _ ->
        do_get_scheduled_downgrade_info(subscription)
    end
  end

  defp stripe_subscription_retriever do
    Application.get_env(
      :ysc,
      :stripe_subscription_retriever,
      Stripe.Subscription
    )
  end

  defp stripe_subscription_module do
    Application.get_env(:ysc, :stripe_subscription_module, Stripe.Subscription)
  end

  defp do_get_scheduled_downgrade_info(%Subscription{} = subscription) do
    with {:ok, stripe_sub} <-
           Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             stripe_subscription_retriever().retrieve(subscription.stripe_id)
           end),
         schedule_id when is_binary(schedule_id) <- stripe_sub.schedule,
         {:ok, schedule} <-
           Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             Stripe.SubscriptionSchedule.retrieve(schedule_id)
           end),
         phases when is_list(phases) and length(phases) >= 2 <- schedule.phases,
         next_phase <- Enum.at(phases, 1),
         [item | _] <- next_phase[:items] || next_phase["items"],
         price_id when is_binary(price_id) <- extract_price_id(item),
         target_plan when not is_nil(target_plan) <- price_id_to_plan(price_id),
         start_date when not is_nil(start_date) <-
           next_phase[:start_date] || next_phase["start_date"] do
      effective_date = DateTime.from_unix!(start_date)

      %{target_plan: target_plan, effective_date: effective_date}
    else
      _ -> nil
    end
  end

  defp extract_price_id(%{price: price}) when is_binary(price), do: price
  defp extract_price_id(%{price: %{id: id}}) when is_binary(id), do: id
  defp extract_price_id(%{"price" => price}) when is_binary(price), do: price
  defp extract_price_id(%{"price" => %{"id" => id}}) when is_binary(id), do: id
  defp extract_price_id(_), do: nil

  defp price_id_to_plan(price_id) do
    plans = Application.get_env(:ysc, :membership_plans, [])

    case Enum.find(plans, &(&1.stripe_price_id == price_id)) do
      %{id: plan_id} when plan_id in [:single, :family] -> plan_id
      _ -> nil
    end
  end

  @doc """
  Cancels a scheduled downgrade by releasing the subscription schedule in Stripe.
  The user keeps their current plan (e.g. Family) with no change at renewal.

  Returns `{:ok, subscription}` on success, `{:error, reason}` on failure.

  ## Examples

      iex> cancel_scheduled_downgrade(subscription)
      {:ok, %Subscription{}}

      iex> cancel_scheduled_downgrade(subscription_without_schedule)
      {:error, :no_scheduled_downgrade}
  """
  def cancel_scheduled_downgrade(nil), do: {:error, "No subscription to update"}

  def cancel_scheduled_downgrade(%Subscription{} = subscription) do
    case Application.get_env(:ysc, :cancel_scheduled_downgrade_callback) do
      callback when is_function(callback, 1) ->
        callback.(subscription)

      _ ->
        do_cancel_scheduled_downgrade(subscription)
    end
  end

  defp do_cancel_scheduled_downgrade(%Subscription{} = subscription) do
    with {:ok, stripe_sub} <-
           Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             stripe_subscription_retriever().retrieve(subscription.stripe_id)
           end),
         schedule_id when is_binary(schedule_id) <- stripe_sub.schedule,
         {:ok, _} <-
           Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             Stripe.SubscriptionSchedule.release(schedule_id)
           end) do
      if subscription.user_id do
        invalidate_membership_caches(subscription.user_id)
      end

      {:ok, subscription}
    else
      nil -> {:error, :no_scheduled_downgrade}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Marks a subscription as cancelled.

  ## Examples

      iex> mark_as_cancelled(subscription)
      {:ok, %Subscription{}}

  """
  def mark_as_cancelled(%Subscription{} = subscription) do
    update_subscription(subscription, %{stripe_status: "cancelled"})
  end

  @doc """
  Cancels a subscription in Stripe by scheduling cancellation at the end of the current period.
  This makes the subscription resumable until the period ends.

  ## Examples

      iex> cancel(subscription)
      {:ok, %Subscription{}}

  """
  def cancel(subscription_or_map, opts \\ [])

  def cancel(%Subscription{} = subscription, opts) do
    stripe_params = opts[:stripe] || %{}
    params = Map.merge(stripe_params, %{cancel_at_period_end: true})

    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           Stripe.Subscription.update(subscription.stripe_id, params)
         end) do
      {:ok, stripe_subscription} ->
        ends_at =
          if subscription.trial_ends_at &&
               DateTime.compare(subscription.trial_ends_at, DateTime.utc_now()) ==
                 :gt do
            subscription.trial_ends_at
          else
            SubscriptionHelpers.current_period_end(stripe_subscription)
            |> DateTime.from_unix!()
            |> DateTime.truncate(:second)
          end

        case subscription
             |> Ecto.Changeset.change(%{
               stripe_status: stripe_subscription.status,
               ends_at: ends_at
             })
             |> Repo.update() do
          {:ok, updated_subscription} ->
            if updated_subscription.user_id do
              invalidate_membership_caches(updated_subscription.user_id)
            end

            updated_subscription
            |> Repo.preload(:subscription_items)
            |> then(&sync_board_pause_after({:ok, &1}))

          {:error, changeset} ->
            {:error, changeset}
        end

      {:error, error} ->
        Ysc.Logging.error("Failed to cancel subscription in Stripe",
          error: error
        )

        {:error,
         "We couldn't turn off auto-renewal right now. Please try again in a few minutes, or email #{Ysc.EmailConfig.membership_email()} for help."}
    end
  end

  def cancel(%{type: :lifetime}, _opts),
    do: {:error, "Lifetime memberships cannot be cancelled"}

  def cancel(nil, _opts), do: {:error, "No subscription to cancel"}

  @doc """
  Immediately cancels a subscription in Stripe (permanent deletion).
  This should only be used for admin purposes or special cases where resumability is not needed.

  ## Examples

      iex> cancel_immediately(subscription)
      {:ok, %Subscription{}}

  """
  def cancel_immediately(%Subscription{} = subscription) do
    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           Stripe.Subscription.cancel(subscription.stripe_id)
         end) do
      {:ok, _stripe_subscription} ->
        mark_as_cancelled(subscription)

      {:error, _error} ->
        {:error, "Failed to cancel subscription immediately in Stripe"}
    end
  end

  @doc """
  Resumes a cancelled subscription in Stripe.

  ## Examples

      iex> resume(subscription)
      {:ok, %Subscription{}}

  """
  def resume(%Subscription{} = subscription) do
    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           Stripe.Subscription.update(subscription.stripe_id, %{
             cancel_at_period_end: false
           })
         end) do
      {:ok, stripe_subscription} ->
        subscription
        |> update_subscription(%{
          stripe_status: stripe_subscription.status,
          current_period_end:
            SubscriptionHelpers.current_period_end(stripe_subscription)
            |> DateTime.from_unix!()
            |> DateTime.truncate(:second),
          ends_at: nil
        })
        |> sync_board_pause_after()

      {:error, _error} ->
        {:error, "Failed to resume subscription in Stripe"}
    end
  end

  def resume(%{type: :lifetime}),
    do: {:error, "Lifetime memberships cannot be resumed"}

  def resume(nil), do: {:error, "No subscription to resume"}

  @doc """
  Changes the prices/items for a subscription.

  ## Examples

      iex> change_prices(subscription, prices: [%{price: "price_123", quantity: 1}])
      {:ok, %Subscription{}}

  """
  def change_prices(%Subscription{} = subscription, params) do
    # Get current subscription items (for potential future use)
    _current_items =
      Repo.preload(subscription, :subscription_items).subscription_items

    # Create new items from params
    new_items =
      Enum.map(params.prices, fn price ->
        %{
          price: price.price,
          quantity: price.quantity
        }
      end)

    # Update subscription in Stripe
    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           Stripe.Subscription.update(subscription.stripe_id, %{
             items: new_items
           })
         end) do
      {:ok, stripe_subscription} ->
        # Update local subscription
        update_subscription(subscription, %{
          stripe_status: stripe_subscription.status,
          current_period_end:
            case SubscriptionHelpers.current_period_end(stripe_subscription) do
              nil -> nil
              timestamp -> DateTime.from_unix!(timestamp)
            end
        })

      {:error, _error} ->
        {:error, "Failed to change subscription prices in Stripe"}
    end
  end

  @doc """
  Updates the subscription period end date using subscription schedules.
  This creates a schedule that overrides when the current subscription period ends.

  ## Examples

      iex> update_period_end(subscription, ~U[2024-12-31 23:59:59Z])
      {:ok, %Subscription{}}

  """
  def update_period_end(
        %Subscription{} = subscription,
        %DateTime{} = new_end_date
      ) do
    # Convert DateTime to Unix timestamp for Stripe
    end_timestamp = DateTime.to_unix(new_end_date)

    # First, retrieve the current subscription to get its items and current period
    with {:ok, stripe_sub} <-
           Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             Stripe.Subscription.retrieve(subscription.stripe_id)
           end),
         :ok <- cancel_existing_schedules(stripe_sub.id),
         {:ok, _schedule} <-
           create_subscription_schedule(stripe_sub, end_timestamp) do
      case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             Stripe.Subscription.retrieve(subscription.stripe_id)
           end) do
        {:ok, updated_stripe_subscription} ->
          # Update local subscription with new period dates
          # The schedule will control the actual period end
          subscription
          |> update_subscription(%{
            stripe_status: updated_stripe_subscription.status,
            current_period_start:
              case SubscriptionHelpers.current_period_start(
                     updated_stripe_subscription
                   ) do
                nil -> nil
                timestamp -> DateTime.from_unix!(timestamp)
              end,
            # Use the schedule's end date or the subscription's current_period_end
            current_period_end: DateTime.from_unix!(end_timestamp)
          })
          |> sync_board_pause_after()

        {:error, error} ->
          {:error, error}
      end
    else
      {:error, error} -> {:error, error}
    end
  end

  # Helper function to cancel any existing schedules
  @dialyzer {:nowarn_function, cancel_existing_schedules: 1}
  defp cancel_existing_schedules(subscription_id) do
    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           Stripe.SubscriptionSchedule.list(%{subscription: subscription_id})
         end) do
      {:ok, %{data: schedules}} when schedules != [] ->
        schedules
        |> Enum.filter(&(&1.status != "canceled"))
        |> Enum.reduce_while(:ok, fn schedule, :ok ->
          case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                 Stripe.SubscriptionSchedule.cancel(schedule.id)
               end) do
            {:ok, _} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      {:ok, %{data: []}} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper function to create subscription schedule
  # Uses a two-step approach: first create schedule from subscription, then update with phases
  @dialyzer {:nowarn_function, create_subscription_schedule: 2}
  defp create_subscription_schedule(stripe_sub, end_timestamp) do
    # Step 1: Create schedule from subscription (without phases)
    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           Stripe.SubscriptionSchedule.create(%{
             from_subscription: stripe_sub.id
           })
         end) do
      {:ok, schedule} ->
        items =
          Enum.map(stripe_sub.items.data, fn item ->
            %{
              price: item.price.id,
              quantity: item.quantity
            }
          end)

        start_timestamp = SubscriptionHelpers.current_period_start(stripe_sub)

        phase = %{
          items: items,
          start_date: start_timestamp,
          end_date: end_timestamp
        }

        case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
               Stripe.SubscriptionSchedule.update(schedule.id, %{
                 phases: [phase],
                 end_behavior: "release"
               })
             end) do
          {:ok, _} = ok ->
            ok

          {:error, _} = error ->
            Ysc.Stripe.RetryHelper.stripe_retry(fn ->
              Stripe.SubscriptionSchedule.cancel(schedule.id)
            end)

            error
        end

      error ->
        error
    end
  end

  @doc """
  Gets the active subscription for a user (if any).

  ## Examples

      iex> get_active_subscription(user)
      %Subscription{}

      iex> get_active_subscription(user)
      nil

  """
  def get_active_subscription(%Ysc.Accounts.User{} = user) do
    user
    |> list_subscriptions()
    |> Enum.find(&active?/1)
  end

  # Used by create_stripe_subscription/2 and activate_membership_with_saved_payment_method/2.
  # Broader than active?/1: Stripe still has an open subscription for past_due, unpaid,
  # incomplete, paused, etc.; creating another would risk double billing. Migration
  # placeholders (stripe_id migrated_*) are excluded so a real Stripe subscription can
  # replace imported rows.
  #
  # Incomplete alone is not treated as "already active" for saved-payment activation —
  # create_stripe_subscription/2 retries those with a new payment method. Hard blockers
  # (active, trialing, past_due, unpaid, paused) still short-circuit activation.
  defp duplicate_create_blocked_by_existing_subscription?(
         %Ysc.Accounts.User{} = user
       ) do
    case find_blocking_subscription(user) do
      %Subscription{stripe_status: "incomplete"} -> false
      %Subscription{} -> true
      nil -> false
    end
  end

  defp subscription_blocks_new_stripe_duplicate?(%Subscription{} = sub) do
    cond do
      is_binary(sub.stripe_id) and
          String.starts_with?(sub.stripe_id, "migrated_") ->
        false

      sub.stripe_status in ["canceled", "incomplete_expired"] ->
        false

      sub.stripe_status in ["past_due", "unpaid", "incomplete"] ->
        true

      sub.stripe_status == "paused" ->
        true

      active?(sub) ->
        true

      true ->
        false
    end
  end

  @doc """
  Change membership plan with correct billing behavior:
  - Upgrades: charge proration delta immediately.
  - Downgrades: take effect at next renewal (no immediate credit/refund).

  Prevents downgrades if user has sub-accounts.
  """
  def change_membership_plan(%{type: :lifetime}, _new_price_id, _direction),
    do: {:error, "Lifetime memberships cannot be changed"}

  def change_membership_plan(nil, _new_price_id, _direction),
    do: {:error, "No active subscription found"}

  def change_membership_plan(
        %Subscription{} = subscription,
        new_price_id,
        direction
      ) do
    # Prevent downgrade if user has sub-accounts
    if direction == :downgrade do
      user = Repo.preload(subscription, :user).user
      sub_accounts = Ysc.Accounts.get_sub_accounts(user)

      if sub_accounts != [] do
        {:error,
         "Cannot switch to a single-person membership while family members are still linked to your account. On the Family page, remove each linked family member, then try again."}
      else
        do_change_membership_plan(subscription, new_price_id, direction)
      end
    else
      do_change_membership_plan(subscription, new_price_id, direction)
    end
  end

  defp do_change_membership_plan(
         %Subscription{} = subscription,
         new_price_id,
         direction
       ) do
    result =
      case Application.get_env(:ysc, :change_membership_plan_stripe_callback) do
        callback when is_function(callback, 3) ->
          callback.(subscription, new_price_id, direction)

        _ ->
          do_change_membership_plan_stripe(
            subscription,
            new_price_id,
            direction
          )
      end

    sync_board_pause_after(result)
  end

  @dialyzer {:nowarn_function, do_change_membership_plan_stripe: 3}
  defp do_change_membership_plan_stripe(
         %Subscription{} = subscription,
         new_price_id,
         direction
       ) do
    # Callback allows tests to stub the initial retrieve (avoid hitting Stripe).
    initial_retrieve_fn =
      Application.get_env(
        :ysc,
        :subscription_retrieve_initial_plan_change_callback
      ) ||
        fn sid, opts ->
          Ysc.Stripe.RetryHelper.stripe_retry(fn ->
            Stripe.Subscription.retrieve(sid, opts)
          end)
        end

    with {:ok, stripe_sub} <-
           initial_retrieve_fn.(subscription.stripe_id, %{
             expand: ["items.data.price"]
           }),
         [first_item | _] when first_item != nil <- stripe_sub.items.data do
      current_price_id =
        if is_binary(first_item.price),
          do: first_item.price,
          else: first_item.price.id

      stripe_item_id = first_item.id

      # Same price selected
      if current_price_id == new_price_id do
        # If subscription has a scheduled downgrade, release it to cancel
        if stripe_sub.schedule do
          case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                 Stripe.SubscriptionSchedule.release(stripe_sub.schedule)
               end) do
            {:ok, _} -> {:ok, subscription}
            {:error, error} -> {:error, error}
          end
        else
          {:ok, subscription}
        end
      else
        case direction do
          :upgrade ->
            # Release any existing schedule first (e.g. scheduled downgrade user is canceling)
            with {:ok, _stripe_sub} <- maybe_release_schedule(stripe_sub) do
              # For upgrades: charge proration delta immediately and update subscription.
              # Note: Manual (paid elsewhere) memberships have no default payment method in
              # Stripe; the user settings flow requires a payment method before allowing
              # upgrade. Without one, Stripe would create an unpaid invoice and the
              # subscription would go incomplete.
              # Board households use proration_behavior: "none" (billing is paused /
              # voided while on the board). Otherwise always_invoice for immediate charge.
              update_items = [
                %{id: stripe_item_id, price: new_price_id, quantity: 1}
              ]

              proration_behavior =
                if board_household_for_subscription?(subscription) do
                  "none"
                else
                  "always_invoice"
                end

              update_params = %{
                items: update_items,
                proration_behavior: proration_behavior,
                billing_cycle_anchor: "unchanged"
              }

              # Callback allows tests to stub the update (avoid hitting Stripe).
              update_fn =
                Application.get_env(
                  :ysc,
                  :subscription_update_plan_change_callback
                ) ||
                  fn sid, params ->
                    Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                      Stripe.Subscription.update(sid, params)
                    end)
                  end

              case update_fn.(subscription.stripe_id, update_params) do
                {:ok, _stripe_subscription} ->
                  # Retrieve updated subscription to sync with Stripe.
                  # Do not overwrite with "incomplete": when Stripe creates an invoice for
                  # the proration, status can be "incomplete" until payment. If we save that,
                  # the user would see no membership until invoice is paid. Keep existing
                  # record so the user retains membership; subscription.updated will sync
                  # when payment succeeds.
                  # Callback allows tests to stub the retrieve (e.g. return status "incomplete").
                  retrieve_fn =
                    Application.get_env(
                      :ysc,
                      :subscription_retrieve_after_plan_change_callback
                    ) ||
                      fn sid ->
                        Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                          Stripe.Subscription.retrieve(sid)
                        end)
                      end

                  case retrieve_fn.(subscription.stripe_id) do
                    {:ok, updated_stripe_subscription} ->
                      if updated_stripe_subscription.status in [
                           "active",
                           "trialing"
                         ] do
                        update_subscription(subscription, %{
                          stripe_status: updated_stripe_subscription.status,
                          current_period_start:
                            case SubscriptionHelpers.current_period_start(
                                   updated_stripe_subscription
                                 ) do
                              nil -> nil
                              timestamp -> DateTime.from_unix!(timestamp)
                            end,
                          current_period_end:
                            case SubscriptionHelpers.current_period_end(
                                   updated_stripe_subscription
                                 ) do
                              nil -> nil
                              timestamp -> DateTime.from_unix!(timestamp)
                            end
                        })
                      else
                        # Status is incomplete (or similar); leave DB unchanged so user
                        # keeps current membership until payment completes
                        {:ok, subscription}
                      end

                    {:error, error} ->
                      {:error, error}
                  end

                {:error, error} ->
                  {:error, error}
              end
            end

          :downgrade ->
            # For downgrades: use subscription schedule so change takes effect at next
            # billing cycle. Customer keeps current plan (e.g. Family) until renewal,
            # then switches to lower plan (e.g. Single). No immediate charge or credit.
            schedule_downgrade_at_renewal(
              subscription,
              stripe_sub,
              first_item,
              new_price_id
            )
        end
      end
    else
      {:error, error} -> {:error, error}
      _ -> {:error, :invalid_subscription_items}
    end
  end

  defp maybe_release_schedule(%{schedule: nil} = stripe_sub),
    do: {:ok, stripe_sub}

  defp maybe_release_schedule(%{schedule: schedule_id} = stripe_sub) do
    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           Stripe.SubscriptionSchedule.release(schedule_id)
         end) do
      {:ok, _} -> {:ok, stripe_sub}
      {:error, _} = error -> error
    end
  end

  @dialyzer {:nowarn_function, schedule_downgrade_at_renewal: 4}
  defp schedule_downgrade_at_renewal(
         subscription,
         stripe_sub,
         first_item,
         new_price_id
       ) do
    current_price_id =
      if is_binary(first_item.price),
        do: first_item.price,
        else: first_item.price.id

    current_period_end = SubscriptionHelpers.current_period_end(stripe_sub)
    current_period_start = SubscriptionHelpers.current_period_start(stripe_sub)

    # Phase 1: current plan until period end
    phase1_items = [
      %{price: current_price_id, quantity: first_item.quantity || 1}
    ]

    phase1 = %{
      items: phase1_items,
      start_date: current_period_start,
      end_date: current_period_end,
      proration_behavior: "none"
    }

    # Phase 2: downgraded plan, starts at period end. Use end_date (duration
    # param not supported in all Stripe API versions). Set to 1 year from
    # period end for annual billing.
    phase2_items = [%{price: new_price_id, quantity: 1}]

    phase2_end_date = current_period_end + 365 * 24 * 60 * 60

    phase2 = %{
      items: phase2_items,
      start_date: current_period_end,
      end_date: phase2_end_date,
      proration_behavior: "none"
    }

    result =
      if stripe_sub.schedule do
        Ysc.Stripe.RetryHelper.stripe_retry(fn ->
          Stripe.SubscriptionSchedule.update(stripe_sub.schedule, %{
            phases: [phase1, phase2],
            end_behavior: "release"
          })
        end)
      else
        with {:ok, schedule} <-
               Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                 Stripe.SubscriptionSchedule.create(%{
                   from_subscription: stripe_sub.id
                 })
               end) do
          case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                 Stripe.SubscriptionSchedule.update(schedule.id, %{
                   phases: [phase1, phase2],
                   end_behavior: "release"
                 })
               end) do
            {:ok, _} ->
              {:ok, schedule}

            {:error, _} = error ->
              Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                Stripe.SubscriptionSchedule.cancel(schedule.id)
              end)

              error
          end
        end
      end

    case result do
      {:ok, _} ->
        # Do NOT update local subscription - it stays on current plan until webhook
        # fires when schedule phase transitions at renewal
        {:scheduled, subscription}

      {:error, error} ->
        {:error, error}
    end
  end

  # Stripe integration functions

  @doc """
  Creates a subscription struct from a Stripe subscription.

  ## Examples

      iex> subscription_struct_from_stripe_subscription(user, stripe_subscription)
      %Ecto.Changeset{data: %Subscription{}}

  """
  def subscription_struct_from_stripe_subscription(
        user,
        %Stripe.Subscription{} = stripe_subscription
      ) do
    attrs = %{
      stripe_id: stripe_subscription.id,
      stripe_status: stripe_subscription.status,
      user_id: user.id,
      # Default name for membership subscriptions
      name: "Membership Subscription",
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

    %Subscription{}
    |> Subscription.changeset(attrs)
  end

  @doc """
  Creates subscription item structs from Stripe subscription items.

  ## Examples

      iex> subscription_item_structs_from_stripe_items(stripe_items, subscription)
      [%Ecto.Changeset{data: %SubscriptionItem{}}, ...]

  """
  def subscription_item_structs_from_stripe_items(stripe_items, subscription) do
    Enum.map(stripe_items, fn stripe_item ->
      attrs = %{
        stripe_id: stripe_item.id,
        stripe_product_id: stripe_item.price.product,
        stripe_price_id: stripe_item.price.id,
        quantity: stripe_item.quantity,
        subscription_id: subscription.id
      }

      %SubscriptionItem{}
      |> SubscriptionItem.changeset(attrs)
    end)
  end

  @doc """
  Creates a subscription in Stripe.

  Returns `{:error, :user_already_has_active_subscription}` if the user already has
  a subscription in Stripe that must not be duplicated—active, trialing, past due,
  unpaid, incomplete checkout, paused, etc. WP migration placeholders (`migrated_*`)
  do not block. This prevents double subscriptions that would lead to double billing.

  ## Examples

      iex> create_stripe_subscription(user, %{prices: [%{price: "price_123", quantity: 1}]})
      {:ok, %Stripe.Subscription{}}

      iex> create_stripe_subscription(user_with_active_subscription, %{prices: [%{price: "price_123", quantity: 1}]})
      {:error, :user_already_has_active_subscription}

  """
  @dialyzer {:nowarn_function, create_stripe_subscription: 2}
  def create_stripe_subscription(user, params) do
    case find_blocking_subscription(user) do
      nil ->
        do_create_stripe_subscription(user, params)

      %Subscription{stripe_status: "incomplete"} = incomplete_sub ->
        retry_incomplete_subscription(user, incomplete_sub, params)

      %Subscription{} ->
        {:error, :user_already_has_active_subscription}
    end
  end

  defp do_create_stripe_subscription(user, params) do
    # Handle both keyword lists and maps
    prices = params[:prices] || params["prices"] || params.prices
    expand = params[:expand] || params["expand"] || []
    idempotency_key = params[:idempotency_key] || params["idempotency_key"]

    stripe_params = %{
      customer: user.stripe_id,
      items:
        Enum.map(prices, fn price ->
          %{price: price.price, quantity: price.quantity}
        end),
      expand: expand,
      metadata: %{
        user_id: user.id
      }
    }

    stripe_params =
      if params[:default_payment_method] || params["default_payment_method"] do
        default_pm =
          params[:default_payment_method] || params["default_payment_method"]

        Map.put(stripe_params, :default_payment_method, default_pm)
      else
        stripe_params
      end

    stripe_params =
      Map.merge(
        stripe_params,
        BoardVolunteerBilling.maybe_pause_collection_params(user)
      )

    result =
      if idempotency_key do
        Ysc.Stripe.RetryHelper.stripe_retry(fn ->
          stripe_subscription_module().create(stripe_params,
            headers: %{
              "Idempotency-Key" => Ysc.Stripe.Idempotency.key(idempotency_key)
            }
          )
        end)
      else
        Ysc.Stripe.RetryHelper.stripe_retry(fn ->
          stripe_subscription_module().create(stripe_params)
        end)
      end

    case result do
      {:ok, _} = ok ->
        if BoardVolunteerBilling.household_on_board?(user) do
          BoardVolunteerBilling.sync_for_user(user)
        end

        ok

      error ->
        error
    end
  end

  # Used by create_stripe_subscription/2 to find the specific blocking
  # subscription (rather than just a boolean) so an "incomplete" one — whose
  # very first invoice was never paid — can be retried with a new payment
  # method instead of leaving the user permanently stuck. Other blocking
  # statuses (active, trialing, past_due, paused) are left as a hard block.
  #
  # Hard blockers are preferred over incomplete: list_subscriptions/1 has no
  # stable order, and retrying an incomplete invoice while another real
  # subscription already exists would risk double-billing.
  defp find_blocking_subscription(%Ysc.Accounts.User{} = user) do
    blocking =
      user
      |> list_subscriptions()
      |> Enum.filter(&subscription_blocks_new_stripe_duplicate?/1)

    Enum.find(blocking, &(&1.stripe_status != "incomplete")) ||
      Enum.find(blocking, &(&1.stripe_status == "incomplete"))
  end

  # Retries an "incomplete" subscription (first invoice never paid) using a
  # newly supplied payment method, instead of unconditionally returning
  # :user_already_has_active_subscription. Nothing else in the codebase ever
  # updates an existing subscription's pinned default_payment_method or
  # retries its open invoice, so without this a customer whose first payment
  # was declined is permanently blocked from ever completing checkout — even
  # after adding a working card or bank account.
  defp retry_incomplete_subscription(
         %Ysc.Accounts.User{} = user,
         %Subscription{} = incomplete_sub,
         params
       ) do
    default_pm =
      params[:default_payment_method] || params["default_payment_method"]

    if is_nil(default_pm) do
      {:error, :user_already_has_active_subscription}
    else
      case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             stripe_subscription_module().update(
               incomplete_sub.stripe_id,
               %{default_payment_method: default_pm, expand: ["latest_invoice"]}
             )
           end) do
        {:ok, stripe_sub} ->
          retry_incomplete_subscription_invoice(user, stripe_sub, default_pm)

        {:error, error} = err ->
          Ysc.Logging.error(
            "Failed to update payment method on incomplete subscription for retry",
            user_id: user.id,
            stripe_subscription_id: incomplete_sub.stripe_id,
            error: inspect(error)
          )

          err
      end
    end
  end

  defp retry_incomplete_subscription_invoice(user, stripe_sub, default_pm) do
    case invoice_id_from_expand(stripe_sub.latest_invoice) do
      nil ->
        Ysc.Logging.error(
          "Incomplete subscription has no open invoice to retry",
          user_id: user.id,
          stripe_subscription_id: stripe_sub.id
        )

        {:error, :user_already_has_active_subscription}

      invoice_id ->
        case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
               stripe_invoice_module().pay(invoice_id, %{
                 payment_method: default_pm
               })
             end) do
          {:ok, _paid_invoice} ->
            refreshed_sub =
              case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                     stripe_subscription_module().retrieve(stripe_sub.id)
                   end) do
                {:ok, sub} -> sub
                {:error, _} -> stripe_sub
              end

            Ysc.Logging.info(
              "Retried incomplete subscription with new payment method",
              user_id: user.id,
              stripe_subscription_id: refreshed_sub.id,
              invoice_id: invoice_id
            )

            {:ok, refreshed_sub}

          {:error, error} = err ->
            Ysc.Logging.warning(
              "Retrying incomplete subscription invoice with new payment method failed",
              user_id: user.id,
              stripe_subscription_id: stripe_sub.id,
              invoice_id: invoice_id,
              error: inspect(error)
            )

            err
        end
    end
  end

  @doc """
  Creates a membership subscription that is already paid (e.g. cash, check).

  Use this when a user pays for membership outside Stripe. Creates the subscription
  in Stripe with an open first invoice, then marks that invoice as paid out of band.
  The subscription becomes active and our webhooks (or immediate sync) create the
  local subscription and payment record.

  ## Options

  - `:plan_id` - Required. Plan atom, e.g. `:single` or `:family` (not `:lifetime`).

  ## Examples

      iex> create_subscription_paid_out_of_band(user, :single)
      {:ok, %Subscription{}}

      iex> create_subscription_paid_out_of_band(user, :family)
      {:ok, %Subscription{}}

      iex> create_subscription_paid_out_of_band(sub_account_user, :single)
      {:error, :sub_accounts_cannot_create_subscriptions}
  """
  def create_subscription_paid_out_of_band(%Ysc.Accounts.User{} = user, plan_id)
      when plan_id in [:single, :family] do
    require Ysc.Logging

    if Ysc.Accounts.sub_account?(user) do
      {:error, :sub_accounts_cannot_create_subscriptions}
    else
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      plan = Enum.find(membership_plans, &(&1.id == plan_id))

      cond do
        is_nil(plan) or is_nil(plan.stripe_price_id) ->
          {:error, :invalid_plan}

        get_active_subscription(user) != nil ->
          {:error, :user_already_has_active_subscription}

        true ->
          user = ensure_user_has_stripe_id(user)

          if is_nil(user.stripe_id) do
            {:error, :could_not_create_stripe_customer}
          else
            do_create_subscription_paid_out_of_band(user, plan)
          end
      end
    end
  end

  def create_subscription_paid_out_of_band(_user, _plan_id),
    do: {:error, :invalid_plan}

  @dialyzer {:nowarn_function, ensure_user_has_stripe_id: 1}
  defp ensure_user_has_stripe_id(%{stripe_id: nil} = user) do
    case Ysc.Customers.create_stripe_customer(user) do
      {:ok, _} -> Ysc.Accounts.get_user!(user.id)
      {:error, _} -> user
    end
  end

  defp ensure_user_has_stripe_id(user), do: user

  defp do_create_subscription_paid_out_of_band(user, plan) do
    require Ysc.Logging

    # Optional callback for tests to inject a fake Stripe subscription without calling Stripe API
    case Application.get_env(
           :ysc,
           :create_subscription_paid_out_of_band_stripe_callback
         ) do
      nil ->
        do_create_subscription_paid_out_of_band_stripe(user, plan)

      callback when is_function(callback, 2) ->
        case callback.(user, plan) do
          {:ok, stripe_subscription} ->
            case create_subscription_from_stripe(user, stripe_subscription) do
              {:ok, subscription} ->
                subscription = Repo.preload(subscription, :subscription_items)

                send_membership_confirmation_email_for_paid_elsewhere(
                  user,
                  plan
                )

                if BoardVolunteerBilling.household_on_board?(user) do
                  BoardVolunteerBilling.sync_for_user(user)
                end

                {:ok, subscription}

              err ->
                err
            end

          {:error, _} = err ->
            err
        end
    end
  end

  @doc false
  def paid_out_of_band_stripe_create_params(user, plan) do
    %{
      customer: user.stripe_id,
      items: [%{price: plan.stripe_price_id, quantity: 1}],
      payment_behavior: "default_incomplete",
      expand: ["latest_invoice"],
      metadata: %{user_id: user.id}
    }
    |> Map.merge(BoardVolunteerBilling.maybe_pause_collection_params(user))
  end

  @dialyzer {:nowarn_function,
             do_create_subscription_paid_out_of_band_stripe: 2}
  defp do_create_subscription_paid_out_of_band_stripe(user, plan) do
    require Ysc.Logging

    stripe_params = paid_out_of_band_stripe_create_params(user, plan)

    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           Stripe.Subscription.create(stripe_params)
         end) do
      {:ok, stripe_subscription} ->
        latest_invoice = stripe_subscription.latest_invoice
        invoice_id = invoice_id_from_expand(latest_invoice)

        case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
               Stripe.Invoice.pay(invoice_id, %{paid_out_of_band: true})
             end) do
          {:ok, _paid_invoice} ->
            stripe_subscription =
              case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                     Stripe.Subscription.retrieve(stripe_subscription.id, %{
                       expand: ["items.data.price"]
                     })
                   end) do
                {:ok, sub} -> sub
                {:error, _} -> stripe_subscription
              end

            case create_subscription_from_stripe(user, stripe_subscription) do
              {:ok, subscription} ->
                subscription = Repo.preload(subscription, :subscription_items)

                send_membership_confirmation_email_for_paid_elsewhere(
                  user,
                  plan
                )

                if BoardVolunteerBilling.household_on_board?(user) do
                  BoardVolunteerBilling.sync_for_user(user)
                end

                {:ok, subscription}

              err ->
                Ysc.Logging.error(
                  "Failed to create local subscription after paid-out-of-band",
                  user_id: user.id,
                  stripe_subscription_id: stripe_subscription.id,
                  error: inspect(err)
                )

                err
            end

          {:error, err} ->
            Ysc.Logging.error("Failed to mark invoice as paid out of band",
              user_id: user.id,
              invoice_id: invoice_id,
              error: inspect(err)
            )

            {:error, err}
        end

      {:error, err} ->
        {:error, err}
    end
  end

  defp invoice_id_from_expand(id) when is_binary(id), do: id
  defp invoice_id_from_expand(%{id: id}), do: id
  defp invoice_id_from_expand(nil), do: nil

  defp send_membership_confirmation_email_for_paid_elsewhere(user, plan) do
    require Ysc.Logging

    try do
      amount = Money.new(plan.amount, :USD)
      payment_date = Date.utc_today()

      YscWeb.Emails.Notifier.deliver_membership_payment_confirmation(
        user,
        plan.id,
        amount,
        payment_date,
        paid_elsewhere: true
      )
    rescue
      error ->
        Ysc.Logging.warning(
          "Failed to send membership confirmation email for paid-elsewhere subscription",
          user_id: user.id,
          error: Exception.message(error)
        )
    end
  end

  @doc """
  Creates a local subscription from a Stripe subscription.
  This is used as a backup when webhooks might not be reliable.

  ## Options

    * `:payment_method_type` - when `:bank_account` and Stripe status is
      `"incomplete"` (ACH still processing), persist local status as `"active"`
      so membership access is granted immediately.
  """
  def create_subscription_from_stripe(user, stripe_subscription, opts \\ []) do
    require Ysc.Logging

    # Check if subscription already exists
    existing = get_subscription_by_stripe_id(stripe_subscription.id)

    if existing do
      Ysc.Logging.info("Subscription already exists locally",
        user_id: user.id,
        subscription_id: existing.id,
        stripe_subscription_id: stripe_subscription.id
      )

      maybe_activate_existing_incomplete_bank_subscription(
        user,
        existing,
        stripe_subscription,
        opts
      )
    else
      stripe_status =
        local_stripe_status_for_persist(
          stripe_subscription.status,
          Keyword.get(opts, :payment_method_type)
        )

      # Create the subscription
      subscription_changeset =
        user
        |> Ecto.build_assoc(:subscriptions)
        |> Subscription.changeset(%{
          user_id: user.id,
          # Default name for membership subscriptions
          name: "Membership Subscription",
          stripe_id: stripe_subscription.id,
          stripe_status: stripe_status,
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
        })

      subscription = Repo.insert(subscription_changeset)

      case subscription do
        {:ok, subscription} ->
          # Create subscription items
          subscription_items =
            subscription_item_structs_from_stripe_items(
              stripe_subscription.items.data,
              subscription
            )

          Enum.each(subscription_items, fn item ->
            case Repo.insert(item) do
              {:ok, _} ->
                :ok

              {:error, reason} ->
                Ysc.Logging.error("Failed to create subscription item",
                  user_id: user.id,
                  subscription_id: subscription.id,
                  error: reason
                )
            end
          end)

          Ysc.Logging.info("Successfully created subscription from Stripe",
            user_id: user.id,
            subscription_id: subscription.id,
            stripe_subscription_id: stripe_subscription.id
          )

          # Invalidate membership cache when subscription is created
          invalidate_membership_caches(user.id)
          broadcast_membership_updated(user.id)

          {:ok, subscription}

        {:error, reason} ->
          Ysc.Logging.error("Failed to create subscription from Stripe",
            user_id: user.id,
            stripe_subscription_id: stripe_subscription.id,
            error: reason
          )

          {:error, reason}
      end
    end
  end

  # When a prior attempt left an incomplete local row, sync it from Stripe so
  # membership access matches a successful retry (card) or grant access while
  # ACH is still processing on Stripe.
  defp maybe_activate_existing_incomplete_bank_subscription(
         user,
         existing,
         stripe_subscription,
         opts
       ) do
    payment_method_type = Keyword.get(opts, :payment_method_type)

    cond do
      existing.stripe_status == "incomplete" and
          stripe_subscription.status in ["active", "trialing"] ->
        sync_existing_subscription_from_stripe(user, existing, stripe_subscription)

      stripe_subscription.status == "incomplete" and
          payment_method_type == :bank_account and
          existing.stripe_status != "active" ->
        case existing
             |> Subscription.changeset(%{stripe_status: "active"})
             |> Repo.update() do
          {:ok, updated} ->
            invalidate_membership_caches(user.id)
            broadcast_membership_updated(user.id)
            {:ok, updated}

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        {:ok, existing}
    end
  end

  defp sync_existing_subscription_from_stripe(user, existing, stripe_subscription) do
    case update_subscription(existing, subscription_attrs_from_stripe(stripe_subscription)) do
      {:ok, updated} ->
        invalidate_membership_caches(user.id)
        broadcast_membership_updated(user.id)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp subscription_attrs_from_stripe(stripe_subscription) do
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

    if stripe_subscription.cancel_at do
      Map.put(attrs, :ends_at, DateTime.from_unix!(stripe_subscription.cancel_at))
    else
      attrs
    end
  end

  @doc """
  Persists a Stripe subscription locally, then removes WP migration placeholder rows.

  Placeholders are deleted only after the real row is stored so a failed insert cannot
  leave the member with no local subscription while Stripe already has an active sub.
  """
  def adopt_stripe_subscription_replacing_migrated(user, stripe_subscription) do
    with {:ok, subscription} <-
           create_subscription_from_stripe(user, stripe_subscription) do
      delete_migrated_placeholder_subscriptions(user)
      {:ok, subscription}
    end
  end

  @doc """
  Deletes WP migration placeholder subscriptions (`stripe_id` prefixed with `migrated_`).
  """
  def delete_migrated_placeholder_subscriptions(%Ysc.Accounts.User{} = user) do
    user
    |> list_subscriptions()
    |> Enum.filter(&migrated_placeholder_subscription?/1)
    |> Enum.each(&delete_migrated_placeholder_subscription/1)

    :ok
  end

  defp delete_migrated_placeholder_subscription(%Subscription{} = subscription) do
    case delete_subscription(subscription) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        require Ysc.Logging

        Ysc.Logging.warning(
          "Failed to remove migrated placeholder subscription",
          user_id: subscription.user_id,
          subscription_id: subscription.id,
          reason: inspect(reason)
        )

        :error
    end
  end

  defp migrated_placeholder_subscription?(%Subscription{stripe_id: stripe_id})
       when is_binary(stripe_id) do
    String.starts_with?(stripe_id, "migrated_")
  end

  defp migrated_placeholder_subscription?(_), do: false

  @doc """
  Retries payment for a failed invoice.

  Validates that the invoice belongs to the user and attempts to pay it via Stripe.

  ## Examples

      iex> retry_failed_invoice(user, "in_1234567890")
      {:ok, %Stripe.Invoice{}}

      iex> retry_failed_invoice(user, "invalid")
      {:error, :invoice_not_found}

  """
  @dialyzer {:nowarn_function, retry_failed_invoice: 2}
  def retry_failed_invoice(user, invoice_id) when is_binary(invoice_id) do
    require Ysc.Logging

    invoice_mod = stripe_invoice_module()

    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           invoice_mod.retrieve(invoice_id)
         end) do
      {:ok, invoice} ->
        customer_id = invoice.customer

        if customer_id != user.stripe_id do
          Ysc.Logging.warning("Invoice does not belong to user",
            user_id: user.id,
            invoice_id: invoice_id,
            invoice_customer: customer_id,
            user_stripe_id: user.stripe_id
          )

          {:error, :unauthorized}
        else
          if invoice.status == "paid" do
            Ysc.Logging.info("Invoice is already paid",
              user_id: user.id,
              invoice_id: invoice_id
            )

            {:error, :already_paid}
          else
            if invoice.status != "open" do
              Ysc.Logging.warning("Invoice is not in a payable state",
                user_id: user.id,
                invoice_id: invoice_id,
                invoice_status: invoice.status
              )

              {:error, :invalid_invoice_status}
            else
              Ysc.Logging.info("Attempting to retry payment for invoice",
                user_id: user.id,
                invoice_id: invoice_id
              )

              case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                     invoice_mod.pay(invoice_id, %{})
                   end) do
                {:ok, paid_invoice} ->
                  Ysc.Logging.info(
                    "Successfully retried payment for invoice",
                    user_id: user.id,
                    invoice_id: invoice_id,
                    invoice_status: paid_invoice.status
                  )

                  {:ok, paid_invoice}

                {:error, %Stripe.Error{} = error} ->
                  Ysc.Logging.error("Failed to retry payment for invoice",
                    user_id: user.id,
                    invoice_id: invoice_id,
                    error: error.message
                  )

                  {:error, error.message}
              end
            end
          end
        end

      {:error, %Stripe.Error{code: :not_found}} ->
        Ysc.Logging.warning("Invoice not found in Stripe",
          user_id: user.id,
          invoice_id: invoice_id
        )

        {:error, :invoice_not_found}

      {:error, %Stripe.Error{} = error} ->
        Ysc.Logging.error("Failed to retrieve invoice from Stripe",
          user_id: user.id,
          invoice_id: invoice_id,
          error: error.message
        )

        {:error, error.message}
    end
  end

  def retry_failed_invoice(_user, _invoice_id),
    do: {:error, :invalid_invoice_id}

  defp stripe_invoice_module do
    Application.get_env(:ysc, :stripe_invoice_module, Stripe.Invoice)
  end

  ## PubSub Functions

  @doc """
  Subscribe to membership update events for a specific user.
  """
  def subscribe_membership_updates(user_id) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, membership_topic(user_id))
  end

  defp membership_topic(user_id), do: "memberships:user:#{user_id}"

  defp broadcast_membership_updated(user_id) when not is_nil(user_id) do
    Phoenix.PubSub.broadcast(
      Ysc.PubSub,
      membership_topic(user_id),
      {__MODULE__,
       %Ysc.MessagePassingEvents.MembershipUpdated{user_id: user_id}}
    )
  end

  defp invalidate_membership_caches(user_id) when is_binary(user_id) do
    MembershipCache.invalidate_user(user_id)
    UserProfileCache.invalidate_user(user_id)
    :ok
  end

  defp sync_board_pause_after({:ok, %Subscription{} = subscription} = result) do
    sync_board_pause_for_subscription(subscription)
    result
  end

  defp sync_board_pause_after(
         {:scheduled, %Subscription{} = subscription} = result
       ) do
    sync_board_pause_for_subscription(subscription)
    result
  end

  defp sync_board_pause_after(other), do: other

  defp sync_board_pause_for_subscription(%Subscription{user_id: nil}), do: :ok

  defp sync_board_pause_for_subscription(%Subscription{} = subscription) do
    user =
      case subscription.user do
        %Ysc.Accounts.User{} = loaded -> loaded
        _ -> Ysc.Accounts.get_user!(subscription.user_id)
      end

    if BoardVolunteerBilling.household_on_board?(user) do
      BoardVolunteerBilling.sync_for_user(user)
    end

    :ok
  end

  defp board_household_for_subscription?(%Subscription{user_id: nil}), do: false

  defp board_household_for_subscription?(%Subscription{} = subscription) do
    user =
      case subscription.user do
        %Ysc.Accounts.User{} = loaded -> loaded
        _ -> Ysc.Accounts.get_user!(subscription.user_id)
      end

    BoardVolunteerBilling.household_on_board?(user)
  end

  @doc """
  Charges the user's default payment method and creates a local membership subscription.

  Used when approving an application and when an already-approved user saves a
  payment method during account setup or settings.

  ## Options

    * `:membership_type` - `:single` or `:family`. Defaults to the user's signup
      application membership type, or `:single`.
    * `:return_url` - Stripe return URL (required for subscription create).

  ## Returns

    * `{:ok, :activated}` - Stripe subscription created (and persisted when possible)
    * `{:ok, :already_active}` - user already has a blocking local subscription
    * `{:error, :no_payment_method}`
    * `{:error, :no_price_id}`
    * `{:error, :missing_return_url}`
    * `{:error, reason}` - Stripe or other failure
  """
  def activate_membership_with_saved_payment_method(
        %Ysc.Accounts.User{} = user,
        opts \\ []
      ) do
    if duplicate_create_blocked_by_existing_subscription?(user) do
      {:ok, :already_active}
    else
      do_activate_membership_with_saved_payment_method(user, opts)
    end
  end

  defp do_activate_membership_with_saved_payment_method(user, opts) do
    return_url = Keyword.get(opts, :return_url)

    if is_nil(return_url) or return_url == "" do
      {:error, :missing_return_url}
    else
      case Ysc.Payments.get_default_payment_method(user) do
        nil ->
          {:error, :no_payment_method}

        default_pm ->
          membership_type =
            Keyword.get(opts, :membership_type) ||
              resolve_membership_type_for_activation(user)

          case membership_price_id(membership_type) do
            nil ->
              Ysc.Logging.error(
                "No Stripe price ID found for membership type on activation",
                user_id: user.id,
                membership_type: inspect(membership_type)
              )

              {:error, :no_price_id}

            price_id ->
              create_and_persist_membership_subscription(
                user,
                default_pm,
                price_id,
                return_url
              )
          end
      end
    end
  end

  defp create_and_persist_membership_subscription(
         user,
         default_pm,
         price_id,
         return_url
       ) do
    case Ysc.Customers.create_subscription(
           user,
           return_url: return_url,
           prices: [%{price: price_id, quantity: 1}],
           default_payment_method: default_pm.provider_id,
           expand: ["latest_invoice"]
         ) do
      {:ok, stripe_subscription} ->
        case create_subscription_from_stripe(user, stripe_subscription,
               payment_method_type: default_pm.type
             ) do
          {:ok, _} ->
            invalidate_activation_membership_caches(user)
            {:ok, :activated}

          {:error, reason} ->
            Ysc.Logging.error(
              "Failed to persist Stripe subscription locally on activation",
              user_id: user.id,
              stripe_subscription_id: stripe_subscription.id,
              reason: inspect(reason)
            )

            # Stripe already charged; treat as activated so callers do not
            # re-prompt for payment. Webhooks can repair the local row.
            invalidate_activation_membership_caches(user)
            {:ok, :activated}
        end

      {:error, :user_already_has_active_subscription} ->
        {:ok, :already_active}

      {:error, reason} ->
        Ysc.Logging.error("Failed to auto-charge membership on activation",
          user_id: user.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # ACH Direct Debit can leave the Stripe subscription incomplete while the
  # PaymentIntent is processing (days). Grant local access immediately so the
  # member is not blocked until settlement.
  defp local_stripe_status_for_persist("incomplete", :bank_account),
    do: "active"

  defp local_stripe_status_for_persist(status, _payment_method_type), do: status

  defp invalidate_activation_membership_caches(user) do
    _ = MembershipCache.invalidate_user(user.id)

    user
    |> Ysc.Accounts.get_sub_accounts()
    |> Enum.each(&MembershipCache.invalidate_user(&1.id))

    :ok
  end

  defp resolve_membership_type_for_activation(user) do
    user = Ysc.Repo.preload(user, :registration_form)

    case user.registration_form do
      %{membership_type: type} when not is_nil(type) -> type
      _ -> :single
    end
  end

  defp membership_price_id(membership_type) do
    plans = Application.get_env(:ysc, :membership_plans, [])

    Enum.find_value(plans, fn plan ->
      if plan.id == membership_type, do: plan[:stripe_price_id]
    end)
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    user_id = Fixtures.ulid()

    from(s in Subscription,
      where: s.user_id == ^user_id,
      preload: :subscription_items
    )
  end
end
