defmodule Ysc.Subscriptions do
  @moduledoc """
  The Subscriptions context for managing subscriptions and subscription items.
  """

  import Ecto.Query, warn: false
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Repo
  alias Ysc.Subscriptions.{Subscription, SubscriptionItem}

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

    # Invalidate membership cache when subscription is updated
    case result do
      {:ok, updated_subscription} ->
        # Invalidate cache for the user
        if updated_subscription.user_id do
          MembershipCache.invalidate_user(updated_subscription.user_id)
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

    # Invalidate membership cache when subscription is deleted
    case result do
      {:ok, _} ->
        if user_id do
          MembershipCache.invalidate_user(user_id)
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

      # Subscription is active only if status is valid AND period is valid AND ends_at is valid
      status_valid? and period_valid? and ends_at_valid?
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

    case Stripe.Subscription.update(subscription.stripe_id, params) do
      {:ok, stripe_subscription} ->
        ends_at =
          if subscription.trial_ends_at &&
               DateTime.compare(subscription.trial_ends_at, DateTime.utc_now()) ==
                 :gt do
            subscription.trial_ends_at
          else
            stripe_subscription.current_period_end
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
            # Invalidate membership cache when subscription is cancelled
            if updated_subscription.user_id do
              MembershipCache.invalidate_user(updated_subscription.user_id)
            end

            {:ok, Repo.preload(updated_subscription, :subscription_items)}

          {:error, changeset} ->
            {:error, changeset}
        end

      {:error, error} ->
        {:error, "Failed to cancel subscription in Stripe: #{inspect(error)}"}
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
    case Stripe.Subscription.delete(subscription.stripe_id) do
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
    case Stripe.Subscription.update(subscription.stripe_id, %{
           cancel_at_period_end: false
         }) do
      {:ok, stripe_subscription} ->
        update_subscription(subscription, %{
          stripe_status: stripe_subscription.status,
          current_period_end:
            stripe_subscription.current_period_end
            |> DateTime.from_unix!()
            |> DateTime.truncate(:second),
          ends_at: nil
        })

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
    case Stripe.Subscription.update(subscription.stripe_id, %{items: new_items}) do
      {:ok, stripe_subscription} ->
        # Update local subscription
        update_subscription(subscription, %{
          stripe_status: stripe_subscription.status,
          current_period_end: stripe_subscription.current_period_end
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
           Stripe.Subscription.retrieve(subscription.stripe_id),
         # Cancel any existing schedules first
         :ok <- cancel_existing_schedules(stripe_sub.id),
         # Create new subscription schedule with the desired end date
         {:ok, _schedule} <-
           create_subscription_schedule(stripe_sub, end_timestamp) do
      # The schedule will automatically apply. Retrieve updated subscription to sync
      case Stripe.Subscription.retrieve(subscription.stripe_id) do
        {:ok, updated_stripe_subscription} ->
          # Update local subscription with new period dates
          # The schedule will control the actual period end
          update_subscription(subscription, %{
            stripe_status: updated_stripe_subscription.status,
            current_period_start:
              updated_stripe_subscription.current_period_start &&
                DateTime.from_unix!(
                  updated_stripe_subscription.current_period_start
                ),
            # Use the schedule's end date or the subscription's current_period_end
            current_period_end: DateTime.from_unix!(end_timestamp)
          })

        {:error, error} ->
          {:error, error}
      end
    else
      {:error, error} -> {:error, error}
    end
  end

  # Helper function to cancel any existing schedules
  defp cancel_existing_schedules(subscription_id) do
    case Stripe.SubscriptionSchedule.list(%{subscription: subscription_id}) do
      {:ok, %{data: schedules}} when schedules != [] ->
        # Cancel all existing schedules
        Enum.each(schedules, fn schedule ->
          if schedule.status != "canceled" do
            Stripe.SubscriptionSchedule.cancel(schedule.id)
          end
        end)

        :ok

      {:ok, %{data: []}} ->
        :ok

      _ ->
        :ok
    end
  end

  # Helper function to create subscription schedule
  # Uses a two-step approach: first create schedule from subscription, then update with phases
  defp create_subscription_schedule(stripe_sub, end_timestamp) do
    # Step 1: Create schedule from subscription (without phases)
    case Stripe.SubscriptionSchedule.create(%{
           from_subscription: stripe_sub.id
         }) do
      {:ok, schedule} ->
        # Step 2: Prepare subscription items for the schedule phase
        items =
          Enum.map(stripe_sub.items.data, fn item ->
            %{
              price: item.price.id,
              quantity: item.quantity
            }
          end)

        # Get the current period start from the subscription
        start_timestamp = stripe_sub.current_period_start

        # Step 3: Update the schedule with a phase that ends at the desired date
        phase = %{
          items: items,
          start_date: start_timestamp,
          end_date: end_timestamp
        }

        # Update the schedule with the new phase
        Stripe.SubscriptionSchedule.update(schedule.id, %{
          phases: [phase],
          end_behavior: "release"
        })

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
         "Cannot downgrade membership while you have sub-accounts. Please remove all sub-accounts first."}
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
    with {:ok, stripe_sub} <-
           Stripe.Subscription.retrieve(subscription.stripe_id),
         [first_item | _] when first_item != nil <- stripe_sub.items.data do
      current_price_id = first_item.price.id
      stripe_item_id = first_item.id

      # No-op if already on desired price
      if current_price_id == new_price_id do
        {:ok, subscription}
      else
        case direction do
          :upgrade ->
            # For upgrades: charge proration delta immediately and update subscription
            # Use proration_behavior: "always_invoice" to ensure immediate charge
            update_items = [
              %{id: stripe_item_id, price: new_price_id, quantity: 1}
            ]

            case Stripe.Subscription.update(subscription.stripe_id, %{
                   items: update_items,
                   proration_behavior: "always_invoice",
                   billing_cycle_anchor: "unchanged"
                 }) do
              {:ok, _stripe_subscription} ->
                # Retrieve updated subscription to sync with Stripe
                case Stripe.Subscription.retrieve(subscription.stripe_id) do
                  {:ok, updated_stripe_subscription} ->
                    update_subscription(subscription, %{
                      stripe_status: updated_stripe_subscription.status,
                      current_period_start:
                        updated_stripe_subscription.current_period_start &&
                          DateTime.from_unix!(
                            updated_stripe_subscription.current_period_start
                          ),
                      current_period_end:
                        updated_stripe_subscription.current_period_end &&
                          DateTime.from_unix!(
                            updated_stripe_subscription.current_period_end
                          )
                    })

                  {:error, error} ->
                    {:error, error}
                end

              {:error, error} ->
                {:error, error}
            end

          :downgrade ->
            # For downgrades: schedule change for next renewal (no immediate charge/credit)
            # Use proration_behavior: "none" to prevent immediate proration
            # This keeps current period at old price, new price takes effect at renewal
            update_items = [
              %{id: stripe_item_id, price: new_price_id, quantity: 1}
            ]

            case Stripe.Subscription.update(subscription.stripe_id, %{
                   items: update_items,
                   proration_behavior: "none",
                   billing_cycle_anchor: "unchanged"
                 }) do
              {:ok, stripe_subscription} ->
                # Subscription is updated but current period remains unchanged
                # New price will apply at next renewal
                update_subscription(subscription, %{
                  stripe_status: stripe_subscription.status,
                  current_period_start:
                    stripe_subscription.current_period_start &&
                      DateTime.from_unix!(
                        stripe_subscription.current_period_start
                      ),
                  current_period_end:
                    stripe_subscription.current_period_end &&
                      DateTime.from_unix!(
                        stripe_subscription.current_period_end
                      )
                })

              {:error, error} ->
                {:error, error}
            end
        end
      end
    else
      {:error, error} -> {:error, error}
      _ -> {:error, :invalid_subscription_items}
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

  ## Examples

      iex> create_stripe_subscription(user, %{prices: [%{price: "price_123", quantity: 1}]})
      {:ok, %Stripe.Subscription{}}

  """
  def create_stripe_subscription(user, params) do
    # Handle both keyword lists and maps
    prices = params[:prices] || params["prices"] || params.prices
    expand = params[:expand] || params["expand"] || []

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

    Stripe.Subscription.create(stripe_params)
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
    require Logger

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

  defp ensure_user_has_stripe_id(%{stripe_id: nil} = user) do
    case Ysc.Customers.create_stripe_customer(user) do
      {:ok, _} -> Ysc.Accounts.get_user!(user.id)
      {:error, _} -> user
    end
  end

  defp ensure_user_has_stripe_id(user), do: user

  defp do_create_subscription_paid_out_of_band(user, plan) do
    require Logger

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

                {:ok, subscription}

              err ->
                err
            end

          {:error, _} = err ->
            err
        end
    end
  end

  defp do_create_subscription_paid_out_of_band_stripe(user, plan) do
    require Logger

    stripe_params = %{
      customer: user.stripe_id,
      items: [%{price: plan.stripe_price_id, quantity: 1}],
      payment_behavior: "default_incomplete",
      expand: ["latest_invoice"],
      metadata: %{user_id: user.id}
    }

    case Stripe.Subscription.create(stripe_params) do
      {:ok, stripe_subscription} ->
        latest_invoice = stripe_subscription.latest_invoice
        invoice_id = invoice_id_from_expand(latest_invoice)

        case Stripe.Invoice.pay(invoice_id, %{paid_out_of_band: true}) do
          {:ok, _paid_invoice} ->
            stripe_subscription =
              case Stripe.Subscription.retrieve(stripe_subscription.id,
                     expand: ["items.data.price"]
                   ) do
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

                {:ok, subscription}

              err ->
                Logger.error(
                  "Failed to create local subscription after paid-out-of-band",
                  user_id: user.id,
                  stripe_subscription_id: stripe_subscription.id,
                  error: inspect(err)
                )

                err
            end

          {:error, err} ->
            Logger.error("Failed to mark invoice as paid out of band",
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

  defp send_membership_confirmation_email_for_paid_elsewhere(user, plan) do
    require Logger

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
        Logger.warning(
          "Failed to send membership confirmation email for paid-elsewhere subscription",
          user_id: user.id,
          error: Exception.message(error)
        )
    end
  end

  @doc """
  Creates a local subscription from a Stripe subscription.
  This is used as a backup when webhooks might not be reliable.
  """
  def create_subscription_from_stripe(user, stripe_subscription) do
    require Logger

    # Check if subscription already exists
    existing = get_subscription_by_stripe_id(stripe_subscription.id)

    if existing do
      Logger.info("Subscription already exists locally",
        user_id: user.id,
        subscription_id: existing.id,
        stripe_subscription_id: stripe_subscription.id
      )

      {:ok, existing}
    else
      # Create the subscription
      subscription_changeset =
        user
        |> Ecto.build_assoc(:subscriptions)
        |> Subscription.changeset(%{
          user_id: user.id,
          # Default name for membership subscriptions
          name: "Membership Subscription",
          stripe_id: stripe_subscription.id,
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
                Logger.error("Failed to create subscription item",
                  user_id: user.id,
                  subscription_id: subscription.id,
                  error: reason
                )
            end
          end)

          Logger.info("Successfully created subscription from Stripe",
            user_id: user.id,
            subscription_id: subscription.id,
            stripe_subscription_id: stripe_subscription.id
          )

          # Invalidate membership cache when subscription is created
          MembershipCache.invalidate_user(user.id)

          {:ok, subscription}

        {:error, reason} ->
          Logger.error("Failed to create subscription from Stripe",
            user_id: user.id,
            stripe_subscription_id: stripe_subscription.id,
            error: reason
          )

          {:error, reason}
      end
    end
  end

  @doc """
  Retries payment for a failed invoice.

  Validates that the invoice belongs to the user and attempts to pay it via Stripe.

  ## Examples

      iex> retry_failed_invoice(user, "in_1234567890")
      {:ok, %Stripe.Invoice{}}

      iex> retry_failed_invoice(user, "invalid")
      {:error, :invoice_not_found}

  """
  def retry_failed_invoice(user, invoice_id) when is_binary(invoice_id) do
    require Logger

    # Retrieve the invoice from Stripe to verify it exists and belongs to the user
    case Stripe.Invoice.retrieve(invoice_id) do
      {:ok, invoice} ->
        # Verify the invoice belongs to the user
        customer_id = invoice.customer

        if customer_id != user.stripe_id do
          Logger.warning("Invoice does not belong to user",
            user_id: user.id,
            invoice_id: invoice_id,
            invoice_customer: customer_id,
            user_stripe_id: user.stripe_id
          )

          {:error, :unauthorized}
        else
          # Check if invoice is already paid
          if invoice.status == "paid" do
            Logger.info("Invoice is already paid",
              user_id: user.id,
              invoice_id: invoice_id
            )

            {:error, :already_paid}
          else
            # Check if invoice is open and can be paid
            if invoice.status != "open" do
              Logger.warning("Invoice is not in a payable state",
                user_id: user.id,
                invoice_id: invoice_id,
                invoice_status: invoice.status
              )

              {:error, :invalid_invoice_status}
            else
              # Attempt to pay the invoice
              Logger.info("Attempting to retry payment for invoice",
                user_id: user.id,
                invoice_id: invoice_id
              )

              case Stripe.Invoice.pay(invoice_id, %{}) do
                {:ok, paid_invoice} ->
                  Logger.info("Successfully retried payment for invoice",
                    user_id: user.id,
                    invoice_id: invoice_id,
                    invoice_status: paid_invoice.status
                  )

                  {:ok, paid_invoice}

                {:error, %Stripe.Error{} = error} ->
                  Logger.error("Failed to retry payment for invoice",
                    user_id: user.id,
                    invoice_id: invoice_id,
                    error: error.message
                  )

                  {:error, error.message}

                {:error, reason} ->
                  Logger.error("Failed to retry payment for invoice",
                    user_id: user.id,
                    invoice_id: invoice_id,
                    error: inspect(reason)
                  )

                  {:error, :payment_failed}
              end
            end
          end
        end

      {:error, %Stripe.Error{code: code}} when code in ["resource_missing"] ->
        Logger.warning("Invoice not found in Stripe",
          user_id: user.id,
          invoice_id: invoice_id
        )

        {:error, :invoice_not_found}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Failed to retrieve invoice from Stripe",
          user_id: user.id,
          invoice_id: invoice_id,
          error: error.message
        )

        {:error, error.message}

      {:error, reason} ->
        Logger.error("Failed to retrieve invoice from Stripe",
          user_id: user.id,
          invoice_id: invoice_id,
          error: inspect(reason)
        )

        {:error, :stripe_error}
    end
  end

  def retry_failed_invoice(_user, _invoice_id),
    do: {:error, :invalid_invoice_id}
end
