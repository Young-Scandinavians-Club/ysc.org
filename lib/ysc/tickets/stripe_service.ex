defmodule Ysc.Tickets.StripeService do
  @moduledoc """
  Service for handling Stripe payments for ticket orders.

  This module provides:
  - Creating payment intents for ticket orders
  - Processing successful payments
  - Handling payment failures and timeouts
  - Integration with the ledger system
  """

  alias Ysc.Tickets

  defp stripe_client do
    Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
  end

  @doc """
  Creates a Stripe payment intent for a ticket order.

  ## Parameters:
  - `ticket_order`: The ticket order to create payment for
  - `customer_id`: Stripe customer ID (optional)
  - `payment_method_id`: Stripe payment method ID (optional)

  ## Returns:
  - `{:ok, %Stripe.PaymentIntent{}}` on success
  - `{:error, reason}` on failure
  """
  def create_payment_intent(ticket_order, opts \\ []) do
    customer_id = Keyword.get(opts, :customer_id)
    payment_method_id = Keyword.get(opts, :payment_method_id)

    amount_cents = money_to_cents(ticket_order.total_amount)

    # Note: Stripe PaymentIntents don't support expires_at parameter.
    # The expires_at parameter is only available for Checkout Sessions, not PaymentIntents.
    # Since we're using PaymentIntents with Stripe Elements (embedded form), we handle
    # expiration server-side via TimeoutWorker that cancels expired orders and releases inventory.
    payment_intent_params = %{
      amount: amount_cents,
      currency: "usd",
      metadata: %{
        ticket_order_id: ticket_order.id,
        ticket_order_reference: ticket_order.reference_id,
        event_id: ticket_order.event_id,
        user_id: ticket_order.user_id
      },
      description: "Event tickets - Order #{ticket_order.reference_id}",
      automatic_payment_methods: %{
        enabled: true
      }
    }

    # Add customer if provided
    payment_intent_params =
      if customer_id do
        Map.put(payment_intent_params, :customer, customer_id)
      else
        payment_intent_params
      end

    # Add payment method if provided
    payment_intent_params =
      if payment_method_id do
        Map.put(payment_intent_params, :payment_method, payment_method_id)
      else
        payment_intent_params
      end

    # Use ticket order reference ID as idempotency key to prevent duplicate charges
    # If the same reference is used again, Stripe will return the existing payment intent
    idempotency_key = "ticket_order_#{ticket_order.reference_id}"

    case stripe_client().create_payment_intent(payment_intent_params,
           headers: %{"Idempotency-Key" => idempotency_key}
         ) do
      {:ok, payment_intent} ->
        # Update the ticket order with the payment intent ID
        case Tickets.update_payment_intent(ticket_order, payment_intent.id) do
          {:ok, _updated_order} ->
            {:ok, payment_intent}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, %Stripe.Error{} = error} ->
        {:error, error.message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Processes a successful payment intent and completes the ticket order.

  ## Parameters:
  - `payment_intent_id`: The Stripe payment intent ID

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, reason}` on failure
  """
  def process_successful_payment(payment_intent_id) do
    with {:ok, payment_intent} <-
           stripe_client().retrieve_payment_intent(payment_intent_id, %{}),
         {:ok, ticket_order} <-
           get_ticket_order_from_payment_intent(payment_intent),
         :ok <- validate_payment_intent(payment_intent, ticket_order) do
      Tickets.process_ticket_order_payment(ticket_order, payment_intent_id)
    end
  end

  @doc """
  Handles a failed payment intent and cancels the ticket order.

  ## Parameters:
  - `payment_intent_id`: The Stripe payment intent ID
  - `failure_reason`: Reason for payment failure

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, reason}` on failure
  """
  def handle_failed_payment(
        payment_intent_id,
        failure_reason \\ "Payment failed"
      ) do
    with {:ok, payment_intent} <-
           stripe_client().retrieve_payment_intent(payment_intent_id, %{}),
         {:ok, ticket_order} <-
           get_ticket_order_from_payment_intent(payment_intent) do
      Tickets.cancel_ticket_order(ticket_order, failure_reason)
    end
  end

  @doc """
  Cancels a Stripe PaymentIntent.

  ## Parameters:
  - `payment_intent_id`: The Stripe payment intent ID to cancel

  ## Returns:
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def cancel_payment_intent(payment_intent_id)
      when is_binary(payment_intent_id) do
    require Logger

    case stripe_client().cancel_payment_intent(payment_intent_id, %{}) do
      {:ok, _payment_intent} ->
        Logger.info("Successfully canceled PaymentIntent",
          payment_intent_id: payment_intent_id
        )

        :ok

      {:error, %Stripe.Error{} = error} ->
        # PaymentIntent might already be canceled or succeeded - that's okay
        if String.contains?(error.message, "already") or
             String.contains?(error.message, "succeeded") do
          Logger.debug("PaymentIntent already canceled or succeeded",
            payment_intent_id: payment_intent_id,
            error: error.message
          )

          :ok
        else
          Logger.warning("Failed to cancel PaymentIntent",
            payment_intent_id: payment_intent_id,
            error: error.message
          )

          {:error, error.message}
        end

      {:error, reason} ->
        Logger.warning("Failed to cancel PaymentIntent",
          payment_intent_id: payment_intent_id,
          error: reason
        )

        {:error, reason}
    end
  end

  def cancel_payment_intent(nil), do: :ok
  def cancel_payment_intent(_), do: {:error, :invalid_payment_intent_id}

  @doc """
  Creates a customer in Stripe for a user if they don't already have one.

  ## Parameters:
  - `user`: The user to create a customer for

  ## Returns:
  - `{:ok, customer_id}` on success
  - `{:error, reason}` on failure
  """
  def ensure_stripe_customer(user) do
    case get_stripe_customer_id(user) do
      nil ->
        # Preload billing_address to ensure it's available for customer creation
        user = Ysc.Repo.preload(user, :billing_address)
        create_stripe_customer(user)

      customer_id ->
        {:ok, customer_id}
    end
  end

  @doc """
  Gets the Stripe customer ID for a user.
  """
  def get_stripe_customer_id(_user) do
    # This would typically be stored in the user record or a separate table
    # For now, we'll return nil and create a new customer each time
    nil
  end

  ## Private Functions

  defp get_ticket_order_from_payment_intent(payment_intent) do
    ticket_order_id = payment_intent.metadata["ticket_order_id"]

    if ticket_order_id do
      case Tickets.get_ticket_order(ticket_order_id) do
        nil -> {:error, :ticket_order_not_found}
        ticket_order -> {:ok, ticket_order}
      end
    else
      {:error, :no_ticket_order_metadata}
    end
  end

  defp validate_payment_intent(payment_intent, ticket_order) do
    expected_amount = money_to_cents(ticket_order.total_amount)

    cond do
      payment_intent.amount != expected_amount ->
        {:error, :amount_mismatch}

      payment_intent.status != "succeeded" ->
        {:error, :payment_not_succeeded}

      true ->
        :ok
    end
  end

  defp create_stripe_customer(user) do
    customer_params = %{
      email: user.email,
      name: "#{user.first_name} #{user.last_name}",
      description: "User ID: #{user.id}",
      metadata: %{
        user_id: user.id
      }
    }

    # Add phone number if available
    customer_params =
      if user.phone_number && user.phone_number != "" do
        Map.put(customer_params, :phone, user.phone_number)
      else
        customer_params
      end

    # Add address if billing_address is available
    customer_params =
      if user.billing_address do
        address = %{
          line1: user.billing_address.address,
          city: user.billing_address.city,
          postal_code: user.billing_address.postal_code,
          country: user.billing_address.country
        }

        # Add state/region if available
        address =
          if user.billing_address.region && user.billing_address.region != "" do
            Map.put(address, :state, user.billing_address.region)
          else
            address
          end

        Map.put(customer_params, :address, address)
      else
        customer_params
      end

    case stripe_client().create_customer(customer_params) do
      {:ok, customer} ->
        # In a real implementation, you'd store the customer ID in the user record
        # For now, we'll just return it
        {:ok, customer.id}

      {:error, %Stripe.Error{} = error} ->
        {:error, error.message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper function to safely convert Money to cents
  defp money_to_cents(%Money{amount: amount, currency: :USD}) do
    # Use Decimal for precise conversion to avoid floating-point errors
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(%Money{amount: amount, currency: _currency}) do
    # For other currencies, use same conversion
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(_) do
    # Fallback for invalid money values
    0
  end
end
