defmodule Ysc.Customers do
  @moduledoc """
  The Customers context for managing customer operations with Stripe.
  """

  require Ysc.Logging

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Accounts.User
  alias Ysc.Subscriptions
  alias Ysc.Payments

  @doc """
  Creates a Stripe customer for the given user.

  ## Examples

      iex> create_stripe_customer(user)
      {:ok, %Stripe.Customer{}}

  """
  @doc """
  Builds parameters for the Stripe Customer create/update APIs from a user.

  ## Options

    * `:include_address` - when `true`, includes billing address when present
      (default `false`)
  """
  def stripe_customer_params(%User{} = user, opts \\ []) do
    user
    |> build_stripe_customer_params()
    |> maybe_put_stripe_customer_address(user, opts)
  end

  @dialyzer {:nowarn_function, create_stripe_customer: 1}
  def create_stripe_customer(%User{} = user) do
    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           user
           |> stripe_customer_params()
           |> then(&stripe_customer_module().create/1)
         end) do
      {:ok, stripe_customer} ->
        persist_user_stripe_id(user.id, stripe_customer.id)
        {:ok, stripe_customer}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Updates a Stripe customer with the latest user information.

  ## Examples

      iex> update_stripe_customer(user)
      {:ok, %Stripe.Customer{}}

      iex> update_stripe_customer(user_without_stripe_id)
      {:error, :no_stripe_customer}

  """
  @dialyzer {:nowarn_function, update_stripe_customer: 1}
  def update_stripe_customer(%User{} = user) do
    if user.stripe_id do
      # Preload billing_address to ensure it's available for customer update
      user = Repo.preload(user, :billing_address)

      customer_params = stripe_customer_params(user, include_address: true)

      case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             stripe_customer_module().update(
               user.stripe_id,
               customer_params,
               []
             )
           end) do
        {:ok, stripe_customer} ->
          {:ok, stripe_customer}

        {:error, error} ->
          Ysc.Logging.error("Failed to update Stripe customer",
            user_id: user.id,
            stripe_customer_id: user.stripe_id,
            error: inspect(error)
          )

          {:error, error}
      end
    else
      {:error, :no_stripe_customer}
    end
  end

  @doc """
  Gets a customer by Stripe ID.

  ## Examples

      iex> customer_from_stripe_id("cus_123")
      %User{}

      iex> customer_from_stripe_id("invalid")
      nil

  """
  def customer_from_stripe_id(stripe_id) do
    Repo.get_by(User, stripe_id: stripe_id)
  end

  @doc """
  Gets all subscriptions for a user.

  ## Examples

      iex> subscriptions(user)
      [%Subscription{}, ...]

  """
  def subscriptions(%User{} = user) do
    Subscriptions.list_subscriptions(user)
  end

  @doc """
  Checks if a user is subscribed to a specific price.

  ## Examples

      iex> subscribed_to_price?(user, "price_123")
      true

      iex> subscribed_to_price?(user, "price_456")
      false

  """
  def subscribed_to_price?(%User{} = user, price_id) do
    user
    |> subscriptions()
    |> Enum.any?(fn subscription ->
      Subscriptions.active?(subscription) and
        subscription_items_contain_price?(subscription, price_id)
    end)
  end

  defp subscription_items_contain_price?(subscription, price_id) do
    subscription_items =
      case subscription.subscription_items do
        %Ecto.Association.NotLoaded{} ->
          # Preload subscription items if not loaded
          subscription = Ysc.Repo.preload(subscription, :subscription_items)
          subscription.subscription_items

        items when is_list(items) ->
          items

        _ ->
          []
      end

    Enum.any?(subscription_items, fn item ->
      item.stripe_price_id == price_id
    end)
  end

  @doc """
  Creates a subscription for a user.

  ## Examples

      iex> create_subscription(user, return_url: "...", prices: [%{price: "price_123", quantity: 1}])
      {:ok, %Stripe.Subscription{}}

  """
  @dialyzer {:nowarn_function, create_subscription: 2}
  def create_subscription(%User{} = user, params) do
    # Prevent sub-accounts from creating subscriptions
    if Ysc.Accounts.sub_account?(user) do
      {:error, :sub_accounts_cannot_create_subscriptions}
    else
      # Ensure user has a Stripe ID
      user = ensure_stripe_customer(user)

      # Convert keyword list to map if needed
      params_map =
        if is_list(params) do
          Enum.into(params, %{})
        else
          params
        end

      case Subscriptions.create_stripe_subscription(user, params_map) do
        {:ok, stripe_subscription} ->
          {:ok, stripe_subscription}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Gets the default payment method for a user.

  ## Examples

      iex> default_payment_method(user)
      %Stripe.PaymentMethod{}

      iex> default_payment_method(user)
      nil

  """
  def default_payment_method(%User{} = user) do
    case Payments.get_default_payment_method(user) do
      nil ->
        nil

      payment_method ->
        case stripe_payment_method_module().retrieve(payment_method.provider_id) do
          {:ok, stripe_payment_method} -> stripe_payment_method
          {:error, _} -> nil
        end
    end
  end

  @doc """
  Gets all payment methods for a user from Stripe.

  ## Examples

      iex> payment_methods(user)
      [%Stripe.PaymentMethod{}, ...]

  """
  def payment_methods(%User{} = user) do
    case stripe_payment_method_module().list(%{
           customer: user.stripe_id,
           type: "card"
         }) do
      {:ok, %{data: payment_methods}} -> payment_methods
      {:error, _} -> []
    end
  end

  @doc """
  Creates a setup intent for a user.

  ## Examples

      iex> create_setup_intent(user, return_url: "...")
      {:ok, %Stripe.SetupIntent{}}

  """
  def create_setup_intent(%User{} = user, params \\ %{}) do
    # Ensure user has a Stripe ID
    user = ensure_stripe_customer(user)

    setup_intent_params = %{
      customer: user.stripe_id,
      payment_method_types: ["card", "us_bank_account", "link"],
      usage: "off_session"
    }

    # Handle stripe-specific parameters
    setup_intent_params =
      if params[:stripe] && params[:stripe][:payment_method_types] do
        Map.put(
          setup_intent_params,
          :payment_method_types,
          params[:stripe][:payment_method_types]
        )
      else
        setup_intent_params
      end

    setup_intent_params =
      if params[:return_url] do
        Map.put(setup_intent_params, :return_url, params.return_url)
      else
        setup_intent_params
      end

    Ysc.Stripe.RetryHelper.stripe_retry(fn ->
      stripe_setup_intent_module().create(setup_intent_params)
    end)
  end

  @doc """
  Gets invoices for a user.

  ## Examples

      iex> invoices(user)
      [%Stripe.Invoice{}, ...]

  """
  def invoices(%User{} = user) do
    case stripe_invoice_module().list(%{customer: user.stripe_id}) do
      {:ok, %{data: invoices}} -> invoices
      {:error, _} -> []
    end
  end

  # Helper functions

  defp persist_user_stripe_id(user_id, stripe_customer_id, retried? \\ false) do
    user = Repo.get!(User, user_id)

    changeset =
      User.update_user_changeset(user, %{stripe_id: stripe_customer_id})

    try do
      case Repo.update(changeset) do
        {:ok, _updated_user} ->
          :ok

        {:error, changeset} ->
          log_stripe_id_update_failure(user_id, stripe_customer_id, changeset)
          :ok
      end
    rescue
      e in Ecto.StaleEntryError ->
        if retried? do
          reraise e, __STACKTRACE__
        else
          Ysc.Logging.warning(
            "Stale user entry when updating stripe_id, retrying",
            user_id: user_id,
            stripe_customer_id: stripe_customer_id
          )

          persist_user_stripe_id(user_id, stripe_customer_id, true)
        end
    end
  end

  defp log_stripe_id_update_failure(user_id, stripe_customer_id, changeset) do
    Ysc.Logging.error("Failed to update user with stripe_id",
      user_id: user_id,
      stripe_customer_id: stripe_customer_id,
      changeset_errors: inspect(changeset.errors)
    )
  end

  defp stripe_customer_module do
    Application.get_env(:ysc, :stripe_customer_module, Stripe.Customer)
  end

  defp stripe_payment_method_module do
    Application.get_env(
      :ysc,
      :stripe_payment_method_module,
      Stripe.PaymentMethod
    )
  end

  defp stripe_setup_intent_module do
    Application.get_env(
      :ysc,
      :stripe_setup_intent_module,
      Stripe.SetupIntent
    )
  end

  defp stripe_invoice_module do
    Application.get_env(:ysc, :stripe_invoice_module, Stripe.Invoice)
  end

  @dialyzer {:nowarn_function, ensure_stripe_customer: 1}
  defp ensure_stripe_customer(%User{stripe_id: nil} = user) do
    case create_stripe_customer(user) do
      {:ok, _stripe_customer} ->
        # Reload user to get updated stripe_id
        Ysc.Accounts.get_user!(user.id)

      {:error, _error} ->
        user
    end
  end

  defp ensure_stripe_customer(%User{} = user), do: user

  defp build_stripe_customer_params(%User{} = user) do
    %{
      email: user.email,
      name:
        "#{Ysc.title_case(user.first_name)} #{Ysc.title_case(user.last_name)}",
      phone: user.phone_number,
      description: "User ID: #{user.id}",
      metadata: %{
        user_id: user.id
      }
    }
  end

  defp maybe_put_stripe_customer_address(params, %User{} = user, opts) do
    if Keyword.get(opts, :include_address, false) do
      maybe_put_stripe_customer_address(params, user.billing_address)
    else
      params
    end
  end

  defp maybe_put_stripe_customer_address(params, nil), do: params

  defp maybe_put_stripe_customer_address(params, billing_address) do
    Map.put(params, :address, build_customer_address(billing_address))
  end

  defp build_customer_address(billing_address) do
    address = %{
      line1: billing_address.address,
      city: billing_address.city,
      postal_code: billing_address.postal_code,
      country: billing_address.country
    }

    # Add state/region if available
    if billing_address.region && billing_address.region != "" do
      Map.put(address, :state, billing_address.region)
    else
      address
    end
  end
end
