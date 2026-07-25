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

  @doc """
  Creates a Stripe customer for the given user.

  Includes billing address when present.

  ## Examples

      iex> create_stripe_customer(user)
      {:ok, %Stripe.Customer{}}

  """
  @dialyzer {:nowarn_function, create_stripe_customer: 1}
  def create_stripe_customer(%User{} = user) do
    user = Repo.preload(user, :billing_address)
    customer_params = stripe_customer_params(user, include_address: true)

    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           stripe_customer_module().create(customer_params)
         end) do
      {:ok, stripe_customer} ->
        persist_user_stripe_id(user.id, stripe_customer.id)
        {:ok, stripe_customer}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Ensures the user has a Stripe customer ID, creating one if needed.

  Returns the user (reloaded when a customer was created). On Stripe failure,
  returns the original user unchanged.
  """
  @dialyzer {:nowarn_function, ensure_stripe_customer: 1}
  def ensure_stripe_customer(%User{stripe_id: nil} = user) do
    case create_stripe_customer(user) do
      {:ok, _stripe_customer} ->
        Ysc.Accounts.get_user!(user.id)

      {:error, _error} ->
        user
    end
  end

  def ensure_stripe_customer(%User{} = user), do: user

  @doc """
  Builds Stripe Payment Element `defaultValues.billingDetails` from a user.

  Prefills email, name, phone, and billing address when present. Blank fields
  are omitted. Returns a map with string keys suitable for Jason encoding into
  a `data-billing-details` HTML attribute.
  """
  def payment_element_default_values(%User{} = user) do
    user = Repo.preload(user, :billing_address)

    %{}
    |> maybe_put_billing_detail("email", user.email)
    |> maybe_put_billing_detail("name", customer_display_name(user))
    |> maybe_put_billing_detail("phone", user.phone_number)
    |> maybe_put_billing_address(user.billing_address)
  end

  @doc """
  JSON-encoded billing details for the Payment Element `data-billing-details` attr.
  """
  def payment_element_default_values_json(%User{} = user) do
    Jason.encode!(payment_element_default_values(user))
  end

  def payment_element_default_values_json(nil), do: "{}"

  @doc """
  Attaches Stripe `customer` and `receipt_email` to PaymentIntent params when available.

  Ensures a Stripe customer exists first. Returns `{params, user}` with the
  (possibly updated) user.
  """
  def attach_customer_to_payment_intent_params(params, %User{} = user)
      when is_map(params) do
    user = ensure_stripe_customer(user)

    params =
      if present_string?(user.stripe_id) do
        Map.put(params, :customer, user.stripe_id)
      else
        params
      end

    params =
      if present_string?(user.email) do
        Map.put(params, :receipt_email, user.email)
      else
        params
      end

    {params, user}
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

  defp build_stripe_customer_params(%User{} = user) do
    %{
      email: user.email,
      name: customer_display_name(user),
      phone: user.phone_number,
      description: "User ID: #{user.id}",
      metadata: %{
        user_id: user.id
      }
    }
  end

  defp customer_display_name(%User{} = user) do
    [user.first_name, user.last_name]
    |> Enum.map(&Ysc.title_case/1)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
  end

  defp maybe_put_stripe_customer_address(params, %User{} = user, opts) do
    if Keyword.get(opts, :include_address, false) do
      maybe_put_stripe_customer_address(params, user.billing_address)
    else
      params
    end
  end

  defp maybe_put_stripe_customer_address(params, nil), do: params

  defp maybe_put_stripe_customer_address(params, %Ecto.Association.NotLoaded{}),
    do: params

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

  defp maybe_put_billing_detail(details, _key, value)
       when is_nil(value) or value == "",
       do: details

  defp maybe_put_billing_detail(details, key, value) when is_binary(value) do
    Map.put(details, key, value)
  end

  defp maybe_put_billing_address(details, nil), do: details

  defp maybe_put_billing_address(details, %Ecto.Association.NotLoaded{}),
    do: details

  defp maybe_put_billing_address(details, billing_address) do
    address =
      %{}
      |> maybe_put_billing_detail("line1", billing_address.address)
      |> maybe_put_billing_detail("city", billing_address.city)
      |> maybe_put_billing_detail("state", billing_address.region)
      |> maybe_put_billing_detail("postal_code", billing_address.postal_code)
      |> maybe_put_billing_detail("country", billing_address.country)

    if address == %{} do
      details
    else
      Map.put(details, "address", address)
    end
  end

  defp present_string?(value) when is_binary(value), do: value != ""
  defp present_string?(_), do: false
end
