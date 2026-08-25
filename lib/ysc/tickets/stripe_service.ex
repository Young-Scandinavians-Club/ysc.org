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
  alias Ysc.MoneyHelper

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
    receipt_email = Keyword.get(opts, :receipt_email)
    user = Keyword.get(opts, :user)
    card_present = Keyword.get(opts, :card_present, false)

    with {:ok, ticket_order} <- Tickets.sync_pending_order_pricing(ticket_order) do
      create_payment_intent_for_order(
        ticket_order,
        customer_id,
        payment_method_id,
        receipt_email,
        user,
        card_present
      )
    end
  end

  defp create_payment_intent_for_order(
         ticket_order,
         customer_id,
         payment_method_id,
         receipt_email,
         user,
         card_present
       ) do
    amount_cents = MoneyHelper.money_to_cents(ticket_order.total_amount)

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
      description: "Event tickets - Order #{ticket_order.reference_id}"
    }

    # The mobile app's Stripe Terminal SDK collects and confirms the card
    # present locally, so it needs a PaymentIntent scoped to card_present
    # rather than the automatic_payment_methods used by the web Elements
    # checkout (which negotiates the method with the customer's browser).
    payment_intent_params =
      if card_present do
        Map.merge(payment_intent_params, %{
          payment_method_types: ["card_present"],
          capture_method: "automatic"
        })
      else
        Map.put(payment_intent_params, :automatic_payment_methods, %{
          enabled: true
        })
      end

    payment_intent_params =
      cond do
        match?(%Ysc.Accounts.User{}, user) ->
          {params, _user} =
            Ysc.Customers.attach_customer_to_payment_intent_params(
              payment_intent_params,
              user
            )

          params

        true ->
          payment_intent_params
          |> maybe_put_opt(:customer, customer_id)
          |> maybe_put_opt(:receipt_email, receipt_email)
      end

    # Add payment method if provided
    payment_intent_params =
      if payment_method_id do
        Map.put(payment_intent_params, :payment_method, payment_method_id)
      else
        payment_intent_params
      end

    # Include amount in the idempotency key so repriced orders get a fresh PI.
    # A reference-only key caused Stripe to return a stale PI after tier repricing.
    idempotency_key =
      Ysc.Stripe.Idempotency.key(
        "ticket_order_#{ticket_order.reference_id}_#{amount_cents}"
      )

    case stripe_client().create_payment_intent(payment_intent_params,
           headers: %{"Idempotency-Key" => idempotency_key}
         ) do
      {:ok, payment_intent} ->
        if payment_intent.amount == amount_cents do
          # Update the ticket order with the payment intent ID
          case Tickets.update_payment_intent(ticket_order, payment_intent.id) do
            {:ok, _updated_order} ->
              {:ok, payment_intent}

            {:error, reason} ->
              {:error, reason}
          end
        else
          require Ysc.Logging

          Ysc.Logging.warning(
            "Stripe returned payment intent with stale amount for ticket order",
            ticket_order_id: ticket_order.id,
            expected_amount_cents: amount_cents,
            payment_intent_id: payment_intent.id,
            payment_intent_amount_cents: payment_intent.amount
          )

          {:error, Ysc.PaymentUserMessages.payment_setup_failed()}
        end

      {:error, %Stripe.Error{} = error} ->
        {:error, Ysc.PaymentUserMessages.format_stripe_error(error)}

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
  def process_successful_payment(payment_intent_id)
      when is_binary(payment_intent_id) do
    with {:ok, payment_intent} <-
           stripe_client().retrieve_payment_intent(payment_intent_id, %{}) do
      process_successful_payment(payment_intent)
    end
  end

  def process_successful_payment(%Stripe.PaymentIntent{} = payment_intent) do
    with {:ok, ticket_order} <-
           get_ticket_order_from_payment_intent(payment_intent),
         {:ok, ticket_order} <-
           Tickets.sync_pending_order_pricing_for_fulfillment(ticket_order),
         :ok <- validate_payment_intent(payment_intent, ticket_order) do
      Tickets.process_ticket_order_payment(ticket_order, payment_intent)
    end
  end

  @doc """
  Handles a failed or canceled payment intent.

  Pass `keep_retryable_order: true` (default `false`) for webhook-driven
  callers reacting to `payment_intent.payment_failed`: that event usually
  means Stripe reverted the PaymentIntent to `requires_payment_method` - it's
  still open for the customer to retry with a different card against the
  same PaymentIntent, inline, without ever leaving the checkout page.
  Cancelling the local order in that case would leave it unable to be
  fulfilled if the retry succeeds (`process_ticket_order_payment/2` only
  completes `:pending`/`:expired` orders), stranding a captured charge with
  no ticket and no refund - the same failure mode this module's abandonment
  handling exists to prevent. With this flag, the order is only cancelled
  once Stripe confirms the PaymentIntent itself is terminally `canceled`; a
  still-retryable decline is a no-op that leaves the order pending for a
  later succeeded webhook (or an explicit user/timeout cancel) to resolve.

  Callers with no inline retry UI (e.g. the dedicated payment-failure
  redirect page, where the customer is sent back to pick tickets again
  rather than retry the same PaymentIntent) should leave this `false` to
  keep releasing the order unconditionally, as before.

  ## Parameters:
  - `payment_intent_id`: The Stripe payment intent ID
  - `failure_reason`: Reason for payment failure

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, reason}` on failure
  """
  def handle_failed_payment(
        payment_intent_id,
        failure_reason \\ "Payment failed",
        opts \\ []
      ) do
    keep_retryable_order? = Keyword.get(opts, :keep_retryable_order, false)

    with {:ok, payment_intent} <-
           stripe_client().retrieve_payment_intent(payment_intent_id, %{}),
         {:ok, ticket_order} <-
           get_ticket_order_from_payment_intent(payment_intent) do
      cond do
        payment_intent.status == "succeeded" ->
          process_successful_payment(payment_intent)

        ticket_order.status == :completed ->
          {:ok, ticket_order}

        keep_retryable_order? and payment_intent.status != "canceled" ->
          require Ysc.Logging

          Ysc.Logging.info(
            "PaymentIntent still retryable after failure, not cancelling order",
            ticket_order_id: ticket_order.id,
            payment_intent_id: payment_intent.id,
            payment_intent_status: payment_intent.status
          )

          {:ok, ticket_order}

        true ->
          # Stripe (via this webhook) already decided this PaymentIntent's
          # fate - a decline typically leaves it in requires_payment_method so
          # the customer can retry with a different card against the same
          # PaymentIntent. Skip the atomic Stripe-cancel reconciliation (that's
          # only for closing the abandonment race) so we don't foreclose that
          # retry; just cancel the local order.
          Tickets.cancel_ticket_order(ticket_order, failure_reason,
            reconcile_with_stripe: false
          )
      end
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
    require Ysc.Logging

    case stripe_client().cancel_payment_intent(payment_intent_id, %{}) do
      {:ok, _payment_intent} ->
        Ysc.Logging.info("Successfully canceled PaymentIntent",
          payment_intent_id: payment_intent_id
        )

        :ok

      {:error, %Stripe.Error{} = error} ->
        # PaymentIntent might already be canceled or succeeded - that's okay
        if String.contains?(error.message, "already") or
             String.contains?(error.message, "succeeded") do
          Ysc.Logging.debug("PaymentIntent already canceled or succeeded",
            payment_intent_id: payment_intent_id,
            error: error.message
          )

          :ok
        else
          Ysc.Logging.warning("Failed to cancel PaymentIntent",
            payment_intent_id: payment_intent_id,
            error: error.message
          )

          {:error, error.message}
        end

      {:error, reason} ->
        Ysc.Logging.warning("Failed to cancel PaymentIntent",
          payment_intent_id: payment_intent_id,
          error: reason
        )

        {:error, reason}
    end
  end

  def cancel_payment_intent(nil), do: :ok
  def cancel_payment_intent(_), do: {:error, :invalid_payment_intent_id}

  defp maybe_put_opt(params, _key, value) when is_nil(value) or value == "",
    do: params

  defp maybe_put_opt(params, key, value), do: Map.put(params, key, value)

  @doc """
  Creates a customer in Stripe for a user if they don't already have one.

  ## Parameters:
  - `user`: The user to create a customer for

  ## Returns:
  - `{:ok, customer_id}` on success
  - `{:error, reason}` on failure
  """
  @dialyzer {:nowarn_function, ensure_stripe_customer: 1}
  def ensure_stripe_customer(user) do
    user = Ysc.Repo.preload(user, :billing_address)

    if user.stripe_id && user.stripe_id != "" do
      {:ok, user.stripe_id}
    else
      create_stripe_customer(user)
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
    metadata = payment_intent.metadata || %{}

    metadata_order_id =
      Map.get(metadata, "ticket_order_id") ||
        Map.get(metadata, :ticket_order_id)

    metadata_user_id =
      Map.get(metadata, "user_id") || Map.get(metadata, :user_id)

    {:ok, total, _} = Tickets.recalculate_pending_order_pricing(ticket_order)
    expected_amount = MoneyHelper.money_to_cents(total)

    cond do
      payment_intent.status != "succeeded" ->
        {:error, :payment_not_succeeded}

      to_string(metadata_order_id || "") != to_string(ticket_order.id) ->
        {:error, :payment_metadata_mismatch}

      to_string(metadata_user_id || "") != to_string(ticket_order.user_id) ->
        {:error, :payment_metadata_mismatch}

      payment_intent.amount != expected_amount ->
        {:error, :amount_mismatch}

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
end
