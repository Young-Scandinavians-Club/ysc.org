defmodule Ysc.Payments do
  @moduledoc """
  The Payments context for managing payment methods and related operations.
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Payments.PaymentMethod

  @doc """
  Returns the list of payment methods for a user.
  """
  def list_payment_methods(user) do
    Repo.all(from pm in PaymentMethod, where: pm.user_id == ^user.id)
  end

  @doc """
  Gets a single payment method by provider and provider_id.
  """
  def get_payment_method_by_provider(provider, provider_id) do
    Repo.get_by(PaymentMethod, provider: provider, provider_id: provider_id)
  end

  defp get_payment_method_by_provider_for_user(user, provider, provider_id) do
    Repo.get_by(PaymentMethod,
      provider: provider,
      provider_id: provider_id,
      user_id: user.id
    )
  end

  defp payment_method_provider_conflict?(user, provider, provider_id) do
    case get_payment_method_by_provider(provider, provider_id) do
      nil -> false
      %PaymentMethod{user_id: id} -> id != user.id
    end
  end

  @doc """
  Gets a single payment method by id.
  """
  def get_payment_method!(id), do: Repo.get!(PaymentMethod, id)

  @doc """
  Gets the default payment method for a user.
  """
  def get_default_payment_method(user) do
    from(pm in PaymentMethod,
      where: pm.user_id == ^user.id and pm.is_default == true
    )
    |> Repo.one()
  end

  @doc """
  Creates a payment method with deduplication logic.
  """
  def insert_payment_method(attrs \\ %{}) do
    %PaymentMethod{}
    |> PaymentMethod.changeset(attrs)
    |> Repo.insert()
    |> handle_duplicate_payment_method()
  end

  @doc """
  Updates a payment method.
  """
  def update_payment_method(%PaymentMethod{} = payment_method, attrs) do
    payment_method
    |> PaymentMethod.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a payment method.
  If the deleted payment method was the default, automatically sets a new default from remaining payment methods.
  """
  def delete_payment_method(%PaymentMethod{} = payment_method) do
    user = Ysc.Accounts.get_user!(payment_method.user_id)
    was_default = payment_method.is_default

    case Repo.delete(payment_method) do
      {:ok, deleted_payment_method} ->
        # If the deleted payment method was the default, set a new default
        if was_default do
          remaining_payment_methods = list_payment_methods(user)

          if remaining_payment_methods != [] do
            # Set the oldest remaining payment method as default
            new_default =
              Enum.min_by(remaining_payment_methods, & &1.inserted_at)

            set_default_payment_method(user, new_default)
          end
        end

        {:ok, deleted_payment_method}

      error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking payment method changes.
  """
  def change_payment_method(%PaymentMethod{} = payment_method, attrs \\ %{}) do
    PaymentMethod.changeset(payment_method, attrs)
  end

  @doc """
  Handles deduplication of payment methods by provider and provider_id.
  If a payment method with the same provider and provider_id already exists,
  it updates the existing one instead of creating a duplicate.
  """
  def deduplicate_payment_methods(user) do
    payment_methods = list_payment_methods(user)

    # Group by provider and provider_id to find duplicates
    grouped = Enum.group_by(payment_methods, &{&1.provider, &1.provider_id})

    # Keep only the most recent payment method for each provider/provider_id combination
    {to_keep, to_delete} =
      grouped
      |> Enum.reduce({[], []}, fn {_key, methods}, {keep, delete} ->
        if length(methods) > 1 do
          # Sort by inserted_at desc and keep the first (most recent)
          sorted_methods =
            Enum.sort_by(methods, & &1.inserted_at, {:desc, DateTime})

          [most_recent | duplicates] = sorted_methods
          {[most_recent | keep], duplicates ++ delete}
        else
          {methods ++ keep, delete}
        end
      end)

    # Delete duplicate payment methods
    Enum.each(to_delete, &delete_payment_method/1)

    {:ok, to_keep}
  end

  @doc """
  Sets a payment method as the default for a user if they don't already have one.
  """
  def set_default_payment_method_if_none(user, payment_method) do
    # Check if user already has a default payment method
    existing_default =
      from(pm in PaymentMethod,
        where: pm.user_id == ^user.id and pm.is_default == true
      )
      |> Repo.one()

    if is_nil(existing_default) do
      set_default_payment_method(user, payment_method)
    else
      {:ok, user}
    end
  end

  @doc """
  Creates or updates a payment method from Stripe data and sets it as the default.
  This is useful when a user is updating their payment method.
  """
  def upsert_and_set_default_payment_method_from_stripe(
        user,
        stripe_payment_method
      ) do
    case upsert_payment_method_from_stripe(user, stripe_payment_method) do
      {:ok, payment_method} ->
        # Always set this payment method as default (replacing any existing default)
        set_default_payment_method(user, payment_method)

      error ->
        error
    end
  end

  @doc """
  Sets a payment method as the default for a user.
  This will unset any existing default payment method and set the new one.
  """
  def set_default_payment_method(user, payment_method) do
    require Ysc.Logging

    Ysc.Logging.info("Starting set_default_payment_method transaction",
      user_id: user.id,
      payment_method_id: payment_method.id,
      current_is_default: payment_method.is_default
    )

    case Repo.transaction(fn ->
           # First, unset any existing default payment methods for this user
           unset_result =
             from(pm in PaymentMethod,
               where: pm.user_id == ^user.id and pm.is_default == true
             )
             |> Repo.update_all(set: [is_default: false])

           Ysc.Logging.info("Unset existing default payment methods",
             user_id: user.id,
             unset_count: elem(unset_result, 0)
           )

           # Use update_all to unconditionally set is_default = true in the DB.
           # A changeset-based update would be a no-op when the in-memory struct
           # already has is_default: true (Ecto detects "no change"), but the DB
           # record was just unset in the step above, so we must force the SQL.
           {1, [updated_payment_method]} =
             from(pm in PaymentMethod,
               where: pm.id == ^payment_method.id,
               select: pm
             )
             |> Repo.update_all(set: [is_default: true])

           Ysc.Logging.info("Set new default payment method",
             user_id: user.id,
             payment_method_id: updated_payment_method.id,
             is_default: updated_payment_method.is_default
           )

           updated_payment_method
         end) do
      {:ok, updated_payment_method} ->
        Ysc.Logging.info(
          "Successfully completed set_default_payment_method transaction",
          user_id: user.id,
          payment_method_id: updated_payment_method.id
        )

        {:ok, user}

      {:error, reason} ->
        Ysc.Logging.error("Failed set_default_payment_method transaction",
          user_id: user.id,
          payment_method_id: payment_method.id,
          error: reason
        )

        {:error, reason}
    end
  end

  @doc """
  Manually syncs payment methods with Stripe for a user.
  This can be called to ensure the local database is in sync with Stripe.
  """
  def sync_payment_methods_with_stripe(user) do
    require Ysc.Logging

    # Get all payment methods from Stripe
    stripe_payment_methods =
      case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             stripe_payment_method_module().list(%{
               customer: user.stripe_id,
               type: "card"
             })
           end) do
        {:ok, %{data: payment_methods}} ->
          payment_methods

        {:error, error} ->
          Ysc.Logging.error("Failed to fetch payment methods from Stripe",
            user_id: user.id,
            error: error.message
          )

          []
      end

    # Get current local payment methods
    local_payment_methods = list_payment_methods(user)

    # Sync each Stripe payment method
    Enum.each(stripe_payment_methods, fn stripe_pm ->
      sync_payment_method_from_stripe(user, stripe_pm)
    end)

    # Get the default payment method from Stripe customer
    stripe_default_pm =
      case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             stripe_customer_module().retrieve(user.stripe_id, [])
           end) do
        {:ok, customer} ->
          if customer.invoice_settings &&
               customer.invoice_settings.default_payment_method do
            customer.invoice_settings.default_payment_method
          else
            nil
          end

        {:error, _} ->
          nil
      end

    # Set the correct default payment method
    if stripe_default_pm do
      case get_payment_method_by_provider(:stripe, stripe_default_pm) do
        nil ->
          Ysc.Logging.warning(
            "Stripe default payment method not found in local database",
            user_id: user.id,
            stripe_payment_method_id: stripe_default_pm
          )

        local_pm ->
          set_default_payment_method(user, local_pm)
      end
    end

    Ysc.Logging.info("Synced payment methods with Stripe",
      user_id: user.id,
      stripe_payment_methods_count: length(stripe_payment_methods),
      local_payment_methods_count: length(local_payment_methods)
    )

    {:ok, list_payment_methods(user)}
  end

  @doc """
  Fixes users who have payment methods but no default payment method set.
  This is a utility function to fix existing data.
  """
  def fix_missing_default_payment_methods do
    # Find all users who have payment methods but no default payment method
    users_without_default =
      from(u in Ysc.Accounts.User,
        join: pm in PaymentMethod,
        on: pm.user_id == u.id,
        left_join: default_pm in PaymentMethod,
        on: default_pm.user_id == u.id and default_pm.is_default == true,
        where: is_nil(default_pm.id),
        distinct: true,
        select: u
      )
      |> Repo.all()

    results =
      Enum.map(users_without_default, fn user ->
        payment_methods = list_payment_methods(user)

        if payment_methods != [] do
          # Set the first (oldest) payment method as default
          first_payment_method = Enum.min_by(payment_methods, & &1.inserted_at)
          set_default_payment_method(user, first_payment_method)
        else
          {:ok, user}
        end
      end)

    successful_fixes = Enum.count(results, fn {status, _} -> status == :ok end)
    total_users = length(users_without_default)

    {:ok, %{fixed_users: successful_fixes, total_users: total_users}}
  end

  @doc """
  Creates or updates a payment method from Stripe data without changing default status.
  This is used by webhooks to sync payment method data.
  """
  def sync_payment_method_from_stripe(user, stripe_payment_method) do
    persist_payment_method_from_stripe(user, stripe_payment_method, :sync)
  end

  @doc """
  Creates or updates a payment method from Stripe data.
  """
  def upsert_payment_method_from_stripe(user, stripe_payment_method) do
    case persist_payment_method_from_stripe(
           user,
           stripe_payment_method,
           :upsert
         ) do
      {:ok, payment_method} = result ->
        set_default_payment_method_if_none(user, payment_method)
        result

      error ->
        error
    end
  end

  # Private functions

  # Persists a Stripe payment method. Handles races where a webhook and LiveView
  # both try to insert the same provider_id by recovering from unique violations.
  defp persist_payment_method_from_stripe(user, stripe_payment_method, mode) do
    attrs = build_stripe_payment_method_attrs(user, stripe_payment_method)
    provider_id = stripe_payment_method.id

    case get_payment_method_by_provider_for_user(user, :stripe, provider_id) do
      nil ->
        if payment_method_provider_conflict?(user, :stripe, provider_id) do
          {:error, :payment_method_owned_by_another_user}
        else
          insert_payment_method_resilient(user, attrs, mode)
          |> maybe_set_default_after_sync_insert(user, mode)
        end

      existing_payment_method ->
        update_payment_method_from_stripe(existing_payment_method, attrs, mode)
    end
  end

  defp build_stripe_payment_method_attrs(user, stripe_payment_method) do
    %{
      provider: :stripe,
      provider_id: stripe_payment_method.id,
      provider_customer_id: stripe_payment_method.customer,
      type: map_stripe_type_to_payment_method_type(stripe_payment_method),
      provider_type: stripe_payment_method.type,
      last_four: get_last_four(stripe_payment_method),
      display_brand: get_display_brand(stripe_payment_method),
      exp_month:
        stripe_payment_method.card && stripe_payment_method.card.exp_month,
      exp_year:
        stripe_payment_method.card && stripe_payment_method.card.exp_year,
      account_type:
        stripe_payment_method.us_bank_account &&
          stripe_payment_method.us_bank_account.account_type,
      routing_number:
        stripe_payment_method.us_bank_account &&
          stripe_payment_method.us_bank_account.routing_number,
      bank_name:
        stripe_payment_method.us_bank_account &&
          stripe_payment_method.us_bank_account.bank_name,
      user_id: user.id,
      payload: stripe_payment_method_to_map(stripe_payment_method)
    }
  end

  defp insert_payment_method_resilient(user, attrs, mode) do
    case insert_payment_method(attrs) do
      {:ok, _} = ok ->
        ok

      {:error, reason} = error ->
        if duplicate_payment_method_error?(reason) do
          recover_payment_method_insert_conflict(user, attrs, mode)
        else
          error
        end
    end
  end

  defp recover_payment_method_insert_conflict(user, attrs, mode) do
    provider = attrs.provider
    provider_id = attrs.provider_id

    case get_payment_method_by_provider_for_user(user, provider, provider_id) do
      %PaymentMethod{} = existing ->
        update_payment_method_from_stripe(existing, attrs, mode)

      nil ->
        if payment_method_provider_conflict?(user, provider, provider_id) do
          {:error, :payment_method_owned_by_another_user}
        else
          {:error, :duplicate_payment_method}
        end
    end
  end

  defp update_payment_method_from_stripe(existing_payment_method, attrs, :sync) do
    # Do not pass is_default so we never overwrite it. Default is owned by
    # user actions (e.g. add payment method, select default); webhooks only
    # sync metadata. This avoids a race where payment_method.attached runs
    # after the LiveView set the new PM as default but still had a stale
    # read of is_default: false, which would overwrite the default.
    update_payment_method(existing_payment_method, attrs)
  end

  defp update_payment_method_from_stripe(
         existing_payment_method,
         attrs,
         :upsert
       ) do
    attrs_with_default =
      Map.put(attrs, :is_default, existing_payment_method.is_default)

    update_payment_method(existing_payment_method, attrs_with_default)
  end

  defp maybe_set_default_after_sync_insert({:ok, payment_method}, user, :sync) do
    set_default_payment_method_if_none(user, payment_method)
    {:ok, payment_method}
  end

  defp maybe_set_default_after_sync_insert(result, _user, _mode), do: result

  defp duplicate_payment_method_error?(:duplicate_payment_method), do: true

  defp duplicate_payment_method_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:provider_id, {"has already been taken", _}} -> true
      {:provider, {"has already been taken", _}} -> true
      _ -> false
    end)
  end

  defp duplicate_payment_method_error?(_), do: false

  defp handle_duplicate_payment_method({:error, %Ecto.Changeset{} = changeset}) do
    if duplicate_payment_method_error?(changeset) do
      {:error, :duplicate_payment_method}
    else
      {:error, changeset}
    end
  end

  defp handle_duplicate_payment_method(result), do: result

  # Map Stripe payment method to our internal type, detecting wallet types like Link
  defp map_stripe_type_to_payment_method_type(stripe_payment_method) do
    case stripe_payment_method.type do
      "card" ->
        card = stripe_payment_method.card

        wallet =
          card &&
            (Map.get(card, :wallet) || Map.get(card, "wallet"))

        wtype =
          wallet && (Map.get(wallet, :type) || Map.get(wallet, "type"))

        cond do
          wtype == "link" ->
            :link

          not is_nil(wtype) ->
            :card

          card &&
              (Map.get(card, :brand) == "link" ||
                 Map.get(card, "brand") == "link") ->
            :link

          true ->
            :card
        end

      "us_bank_account" ->
        :bank_account

      "sepa_debit" ->
        :sepa_debit

      "link" ->
        :link

      "paypal" ->
        :paypal

      "affirm" ->
        :affirm

      "klarna" ->
        :klarna

      "cashapp" ->
        :cashapp

      # Return :other for unknown payment types to prevent atom exhaustion
      _unknown ->
        :other
    end
  end

  # Extract last four digits from various payment method types
  defp get_last_four(%{card: %{wallet: %{dynamic_last4: dynamic_last4}}})
       when not is_nil(dynamic_last4),
       do: dynamic_last4

  defp get_last_four(%{card: %{last4: last4}}), do: last4
  defp get_last_four(%{us_bank_account: %{last4: last4}}), do: last4
  defp get_last_four(%{link: %{last4: last4}}), do: last4
  defp get_last_four(%{cashapp: %{last4: last4}}), do: last4
  defp get_last_four(_), do: nil

  # Extract display brand from various payment method types
  defp get_display_brand(%{card: %{wallet: %{type: wallet_type}} = card})
       when not is_nil(wallet_type) do
    case wallet_type do
      "link" -> Map.get(card, :display_brand) || Map.get(card, :brand)
      "apple_pay" -> "Apple Pay"
      "google_pay" -> "Google Pay"
      "samsung_pay" -> "Samsung Pay"
      _ -> Map.get(card, :display_brand) || Map.get(card, :brand)
    end
  end

  defp get_display_brand(%{card: %{brand: "link"}}), do: "Link"
  defp get_display_brand(%{card: %{display_brand: brand}}), do: brand
  defp get_display_brand(%{card: %{brand: brand}}), do: brand

  defp get_display_brand(%{us_bank_account: %{bank_name: bank_name}}),
    do: bank_name

  defp get_display_brand(%{link: link}) when not is_nil(link), do: "Link"

  defp get_display_brand(%{cashapp: cashapp}) when not is_nil(cashapp),
    do: "Cash App"

  defp get_display_brand(%{paypal: paypal}) when not is_nil(paypal),
    do: "PayPal"

  defp get_display_brand(%{klarna: klarna}) when not is_nil(klarna),
    do: "Klarna"

  defp get_display_brand(%{affirm: affirm}) when not is_nil(affirm),
    do: "Affirm"

  defp get_display_brand(_), do: nil

  defp stripe_payment_method_to_map(stripe_payment_method) do
    # Convert Stripe struct to map for storage
    case stripe_payment_method do
      %{__struct__: _} = struct ->
        Map.from_struct(struct)
        |> Enum.map(fn {key, value} -> {key, convert_to_map(value)} end)
        |> Enum.into(%{})

      %{} = map ->
        # Already a map, just convert nested values
        Enum.map(map, fn {key, value} -> {key, convert_to_map(value)} end)
        |> Enum.into(%{})
    end
  end

  defp convert_to_map(%{__struct__: _module} = struct) do
    Map.from_struct(struct)
    |> Enum.map(fn {key, value} -> {key, convert_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp convert_to_map(%{} = map) do
    Enum.map(map, fn {key, value} -> {key, convert_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp convert_to_map(list) when is_list(list) do
    Enum.map(list, &convert_to_map/1)
  end

  defp convert_to_map(value), do: value

  defp stripe_payment_method_module do
    Application.get_env(
      :ysc,
      :stripe_payment_method_module,
      Stripe.PaymentMethod
    )
  end

  defp stripe_customer_module do
    Application.get_env(:ysc, :stripe_customer_module, Stripe.Customer)
  end
end
