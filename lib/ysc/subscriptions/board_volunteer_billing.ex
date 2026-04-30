defmodule Ysc.Subscriptions.BoardVolunteerBilling do
  @moduledoc false

  import Ecto.Query

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Accounts.User
  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription

  @doc """
  Syncs Stripe `pause_collection` for the primary account holder's membership
  subscription(s) based on whether anyone in the user's family group holds a
  board position.

  - While volunteering: `pause_collection` with `behavior: "void"` and no `resumes_at`.
  - When the last volunteer leaves: same pause with `resumes_at` six calendar months ahead.
  - No-op in test environment (no Stripe calls).
  """
  def sync_for_user(%User{} = user) do
    if Ysc.Env.test?() do
      :ok
    else
      do_sync(user)
    end
  end

  @doc false
  def grace_resume_at_unix_from(%DateTime{} = utc_now) do
    utc_now
    |> Timex.shift(months: 6)
    |> DateTime.truncate(:second)
    |> DateTime.to_unix()
  end

  @doc false
  def membership_subscription_for_pause?(%Subscription{} = subscription) do
    real_stripe_subscription?(subscription) and
      subscription.stripe_status in ["active", "trialing"] and
      subscription_items_match_membership_plans?(subscription)
  end

  defp do_sync(%User{} = user) do
    [primary | _] = Accounts.get_family_group(user)

    if is_nil(primary.stripe_id) or primary.stripe_id == "" do
      :ok
    else
      household_on_board? = any_family_board_member?(user)
      subs = list_membership_subscriptions_for_pause(primary)

      params =
        if household_on_board? do
          %{pause_collection: %{behavior: "void"}}
        else
          unix = grace_resume_at_unix_from(DateTime.utc_now())

          %{pause_collection: %{behavior: "void", resumes_at: unix}}
        end

      Enum.each(subs, fn sub ->
        case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
               Stripe.Subscription.update(sub.stripe_id, params)
             end) do
          {:ok, _} ->
            :ok

          {:error, error} ->
            Ysc.Logging.error(
              "Board volunteer Stripe pause_collection sync failed",
              user_id: user.id,
              primary_user_id: primary.id,
              subscription_stripe_id: sub.stripe_id,
              household_on_board: household_on_board?,
              error: inspect(error)
            )
        end
      end)

      :ok
    end
  end

  defp any_family_board_member?(%User{} = user) do
    family_ids = Accounts.get_family_group_user_ids(user)

    Repo.exists?(
      from u in User,
        where: u.id in ^family_ids,
        where: not is_nil(u.board_position)
    )
  end

  defp list_membership_subscriptions_for_pause(%User{} = primary) do
    Subscription
    |> where([s], s.user_id == ^primary.id)
    |> preload(:subscription_items)
    |> Repo.all()
    |> Enum.filter(&membership_subscription_for_pause?/1)
  end

  defp real_stripe_subscription?(%Subscription{} = sub) do
    is_binary(sub.stripe_id) and
      sub.stripe_id != "" and
      not String.starts_with?(sub.stripe_id, "migrated_")
  end

  defp subscription_items_match_membership_plans?(
         %Subscription{} = subscription
       ) do
    price_ids = membership_price_ids_set()

    Enum.any?(subscription.subscription_items, fn item ->
      MapSet.member?(price_ids, item.stripe_price_id)
    end)
  end

  defp membership_price_ids_set do
    Application.get_env(:ysc, :membership_plans, [])
    |> Enum.map(& &1.stripe_price_id)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end
end
