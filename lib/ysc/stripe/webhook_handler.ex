defmodule Ysc.Stripe.WebhookHandler do
  @moduledoc """
  Handles incoming webhook events from Stripe.

  Processes various Stripe webhook event types including subscriptions,
  payments, invoices, and customer updates.
  """
  import Ecto.Query, warn: false
  alias Ysc.Customers
  alias Ysc.Subscriptions
  alias Ysc.Ledgers
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  alias Ysc.Accounts

  # Maximum age for webhook events (5 minutes in seconds)
  @webhook_max_age_seconds 300

  def handle_event(event) do
    require Logger

    Logger.info("Processing Stripe webhook event",
      event_id: event.id,
      event_type: event.type
    )

    # Emit telemetry event for webhook received
    :telemetry.execute(
      [:ysc, :payments, :stripe_webhook_received],
      %{count: 1},
      %{
        event_id: event.id,
        event_type: event.type
      }
    )

    start_time = System.monotonic_time()

    # Check for replay attacks - reject webhooks older than 5 minutes
    result =
      case check_webhook_age(event) do
        :ok ->
          process_webhook(event)

        {:error, :webhook_too_old} = error ->
          Logger.warning("Rejecting old webhook event (possible replay attack)",
            event_id: event.id,
            event_type: event.type,
            event_created: event.created,
            age_seconds:
              DateTime.diff(
                DateTime.utc_now(),
                DateTime.from_unix!(event.created)
              )
          )

          error
      end

    # Emit telemetry event for webhook processing duration
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    :telemetry.execute(
      [:ysc, :payments, :stripe_webhook_processing_duration],
      %{duration: duration_ms},
      %{
        event_id: event.id,
        event_type: event.type,
        status: if(match?(:ok, result), do: "success", else: "failure")
      }
    )

    result
  end

  # Normalizes currency strings to atoms safely, preventing atom exhaustion
  # Supports common Stripe currencies
  defp normalize_currency("usd"), do: :USD
  defp normalize_currency("eur"), do: :EUR
  defp normalize_currency("gbp"), do: :GBP
  defp normalize_currency("cad"), do: :CAD
  defp normalize_currency("aud"), do: :AUD
  defp normalize_currency("jpy"), do: :JPY

  defp normalize_currency(currency) when is_binary(currency) do
    # For unknown currencies, try to use existing atom
    # This will raise if the atom doesn't exist, which is safer than creating new atoms
    String.to_existing_atom(String.upcase(currency))
  rescue
    # Default to USD if currency atom doesn't exist
    ArgumentError -> :USD
  end

  defp normalize_currency(_), do: :USD

  # Check if webhook is within acceptable age
  defp check_webhook_age(event) do
    event_timestamp = DateTime.from_unix!(event.created)
    current_time = DateTime.utc_now()
    age_seconds = DateTime.diff(current_time, event_timestamp)

    if age_seconds > @webhook_max_age_seconds do
      {:error, :webhook_too_old}
    else
      :ok
    end
  end

  # Process webhook after age validation
  defp process_webhook(event) do
    require Logger

    # Write the webhook event to the database first
    # IF already exists, try to lock and process it
    try do
      Ysc.Webhooks.create_webhook_event!(%{
        provider: "stripe",
        event_id: event.id,
        event_type: event.type,
        payload: stripe_event_to_map(event)
      })

      # Lock and process the newly created event
      case Ysc.Webhooks.lock_webhook_event_by_provider_and_event_id(
             "stripe",
             event.id
           ) do
        {:ok, webhook_event} ->
          Logger.info("Locked newly created webhook event for processing",
            event_id: event.id,
            event_type: event.type
          )

          process_webhook_event(webhook_event, event)

        {:error, :already_processing} ->
          Logger.info(
            "Newly created webhook event already being processed, skipping",
            event_id: event.id,
            event_type: event.type
          )

          :ok

        {:error, :not_found} ->
          Logger.error("Newly created webhook event not found after creation",
            event_id: event.id,
            event_type: event.type
          )

          # Report to Sentry
          Sentry.capture_message("Webhook event not found after creation",
            level: :error,
            extra: %{
              event_id: event.id,
              event_type: event.type
            },
            tags: %{
              webhook_provider: "stripe",
              event_type: event.type,
              error_type: "webhook_not_found"
            }
          )

          :ok
      end
    rescue
      Ysc.Webhooks.DuplicateWebhookEventError ->
        # Event already exists, try to lock and process it
        case Ysc.Webhooks.lock_webhook_event_by_provider_and_event_id(
               "stripe",
               event.id
             ) do
          {:ok, webhook_event} ->
            Logger.info("Locked existing webhook event for processing",
              event_id: event.id,
              event_type: event.type
            )

            process_webhook_event(webhook_event, event)

          {:error, :already_processing} ->
            Logger.info("Webhook event already being processed, skipping",
              event_id: event.id,
              event_type: event.type
            )

            :ok

          {:error, :not_found} ->
            Logger.error("Webhook event not found after duplicate error",
              event_id: event.id,
              event_type: event.type
            )

            # Report to Sentry
            Sentry.capture_message(
              "Webhook event not found after duplicate error",
              level: :error,
              extra: %{
                event_id: event.id,
                event_type: event.type
              },
              tags: %{
                webhook_provider: "stripe",
                event_type: event.type,
                error_type: "webhook_not_found_after_duplicate"
              }
            )

            :ok
        end
    end
  end

  defp process_webhook_event(webhook_event, event) do
    require Logger

    try do
      # Process the webhook event
      result = handle(event.type, event.data.object)

      # Mark as processed
      Ysc.Webhooks.update_webhook_state(webhook_event, :processed)

      Logger.info("Webhook event processed successfully",
        event_id: event.id,
        event_type: event.type
      )

      result
    rescue
      error ->
        # Mark as failed
        Ysc.Webhooks.update_webhook_state(webhook_event, :failed)

        Logger.warning("Webhook event processing failed",
          event_id: event.id,
          event_type: event.type,
          error: Exception.message(error)
        )

        # Report to Sentry with full context
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            event_id: event.id,
            event_type: event.type,
            webhook_event_id: webhook_event.id,
            error_message: Exception.message(error)
          },
          tags: %{
            webhook_provider: "stripe",
            event_type: event.type,
            worker: "WebhookHandler"
          }
        )

        :ok
    end
  end

  defp handle("customer.deleted", %Stripe.Customer{} = event) do
    user = Ysc.Accounts.get_user_from_stripe_id(event.id)

    if user do
      user
      |> Customers.subscriptions()
      |> Enum.each(&Subscriptions.mark_as_cancelled/1)
    end

    :ok
  end

  defp handle("customer.created", %Stripe.Customer{} = event) do
    require Logger

    # Try to find user by user_id in metadata first, then by email
    user =
      case event.metadata do
        %{"user_id" => user_id_str} when is_binary(user_id_str) ->
          Ysc.Accounts.get_user(user_id_str)

        _ ->
          # Fallback to finding by email
          case event.email do
            nil -> nil
            email -> Ysc.Accounts.get_user_by_email(email)
          end
      end

    if user do
      if is_nil(user.stripe_id) do
        # User doesn't have stripe_id set, update it
        changeset =
          Ysc.Accounts.User.update_user_changeset(user, %{stripe_id: event.id})

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            Logger.info("Successfully linked Stripe customer to user",
              user_id: user.id,
              stripe_customer_id: event.id,
              method:
                if(event.metadata["user_id"],
                  do: "user_id_metadata",
                  else: "email"
                )
            )

            {:ok, updated_user}

          {:error, changeset} ->
            Logger.error("Failed to update user with stripe_id",
              user_id: user.id,
              stripe_customer_id: event.id,
              changeset_errors: inspect(changeset.errors)
            )

            # Return :error instead of {:error, changeset} as Stripe webhook plug expects
            # {:ok, term}, :ok, {:error, reason}, or :error
            :error
        end
      else
        # User already has stripe_id set
        Logger.info("User already has Stripe customer ID, skipping update",
          user_id: user.id,
          existing_stripe_id: user.stripe_id,
          webhook_stripe_id: event.id
        )

        :ok
      end
    else
      Logger.warning("No user found for customer.created webhook",
        stripe_customer_id: event.id,
        email: event.email,
        user_id_metadata: event.metadata["user_id"]
      )

      :ok
    end
  end

  defp handle("customer.updated", %Stripe.Customer{} = event) do
    user = Ysc.Accounts.get_user_from_stripe_id(event.id)

    if user do
      # Temporarily disable automatic syncing to prevent race conditions
      # The user-initiated payment method selection should handle this
      require Logger

      Logger.info(
        "Customer updated webhook received, skipping automatic sync to prevent race conditions",
        user_id: user.id,
        customer_id: event.id
      )
    end

    :ok
  end

  defp handle("customer.subscription.created", %Stripe.Subscription{} = event) do
    customer = Ysc.Accounts.get_user_from_stripe_id(event.customer)
    Subscriptions.create_subscription_from_stripe(customer, event)

    :ok
  end

  defp handle("customer.subscription.deleted", %Stripe.Subscription{} = event) do
    subscription = Subscriptions.get_subscription_by_stripe_id(event.id)

    if subscription do
      Subscriptions.mark_as_cancelled(subscription)
    end

    :ok
  end

  defp handle("customer.subscription.updated", %Stripe.Subscription{} = event) do
    require Logger

    subscription = Subscriptions.get_subscription_by_stripe_id(event.id)

    if subscription do
      status = event.status

      if status == "incomplete_expired" do
        # Invalidate cache before deleting
        if subscription.user_id do
          Ysc.Accounts.MembershipCache.invalidate_user(subscription.user_id)
        end

        Subscriptions.delete_subscription(subscription)
      else
        # Build update attrs from Stripe subscription
        attrs = %{
          stripe_status: event.status,
          start_date: event.start_date && DateTime.from_unix!(event.start_date),
          current_period_start:
            event.current_period_start &&
              DateTime.from_unix!(event.current_period_start),
          current_period_end:
            event.current_period_end &&
              DateTime.from_unix!(event.current_period_end),
          trial_ends_at:
            event.trial_end && DateTime.from_unix!(event.trial_end),
          ends_at: event.ended_at && DateTime.from_unix!(event.ended_at)
        }

        # Add cancellation info if present
        attrs =
          if event.cancel_at do
            Map.put(attrs, :ends_at, DateTime.from_unix!(event.cancel_at))
          else
            attrs
          end

        case Subscriptions.update_subscription(subscription, attrs) do
          {:ok, updated_subscription} ->
            # Update subscription items
            update_subscription_items(updated_subscription, event.items.data)

            # Check if subscription is now expired or cancelled after update
            # This handles edge cases where status might be "active" but period has ended
            if Subscriptions.cancelled?(updated_subscription) or
                 not Subscriptions.active?(updated_subscription) do
              # Invalidate membership cache to ensure immediate access revocation
              if updated_subscription.user_id do
                Ysc.Accounts.MembershipCache.invalidate_user(
                  updated_subscription.user_id
                )

                Logger.info(
                  "Subscription expired/cancelled via webhook, cache invalidated",
                  subscription_id: updated_subscription.id,
                  user_id: updated_subscription.user_id,
                  stripe_status: updated_subscription.stripe_status,
                  current_period_end: updated_subscription.current_period_end,
                  ends_at: updated_subscription.ends_at
                )
              end
            end

          {:error, _changeset} ->
            :ok
        end
      end
    end

    :ok
  end

  # Grouped subscription_schedule handlers
  defp handle(
         "subscription_schedule.created",
         %Stripe.SubscriptionSchedule{} = _schedule
       ),
       do: :ok

  defp handle(
         "subscription_schedule.updated",
         %Stripe.SubscriptionSchedule{} = _schedule
       ),
       do: :ok

  defp handle(
         "subscription_schedule.released",
         %Stripe.SubscriptionSchedule{} = _schedule
       ),
       do: :ok

  defp handle(
         "subscription_schedule.canceled",
         %Stripe.SubscriptionSchedule{} = _schedule
       ),
       do: :ok

  defp handle(
         "payment_method.attached",
         %Stripe.PaymentMethod{} = payment_method
       ) do
    user = Ysc.Accounts.get_user_from_stripe_id(payment_method.customer)

    if user do
      # Just sync the payment method data without changing default status
      case Ysc.Payments.sync_payment_method_from_stripe(user, payment_method) do
        {:ok, _payment_method_record} ->
          # Payment method created/updated successfully
          :ok

        {:error, _} ->
          # Still log the error but don't fail the webhook
          require Logger

          Logger.warning("Failed to upsert payment method from Stripe webhook",
            user_id: user.id,
            payment_method_id: payment_method.id
          )
      end
    end

    :ok
  end

  defp handle(
         "payment_method.detached",
         %Stripe.PaymentMethod{} = payment_method
       ) do
    case Ysc.Payments.get_payment_method_by_provider(:stripe, payment_method.id) do
      nil ->
        :ok

      existing_payment_method ->
        Ysc.Payments.delete_payment_method(existing_payment_method)
    end

    :ok
  end

  defp handle(
         "payment_method.updated",
         %Stripe.PaymentMethod{} = payment_method
       ) do
    user = Ysc.Accounts.get_user_from_stripe_id(payment_method.customer)

    if user do
      # Just sync the payment method data without changing default status
      Ysc.Payments.sync_payment_method_from_stripe(user, payment_method)
    end

    :ok
  end

  defp handle("setup_intent.created", %Stripe.SetupIntent{} = setup_intent) do
    require Logger

    Logger.info("Setup intent created",
      setup_intent_id: setup_intent.id,
      user_id: setup_intent.customer
    )

    :ok
  end

  defp handle("setup_intent.succeeded", %Stripe.SetupIntent{} = setup_intent) do
    user = Ysc.Accounts.get_user_from_stripe_id(setup_intent.customer)

    if user && setup_intent.payment_method do
      # When setup intent succeeds, the payment method should already be handled by payment_method.attached
      # If it's not found, it will be handled when payment_method.attached is received
      case Ysc.Payments.get_payment_method_by_provider(
             :stripe,
             setup_intent.payment_method
           ) do
        nil ->
          # Payment method not found in our system yet, it will be handled by payment_method.attached
          :ok

        _payment_method_record ->
          # Payment method exists, default setting is already handled by upsert_payment_method_from_stripe
          :ok
      end
    end

    :ok
  end

  defp handle("invoice.payment_action_required", %Stripe.Invoice{} = _invoice) do
    :ok
  end

  # Handle invoice.payment.failed (with dots) - newer Stripe API format
  defp handle("invoice.payment.failed", %Stripe.Invoice{} = invoice) do
    # Convert Stripe struct to map and call the map handler
    invoice_map = %{
      id: invoice.id,
      customer: invoice.customer,
      subscription: invoice.subscription,
      billing_reason: Map.get(invoice, :billing_reason),
      lines: invoice.lines
    }

    handle("invoice.payment.failed", invoice_map)
  end

  # Handle invoice.payment_failed (with underscore) - older Stripe API format
  defp handle("invoice.payment_failed", %Stripe.Invoice{} = invoice) do
    # Convert Stripe struct to map and call the map handler
    invoice_map = %{
      id: invoice.id,
      customer: invoice.customer,
      subscription: invoice.subscription,
      billing_reason: Map.get(invoice, :billing_reason),
      lines: invoice.lines
    }

    handle("invoice.payment.failed", invoice_map)
  end

  # Handle invoice.payment_failed (with underscore) - map format
  defp handle("invoice.payment_failed", invoice) when is_map(invoice) do
    # Route to the same handler as invoice.payment.failed
    handle("invoice.payment.failed", invoice)
  end

  defp handle("invoice.payment.failed", invoice) when is_map(invoice) do
    require Logger

    invoice_id = invoice[:id] || invoice["id"]
    customer_id = invoice[:customer] || invoice["customer"]
    subscription_id_raw = invoice[:subscription] || invoice["subscription"]
    billing_reason = invoice[:billing_reason] || invoice["billing_reason"]

    Logger.info("Handling invoice.payment.failed webhook",
      invoice_id: invoice_id,
      customer_id: customer_id,
      subscription_id: subscription_id_raw,
      billing_reason: billing_reason,
      invoice_keys: if(is_map(invoice), do: Map.keys(invoice), else: [])
    )

    # Check if this is a subscription invoice (membership)
    subscription_id = resolve_subscription_id(invoice)

    case subscription_id do
      nil ->
        # Not a subscription invoice, skip
        Logger.info(
          "Invoice payment failed is not for a subscription, skipping",
          invoice_id: invoice_id,
          customer_id: customer_id,
          subscription_id_from_invoice: subscription_id_raw,
          billing_reason: billing_reason
        )

        :ok

      subscription_id ->
        user = Accounts.get_user_from_stripe_id(customer_id)

        if user do
          # Determine if this is a renewal (not the initial subscription creation)
          # subscription_create = initial payment, subscription_cycle = renewal payment
          is_renewal =
            billing_reason == "subscription_cycle" ||
              billing_reason == "subscription_update"

          # Get membership type from subscription
          membership_type =
            get_membership_type_from_subscription_id(subscription_id)

          Logger.info("Processing membership payment failure",
            invoice_id: invoice_id,
            user_id: user.id,
            subscription_id: subscription_id,
            membership_type: membership_type,
            is_renewal: is_renewal,
            billing_reason: billing_reason
          )

          # Send email notification (always send, regardless of renewal status)
          send_membership_payment_failure_email(
            user,
            membership_type,
            is_renewal,
            invoice_id
          )

          # If this is a renewal payment failure, check if subscription should be expired
          # and immediately invalidate cache to revoke access
          if is_renewal do
            subscription =
              Subscriptions.get_subscription_by_stripe_id(subscription_id)

            if subscription do
              # Check if subscription is expired or should be expired
              if Subscriptions.cancelled?(subscription) or
                   not Subscriptions.active?(subscription) do
                # Invalidate membership cache to ensure immediate access revocation
                Ysc.Accounts.MembershipCache.invalidate_user(user.id)

                Logger.info(
                  "Renewal payment failed and subscription expired, cache invalidated",
                  user_id: user.id,
                  subscription_id: subscription_id,
                  invoice_id: invoice_id
                )
              end
            end
          end

          :ok
        else
          Logger.warning("No user found for invoice payment failure",
            invoice_id: invoice_id,
            customer_id: customer_id,
            subscription_id: subscription_id
          )

          :ok
        end
    end
  end

  defp handle("invoice.payment_succeeded", %Stripe.Invoice{} = invoice) do
    # Convert Stripe struct to map and call the map handler
    invoice_map = %{
      id: invoice.id,
      customer: invoice.customer,
      subscription: invoice.subscription,
      amount_paid: invoice.amount_paid,
      description: invoice.description,
      number: invoice.number,
      charge: invoice.charge,
      metadata: invoice.metadata,
      billing_reason: Map.get(invoice, :billing_reason)
    }

    handle("invoice.payment_succeeded", invoice_map)
  end

  defp handle("invoice.payment_succeeded", invoice) when is_map(invoice) do
    require Logger

    # This webhook is specifically for subscription payments
    # It's more reliable than payment_intent.succeeded for subscription billing
    # Handle both atom and string keys for compatibility
    subscription_id = resolve_subscription_id(invoice)

    case subscription_id do
      nil ->
        # Not a subscription invoice, skip
        :ok

      subscription_id ->
        # Get the user from the customer ID
        customer_id = invoice[:customer] || invoice["customer"]
        invoice_id = invoice[:id] || invoice["id"]
        user = Ysc.Accounts.get_user_from_stripe_id(customer_id)

        if user do
          # Check if we already have a payment record for this invoice
          existing_payment = Ledgers.get_payment_by_external_id(invoice_id)

          if existing_payment do
            Logger.info("Payment already exists for invoice",
              invoice_id: invoice_id,
              payment_id: existing_payment.id
            )

            :ok
          else
            # Process the subscription payment with ledger entries
            # Use find_or_create_subscription_reference to handle race condition
            # where invoice arrives before subscription.created webhook
            entity_id =
              find_or_create_subscription_reference(subscription_id, user)

            amount_paid = invoice[:amount_paid] || invoice["amount_paid"]
            description = invoice[:description] || invoice["description"]
            number = invoice[:number] || invoice["number"]

            payment_attrs = %{
              user_id: user.id,
              amount:
                Money.new(MoneyHelper.cents_to_dollars(amount_paid), :USD),
              entity_type: :membership,
              entity_id: entity_id,
              external_payment_id: invoice_id,
              stripe_fee: extract_stripe_fee_from_invoice(invoice),
              description:
                "Membership payment - #{description || "Invoice #{number}"}",
              property: nil,
              payment_method_id: extract_payment_method_from_invoice(invoice)
            }

            case Ledgers.process_payment(payment_attrs) do
              {:ok, {payment, _transaction, _entries}} ->
                Logger.info(
                  "Subscription payment processed successfully in ledger",
                  invoice_id: invoice_id,
                  user_id: user.id,
                  subscription_id: subscription_id,
                  entity_id: entity_id
                )

                # Send appropriate email: renewal success or first-time payment confirmation
                billing_reason =
                  invoice[:billing_reason] || invoice["billing_reason"]

                is_renewal =
                  billing_reason == "subscription_cycle" ||
                    billing_reason == "subscription_update"

                membership_type =
                  get_membership_type_from_subscription_id(subscription_id)

                payment_date =
                  case payment.payment_date do
                    %Date{} = date -> date
                    %DateTime{} = datetime -> DateTime.to_date(datetime)
                    _ -> Date.utc_today()
                  end

                if is_renewal do
                  send_membership_renewal_success_email(
                    user,
                    membership_type,
                    payment.amount,
                    payment_date
                  )
                else
                  # First-time membership payment: send confirmation that payment was received and membership is active
                  # paid_elsewhere: true when no payment method (e.g. cash/check via Stripe paid_out_of_band)
                  paid_elsewhere = is_nil(payment.payment_method_id)

                  YscWeb.Emails.Notifier.deliver_membership_payment_confirmation(
                    user,
                    membership_type,
                    payment.amount,
                    payment_date,
                    paid_elsewhere: paid_elsewhere
                  )
                end

                :ok

              {:error, reason} ->
                Logger.error("Failed to process subscription payment in ledger",
                  invoice_id: invoice_id,
                  user_id: user.id,
                  subscription_id: subscription_id,
                  error: reason
                )

                # Raise error to mark webhook as failed
                raise "Failed to process payment: #{inspect(reason)}"
            end
          end
        else
          Logger.warning("No user found for invoice payment",
            invoice_id: invoice_id,
            customer_id: customer_id
          )

          # Raise error to mark webhook as failed - missing customer is a critical error
          raise "No user found for customer_id: #{customer_id}"
        end
    end
  end

  defp handle(
         "payment_intent.succeeded",
         %Stripe.PaymentIntent{} = payment_intent
       ) do
    # Convert Stripe struct to map and call the map handler
    payment_intent_map = %{
      id: payment_intent.id,
      status: payment_intent.status,
      customer: payment_intent.customer,
      amount: payment_intent.amount,
      description: payment_intent.description,
      metadata: payment_intent.metadata,
      # latest_charge might not exist on all PaymentIntent structs
      latest_charge: Map.get(payment_intent, :latest_charge)
    }

    handle("payment_intent.succeeded", payment_intent_map)
  end

  defp handle("payment_intent.succeeded", payment_intent)
       when is_map(payment_intent) do
    require Logger

    Logger.info("Payment intent succeeded",
      payment_intent_id: payment_intent.id,
      payment_intent_status: payment_intent.status,
      customer_id: payment_intent.customer
    )

    :ok
  end

  defp handle("payout.paid", %Stripe.Payout{} = payout) do
    # Convert Stripe struct to map and call the map handler
    payout_map = %{
      id: payout.id,
      amount: payout.amount,
      currency: payout.currency,
      status: payout.status,
      arrival_date: payout.arrival_date,
      description: payout.description,
      metadata: payout.metadata
    }

    handle("payout.paid", payout_map)
  end

  defp handle("payout.paid", payout) when is_map(payout) do
    require Logger

    payout_id = payout[:id] || payout["id"]

    Logger.info("Processing Stripe payout",
      payout_id: payout_id,
      amount: payout[:amount] || payout["amount"],
      currency: payout[:currency] || payout["currency"],
      status: payout[:status] || payout["status"]
    )

    # Check if payout already exists (idempotency)
    case Ledgers.get_payout_by_stripe_id(payout_id) do
      nil ->
        # Payout doesn't exist, process it
        process_new_payout(payout)

      existing_payout ->
        # Payout already exists, skip processing
        Logger.info("Payout already processed, skipping (idempotency)",
          payout_id: payout_id,
          existing_payout_id: existing_payout.id
        )

        :ok
    end
  end

  defp handle("charge.dispute.created", %Stripe.Dispute{} = dispute) do
    require Logger

    # Handle chargeback/dispute - you may want to create a liability entry
    Logger.info("Chargeback/dispute created",
      dispute_id: dispute.id,
      charge_id: dispute.charge
    )

    # You could add logic here to create ledger entries for disputes
    :ok
  end

  defp handle("charge.refunded", %Stripe.Charge{} = charge) do
    require Logger

    Logger.info("Charge refunded event received",
      charge_id: charge.id,
      payment_intent_id: charge.payment_intent
    )

    # Note: We prefer to handle refunds via the refund.created webhook
    # which fires for each individual refund. This event can contain
    # multiple refunds, making it harder to track individual refund IDs.
    # However, we'll process it as a fallback in case refund.created is missed.

    # Process each refund individually to ensure proper idempotency
    case charge.refunds do
      %Stripe.List{data: refunds} when is_list(refunds) and refunds != [] ->
        Enum.each(refunds, fn refund ->
          result = process_refund_from_refund_object(refund)

          case result do
            {:error, {:already_processed, _, _}} ->
              Logger.debug(
                "Refund already processed (from charge.refunded event)",
                refund_id: Map.get(refund, :id),
                charge_id: charge.id
              )

            _ ->
              :ok
          end
        end)

      _ ->
        Logger.warning("No refunds data in charge.refunded event",
          charge_id: charge.id
        )
    end

    :ok
  end

  defp handle("refund.created", %Stripe.Refund{} = refund) do
    require Logger

    Logger.info("Refund created",
      refund_id: refund.id,
      charge_id: refund.charge,
      amount: refund.amount
    )

    # Process refund in ledger
    result = process_refund_from_refund_object(refund)

    # Handle idempotency case
    case result do
      {:error, {:already_processed, _, _}} ->
        Logger.info("Refund already processed, skipping (idempotency)",
          refund_id: refund.id,
          charge_id: refund.charge
        )

      _ ->
        :ok
    end

    :ok
  end

  defp handle("refund.created", refund) when is_map(refund) do
    require Logger

    refund_id = refund[:id] || refund["id"]
    charge_id = refund[:charge] || refund["charge"]

    Logger.info("Refund created (map)",
      refund_id: refund_id,
      charge_id: charge_id,
      amount: refund[:amount] || refund["amount"]
    )

    # Process refund in ledger
    result = process_refund_from_refund_object(refund)

    # Handle idempotency case
    case result do
      {:error, {:already_processed, _, _}} ->
        Logger.info("Refund already processed, skipping (idempotency)",
          refund_id: refund_id,
          charge_id: charge_id
        )

      _ ->
        :ok
    end

    :ok
  end

  defp handle("refund.updated", %Stripe.Refund{} = refund) do
    require Logger

    Logger.info("Refund updated",
      refund_id: refund.id,
      charge_id: refund.charge,
      amount: refund.amount,
      status: refund.status
    )

    # You could add logic here to update refund status in ledger
    :ok
  end

  defp handle("refund.updated", refund) when is_map(refund) do
    require Logger

    refund_id = refund[:id] || refund["id"]
    charge_id = refund[:charge] || refund["charge"]

    Logger.info("Refund updated (map)",
      refund_id: refund_id,
      charge_id: charge_id,
      amount: refund[:amount] || refund["amount"],
      status: refund[:status] || refund["status"]
    )

    # You could add logic here to update refund status in ledger
    :ok
  end

  defp handle(event_name, event_object) when is_binary(event_name) do
    # Log unhandled invoice-related events for debugging
    if String.starts_with?(event_name, "invoice.") do
      require Logger

      Logger.debug("Unhandled invoice webhook event",
        event_type: event_name,
        event_object_type:
          if(is_map(event_object),
            do: "map",
            else: inspect(event_object.__struct__)
          )
      )
    end

    :ok
  end

  defp handle(_event_name, _event_object), do: :ok

  # Helper function to process a new payout
  defp process_new_payout(payout) do
    require Logger

    payout_id = payout[:id] || payout["id"]
    amount_cents = payout[:amount] || payout["amount"]
    currency_str = payout[:currency] || payout["currency"]
    currency = normalize_currency(String.downcase(currency_str))

    description =
      payout[:description] || payout["description"] || "Stripe payout"

    status = payout[:status] || payout["status"]
    metadata = payout[:metadata] || payout["metadata"] || %{}

    # Extract fee information from Stripe payout
    # Stripe payouts have a 'fees' object with 'amount' field
    fee_cents =
      case payout[:fees] || payout["fees"] do
        nil -> 0
        fees when is_map(fees) -> fees[:amount] || fees["amount"] || 0
        _ -> 0
      end

    # Parse arrival_date if present
    arrival_date =
      case payout[:arrival_date] || payout["arrival_date"] do
        nil ->
          nil

        unix_timestamp when is_integer(unix_timestamp) ->
          DateTime.from_unix!(unix_timestamp) |> DateTime.truncate(:second)

        _ ->
          nil
      end

    # Convert amount from cents to Money struct
    payout_amount =
      Money.new(MoneyHelper.cents_to_dollars(amount_cents), currency)

    fee_total = Money.new(MoneyHelper.cents_to_dollars(fee_cents), currency)

    Logger.debug("Processing Stripe payout with fees",
      payout_id: payout_id,
      amount: Money.to_string!(payout_amount),
      fee_total: Money.to_string!(fee_total),
      fee_cents: fee_cents
    )

    # Process the payout in the ledger
    case Ledgers.process_stripe_payout(%{
           payout_amount: payout_amount,
           fee_total: fee_total,
           stripe_payout_id: payout_id,
           description: description,
           currency: currency_str,
           status: status,
           arrival_date: arrival_date,
           metadata: metadata
         }) do
      {:ok, {_payout_payment, _transaction, _entries, payout}} ->
        Logger.info("Stripe payout processed successfully in ledger",
          payout_id: payout_id,
          amount: Money.to_string!(payout_amount),
          fee_total:
            if(fee_total, do: Money.to_string!(fee_total), else: "none")
        )

        # Fetch and link payments/refunds from Stripe
        # This must complete before QuickBooks sync
        updated_payout = link_payout_transactions(payout, payout_id)

        # After linking is complete, check if we should enqueue QuickBooks sync
        # Only sync if all linked payments/refunds are already synced AND fee_total is populated
        enqueue_quickbooks_sync_payout_if_ready(updated_payout)

        :ok

      {:error, reason} ->
        Logger.error("Failed to process Stripe payout in ledger",
          payout_id: payout_id,
          amount: Money.to_string!(payout_amount),
          error: reason
        )

        # Report to Sentry
        Sentry.capture_message("Failed to process Stripe payout in ledger",
          level: :error,
          extra: %{
            payout_id: payout_id,
            amount: Money.to_string!(payout_amount),
            error: inspect(reason)
          },
          tags: %{
            webhook_provider: "stripe",
            event_type: "payout.paid",
            error_type: "payout_processing_failed"
          }
        )

        :ok
    end
  end

  @doc """
  Public function to handle webhook events by type and data object.
  This is used by the webhook reprocessor to re-process failed webhooks.
  """
  def handle_webhook_event(event_type, event_object) do
    handle(event_type, event_object)
  end

  @doc """
  Debug function to inspect balance transactions for a payout without processing them.
  Useful for troubleshooting issues with payout linking.

  ## Examples
      iex> Ysc.Stripe.WebhookHandler.debug_payout_transactions("po_1SYFlzREiftrEncLDHTuRysd")
  """
  def debug_payout_transactions(stripe_payout_id)
      when is_binary(stripe_payout_id) do
    require Logger

    Logger.info("Debugging payout transactions",
      stripe_payout_id: stripe_payout_id
    )

    case list_payout_transactions(stripe_payout_id) do
      {:ok, balance_transactions} when is_list(balance_transactions) ->
        IO.puts("\n=== Balance Transactions Debug ===")
        IO.puts("Total transactions: #{length(balance_transactions)}\n")

        Enum.each(balance_transactions, fn bt ->
          IO.puts("Transaction:")
          IO.puts("  ID: #{extract_balance_transaction_id(bt)}")
          IO.puts("  Type: #{extract_field(bt, :type)}")

          IO.puts(
            "  Reporting Category: #{extract_field(bt, :reporting_category)}"
          )

          IO.puts("  Fee: #{extract_field(bt, :fee)}")
          IO.puts("  Amount: #{extract_field(bt, :amount)}")

          IO.puts(
            "  Source Type: #{if is_map(extract_source(bt)), do: extract_source(bt).__struct__ || "map", else: "ID: #{extract_source_id(extract_source(bt))}"}"
          )

          IO.puts("")
        end)

        {:ok, balance_transactions}

      {:error, reason} ->
        IO.puts("Error fetching balance transactions: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_field(balance_transaction, field) do
    cond do
      is_struct(balance_transaction) ->
        # For structs, use Map.get to safely access fields
        try do
          value =
            Map.get(balance_transaction, field) ||
              Map.get(balance_transaction, to_string(field))

          inspect(value)
        rescue
          _ -> "unknown"
        end

      is_map(balance_transaction) ->
        (balance_transaction[field] || balance_transaction[to_string(field)] ||
           "nil")
        |> inspect()

      true ->
        "unknown"
    end
  end

  # Helper to safely extract a field from a balance transaction (struct or map)
  defp get_balance_transaction_field(balance_transaction, field, default \\ nil) do
    cond do
      is_struct(balance_transaction) ->
        # For structs, use Map.get to safely access fields
        try do
          Map.get(balance_transaction, field) ||
            Map.get(balance_transaction, to_string(field)) ||
            default
        rescue
          _ -> default
        end

      is_map(balance_transaction) ->
        balance_transaction[field] || balance_transaction[to_string(field)] ||
          default

      true ->
        default
    end
  end

  @doc """
  Public function to manually re-link payments and refunds to a payout.
  This can be called from IEx to fix payout linking issues.

  This will:
  1. Fetch all balance transactions for the payout from Stripe (with pagination)
  2. Link all payments and refunds to the payout
  3. Update fee_total from balance transactions
  4. Check if QuickBooks sync should be triggered (if all conditions are met)

  ## Examples
      iex> payout = Ysc.Ledgers.get_payout_by_stripe_id("po_1SYFlzREiftrEncLDHTuRysd")
      iex> updated_payout = Ysc.Stripe.WebhookHandler.relink_payout_transactions(payout)
      iex> # Check the results
      iex> updated_payout = Ysc.Repo.preload(updated_payout, [:payments, :refunds])
      iex> IO.inspect(length(updated_payout.payments), label: "Linked payments")
      iex> IO.inspect(length(updated_payout.refunds), label: "Linked refunds")
      iex> IO.inspect(updated_payout.fee_total, label: "Fee total")

  ## Returns
  - `%Ysc.Ledgers.Payout{}` - The updated payout with linked payments/refunds
  """
  def relink_payout_transactions(%Ledgers.Payout{} = payout) do
    require Logger

    Logger.info("Manually relinking payout transactions",
      payout_id: payout.id,
      stripe_payout_id: payout.stripe_payout_id
    )

    # Relink all transactions
    updated_payout = link_payout_transactions(payout, payout.stripe_payout_id)

    # Check if QuickBooks sync should be triggered
    enqueue_quickbooks_sync_payout_if_ready(updated_payout)

    # Return the updated payout
    updated_payout
  end

  # Convert Stripe.Event struct to a plain map for JSON storage
  defp stripe_event_to_map(%Stripe.Event{} = event) do
    %{
      id: event.id,
      object: event.object,
      api_version: event.api_version,
      created: event.created,
      data: convert_to_map(event.data),
      livemode: event.livemode,
      pending_webhooks: event.pending_webhooks,
      request: convert_to_map(event.request),
      type: event.type,
      account: event.account
    }
  end

  # Recursively convert any Stripe structs to maps
  defp convert_to_map(%{__struct__: _module} = struct) do
    # Convert any struct to a map
    Map.from_struct(struct)
    |> Enum.map(fn {key, value} -> {key, convert_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp convert_to_map(%{} = map) do
    # Convert nested maps
    Enum.map(map, fn {key, value} -> {key, convert_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp convert_to_map(list) when is_list(list) do
    Enum.map(list, &convert_to_map/1)
  end

  defp convert_to_map(value), do: value

  # Helper functions for extracting data from payment intents

  @doc """
  Fetches the actual Stripe fee from a charge by retrieving the balance transaction.

  This is the preferred method for getting accurate fee information.
  Falls back to estimated fee calculation if the charge cannot be retrieved.

  ## Parameters:
  - `charge_id`: Stripe charge ID

  ## Returns:
  - `%Money{}` - The Stripe fee amount
  """
  def fetch_actual_stripe_fee_from_charge(charge_id)
      when is_binary(charge_id) do
    require Logger

    try do
      # Fetch the charge with expanded balance transaction to get actual fees
      case Stripe.Charge.retrieve(charge_id, expand: ["balance_transaction"]) do
        {:ok,
         %Stripe.Charge{
           balance_transaction: %Stripe.BalanceTransaction{fee: fee}
         }} ->
          # fee is already in cents, convert to dollars
          # Log the fee for debugging
          Logger.info("Extracted Stripe fee from balance transaction",
            charge_id: charge_id,
            fee_cents: fee,
            fee_dollars: MoneyHelper.cents_to_dollars(fee)
          )

          Money.new(MoneyHelper.cents_to_dollars(fee), :USD)

        {:ok, %Stripe.Charge{}} ->
          Logger.warning(
            "Charge retrieved but no balance transaction fee found",
            charge_id: charge_id
          )

          # Fallback to estimated fee
          calculate_estimated_fee_from_charge_amount(charge_id)

        {:error, reason} ->
          Logger.error("Failed to fetch charge for fee calculation",
            charge_id: charge_id,
            error: reason
          )

          # Fallback to estimated fee
          calculate_estimated_fee_from_charge_amount(charge_id)
      end
    rescue
      error ->
        Logger.error("Exception while fetching charge for fee calculation",
          charge_id: charge_id,
          error: Exception.message(error)
        )

        # Fallback to estimated fee
        calculate_estimated_fee_from_charge_amount(charge_id)
    end
  end

  def fetch_actual_stripe_fee_from_charge(nil) do
    require Logger
    Logger.warning("No charge ID provided for fee calculation")
    # Return zero fee if no charge ID
    Money.new(0, :USD)
  end

  @doc """
  Calculates an estimated Stripe fee when we can't fetch the actual fee.

  Uses the charge amount to estimate: 2.9% + $0.30

  ## Parameters:
  - `charge_id`: Stripe charge ID

  ## Returns:
  - `%Money{}` - The estimated Stripe fee amount
  """
  def calculate_estimated_fee_from_charge_amount(charge_id) do
    require Logger

    try do
      # Try to get the charge amount to calculate estimated fee
      case Stripe.Charge.retrieve(charge_id) do
        {:ok, %Stripe.Charge{amount: amount}} ->
          # amount is in cents, convert to dollars for calculation
          amount_dollars = MoneyHelper.cents_to_dollars(amount)
          calculate_estimated_fee(amount_dollars)

        {:error, reason} ->
          Logger.error("Failed to fetch charge amount for fee estimation",
            charge_id: charge_id,
            error: reason
          )

          # Return zero fee as last resort
          Money.new(0, :USD)
      end
    rescue
      error ->
        Logger.error(
          "Exception while fetching charge amount for fee estimation",
          charge_id: charge_id,
          error: Exception.message(error)
        )

        # Return zero fee as last resort
        Money.new(0, :USD)
    end
  end

  @doc """
  Calculates an estimated Stripe fee based on payment amount.

  Formula: 2.9% + $0.30

  ## Parameters:
  - `amount`: Payment amount as a Decimal (in dollars)

  ## Returns:
  - `%Money{}` - The estimated Stripe fee amount
  """
  def calculate_estimated_fee(amount) do
    # 2.9% + 30¢ for domestic cards
    # amount is a Decimal from cents_to_dollars, so 30¢ = 0.30
    estimated_fee =
      Decimal.add(
        Decimal.mult(amount, Decimal.new("0.029")),
        Decimal.new("0.30")
      )

    # Return Money directly with the fee in dollars (no need to convert back to cents)
    Money.new(estimated_fee, :USD)
  end

  # Helper function to resolve subscription ID from invoice
  # Sometimes the initial subscription invoice has subscription: null but billing_reason: subscription_create
  defp resolve_subscription_id(invoice) do
    subscription_id = invoice[:subscription] || invoice["subscription"]

    if subscription_id do
      subscription_id
    else
      billing_reason = invoice[:billing_reason] || invoice["billing_reason"]
      customer_id = invoice[:customer] || invoice["customer"]

      if billing_reason == "subscription_create" && customer_id do
        require Logger

        Logger.info(
          "Subscription ID missing in invoice, attempting to resolve from customer",
          customer_id: customer_id,
          billing_reason: billing_reason
        )

        user = Ysc.Accounts.get_user_from_stripe_id(customer_id)

        if user do
          case Ysc.Subscriptions.list_subscriptions(user) do
            [] ->
              Logger.warning(
                "No subscriptions found for user when resolving invoice",
                user_id: user.id
              )

              nil

            subscriptions ->
              # Get the most recently created subscription
              # We sort by inserted_at to find the one we just created
              subscription =
                subscriptions
                |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
                |> List.first()

              if subscription do
                Logger.info("Resolved subscription ID from user subscriptions",
                  resolved_subscription_id: subscription.stripe_id
                )

                subscription.stripe_id
              else
                nil
              end
          end
        else
          Logger.warning("User not found when resolving invoice subscription",
            stripe_customer_id: customer_id
          )

          nil
        end
      else
        nil
      end
    end
  end

  # Helper function to find or create subscription reference from Stripe
  # This handles the race condition where invoice.payment_succeeded arrives before customer.subscription.created
  defp find_or_create_subscription_reference(stripe_subscription_id, user) do
    require Logger

    # Try to find existing subscription
    case Ysc.Subscriptions.get_subscription_by_stripe_id(stripe_subscription_id) do
      nil ->
        # Subscription doesn't exist locally yet
        # Fetch from Stripe and create it to ensure proper entity_id linkage
        Logger.info(
          "Subscription not found locally, fetching from Stripe to prevent race condition",
          stripe_subscription_id: stripe_subscription_id,
          user_id: user.id
        )

        case Stripe.Subscription.retrieve(stripe_subscription_id) do
          {:ok, stripe_subscription} ->
            case Subscriptions.create_subscription_from_stripe(
                   user,
                   stripe_subscription
                 ) do
              {:ok, subscription} ->
                Logger.info(
                  "Created subscription from Stripe before processing payment",
                  subscription_id: subscription.id,
                  stripe_subscription_id: stripe_subscription_id,
                  user_id: user.id
                )

                subscription.id

              {:error, reason} ->
                Logger.error("Failed to create subscription from Stripe",
                  stripe_subscription_id: stripe_subscription_id,
                  user_id: user.id,
                  error: inspect(reason)
                )

                nil
            end

          {:error, reason} ->
            Logger.error("Failed to fetch subscription from Stripe",
              stripe_subscription_id: stripe_subscription_id,
              user_id: user.id,
              error: inspect(reason)
            )

            nil
        end

      subscription ->
        subscription.id
    end
  end

  @doc """
  Extracts Stripe fee from an invoice.

  First checks invoice metadata for a fee, then falls back to fetching from the charge.

  ## Parameters:
  - `invoice`: Stripe invoice (map or struct)

  ## Returns:
  - `%Money{}` - The Stripe fee amount
  """
  def extract_stripe_fee_from_invoice(invoice) do
    require Logger

    # Check if fee is provided in metadata first
    metadata = invoice[:metadata] || invoice["metadata"] || %{}
    charge_id = invoice[:charge] || invoice["charge"]

    case metadata do
      %{"stripe_fee" => fee_str} ->
        # Try to parse as integer (cents) first
        case Integer.parse(fee_str) do
          {fee, _} ->
            # If fee seems too large (likely already in dollars), treat as dollars
            # A fee over $1000 would be unusual for most payments
            if fee > 100_000 do
              Logger.warning(
                "Fee in metadata seems unusually large, treating as dollars",
                fee_value: fee,
                charge_id: charge_id
              )

              # Treat as dollars (already converted)
              Money.new(Decimal.new(fee_str), :USD)
            else
              # fee is in cents, convert to dollars
              Money.new(MoneyHelper.cents_to_dollars(fee), :USD)
            end

          :error ->
            # Try parsing as decimal (might be in dollars already)
            case Decimal.parse(fee_str) do
              {decimal, _} ->
                Logger.info(
                  "Fee in metadata parsed as decimal (treating as dollars)",
                  fee_value: fee_str,
                  charge_id: charge_id
                )

                Money.new(decimal, :USD)

              :error ->
                Logger.warning(
                  "Could not parse fee from metadata, fetching from charge",
                  fee_value: fee_str,
                  charge_id: charge_id
                )

                fetch_actual_stripe_fee_from_charge(charge_id)
            end
        end

      _ ->
        fetch_actual_stripe_fee_from_charge(charge_id)
    end
  end

  @doc """
  Extracts Stripe fee from a payment intent.

  Retrieves the charge from the payment intent and fetches the actual fee from the balance transaction.
  Falls back to estimated fee if the charge cannot be retrieved.

  ## Parameters:
  - `payment_intent`: Stripe payment intent (struct or map with :id or "id")

  ## Returns:
  - `%Money{}` - The Stripe fee amount
  """
  def extract_stripe_fee_from_payment_intent(payment_intent) do
    require Logger

    payment_intent_id = get_payment_intent_id(payment_intent)

    # Try to get the charge from the payment intent
    case get_charge_from_payment_intent(payment_intent) do
      {:ok, %{id: charge_id}} when is_binary(charge_id) ->
        # We have a charge ID, fetch actual fee
        fetch_actual_stripe_fee_from_charge(charge_id)

      {:ok, charge} when is_map(charge) ->
        # We have a charge struct, extract the ID
        charge_id = Map.get(charge, :id) || Map.get(charge, "id")

        if charge_id do
          fetch_actual_stripe_fee_from_charge(charge_id)
        else
          # No charge ID found, estimate from payment intent
          estimate_fee_from_payment_intent(payment_intent)
        end

      {:error, _reason} ->
        # Fallback: try to retrieve payment intent with charges expanded
        case retrieve_payment_intent_with_charges(payment_intent_id) do
          {:ok, payment_intent_with_charges} ->
            case get_charge_from_payment_intent(payment_intent_with_charges) do
              {:ok, %{id: charge_id}} when is_binary(charge_id) ->
                fetch_actual_stripe_fee_from_charge(charge_id)

              {:ok, charge} when is_map(charge) ->
                charge_id = Map.get(charge, :id) || Map.get(charge, "id")

                if charge_id do
                  fetch_actual_stripe_fee_from_charge(charge_id)
                else
                  estimate_fee_from_payment_intent(payment_intent)
                end

              {:error, _} ->
                # Final fallback: estimate from payment intent amount
                estimate_fee_from_payment_intent(payment_intent)
            end

          {:error, _} ->
            # Fallback to estimated fee
            estimate_fee_from_payment_intent(payment_intent)
        end
    end
  end

  # Helper to get payment intent ID from struct or map
  defp get_payment_intent_id(%{id: id}) when is_binary(id), do: id
  defp get_payment_intent_id(%{"id" => id}) when is_binary(id), do: id
  defp get_payment_intent_id(_), do: nil

  # Helper to get charge from payment intent
  defp get_charge_from_payment_intent(%{
         charges: %Stripe.List{data: [charge | _]}
       })
       when is_map(charge),
       do: {:ok, charge}

  defp get_charge_from_payment_intent(%{"charges" => %{"data" => [charge | _]}})
       when is_map(charge),
       do: {:ok, charge}

  defp get_charge_from_payment_intent(%{latest_charge: charge_id})
       when is_binary(charge_id),
       do: {:ok, %{id: charge_id}}

  defp get_charge_from_payment_intent(%{"latest_charge" => charge_id})
       when is_binary(charge_id),
       do: {:ok, %{id: charge_id}}

  defp get_charge_from_payment_intent(_), do: {:error, :no_charge_found}

  # Helper to retrieve payment intent with charges expanded
  defp retrieve_payment_intent_with_charges(nil),
    do: {:error, :no_payment_intent_id}

  defp retrieve_payment_intent_with_charges(payment_intent_id) do
    case Stripe.PaymentIntent.retrieve(payment_intent_id, %{
           expand: ["charges.data.balance_transaction"]
         }) do
      {:ok, payment_intent} -> {:ok, payment_intent}
      {:error, reason} -> {:error, reason}
    end
  end

  # Helper to estimate fee from payment intent amount
  defp estimate_fee_from_payment_intent(payment_intent) do
    require Logger

    amount_cents = get_payment_intent_amount(payment_intent)

    if amount_cents do
      amount_dollars = MoneyHelper.cents_to_dollars(amount_cents)
      calculate_estimated_fee(amount_dollars)
    else
      Logger.warning(
        "Could not determine payment intent amount for fee estimation"
      )

      Money.new(0, :USD)
    end
  end

  # Helper to get amount from payment intent
  defp get_payment_intent_amount(%{amount: amount}) when is_integer(amount),
    do: amount

  defp get_payment_intent_amount(%{"amount" => amount}) when is_integer(amount),
    do: amount

  defp get_payment_intent_amount(_), do: nil

  # Helper function to update subscription items
  defp update_subscription_items(subscription, stripe_items) do
    # Create/update subscription items
    subscription_items =
      Subscriptions.subscription_item_structs_from_stripe_items(
        stripe_items,
        subscription
      )

    # Insert new items, update any items that may have changed
    Enum.each(subscription_items, fn item ->
      Ysc.Repo.insert!(item,
        on_conflict: :replace_all,
        conflict_target: [:stripe_id]
      )
    end)

    # Delete any items that may have been removed
    item_ids = Enum.map(stripe_items, & &1.id)

    from(s in Ysc.Subscriptions.SubscriptionItem,
      where: s.subscription_id == ^subscription.id,
      where: s.stripe_id not in ^item_ids
    )
    |> Ysc.Repo.delete_all()
  end

  # Helper function to ensure customer has a default payment method after subscription creation

  # Helper function to extract and sync payment method from Stripe invoice
  # Creates the payment method in our database if it doesn't exist
  defp extract_payment_method_from_invoice(invoice) do
    require Logger

    # Get the charge ID from the invoice
    charge_id = invoice[:charge] || invoice["charge"]
    invoice_id = invoice[:id] || invoice["id"]
    customer_id = invoice[:customer] || invoice["customer"]

    case charge_id do
      nil ->
        Logger.info("No charge found in invoice", invoice_id: invoice_id)
        nil

      charge_id when is_binary(charge_id) ->
        # Retrieve the charge to get payment method details
        case Stripe.Charge.retrieve(charge_id) do
          {:ok, charge} ->
            # Get the payment method ID from the charge
            payment_method_id =
              cond do
                is_struct(charge) ->
                  Map.get(charge, :payment_method) ||
                    Map.get(charge, "payment_method")

                is_map(charge) ->
                  charge[:payment_method] || charge["payment_method"]

                true ->
                  nil
              end

            case payment_method_id do
              nil ->
                Logger.info("No payment method found in charge",
                  charge_id: charge_id,
                  invoice_id: invoice_id
                )

                nil

              stripe_payment_method_id
              when is_binary(stripe_payment_method_id) ->
                # Get the user to sync the payment method
                user = Ysc.Accounts.get_user_from_stripe_id(customer_id)

                if user do
                  # Check if payment method already exists in our database
                  case Ysc.Payments.get_payment_method_by_provider(
                         :stripe,
                         stripe_payment_method_id
                       ) do
                    nil ->
                      # Payment method doesn't exist, retrieve from Stripe and create it
                      Logger.info(
                        "Payment method not found in local database, creating it",
                        stripe_payment_method_id: stripe_payment_method_id,
                        charge_id: charge_id,
                        invoice_id: invoice_id
                      )

                      case Stripe.PaymentMethod.retrieve(
                             stripe_payment_method_id
                           ) do
                        {:ok, stripe_payment_method} ->
                          # Sync the payment method to our database
                          case Ysc.Payments.sync_payment_method_from_stripe(
                                 user,
                                 stripe_payment_method
                               ) do
                            {:ok, payment_method} ->
                              Logger.info("Created payment method for invoice",
                                payment_method_id: payment_method.id,
                                stripe_payment_method_id:
                                  stripe_payment_method_id,
                                charge_id: charge_id,
                                invoice_id: invoice_id
                              )

                              payment_method.id

                            {:error, reason} ->
                              Logger.error(
                                "Failed to create payment method from Stripe",
                                stripe_payment_method_id:
                                  stripe_payment_method_id,
                                charge_id: charge_id,
                                invoice_id: invoice_id,
                                error: inspect(reason)
                              )

                              nil
                          end

                        {:error, error} ->
                          Logger.error(
                            "Failed to retrieve payment method from Stripe",
                            stripe_payment_method_id: stripe_payment_method_id,
                            charge_id: charge_id,
                            invoice_id: invoice_id,
                            error: inspect(error)
                          )

                          nil
                      end

                    existing_payment_method ->
                      # Payment method already exists
                      Logger.info("Found existing payment method for invoice",
                        payment_method_id: existing_payment_method.id,
                        stripe_payment_method_id: stripe_payment_method_id,
                        charge_id: charge_id,
                        invoice_id: invoice_id
                      )

                      existing_payment_method.id
                  end
                else
                  Logger.warning(
                    "User not found for customer, cannot create payment method",
                    customer_id: customer_id,
                    invoice_id: invoice_id,
                    stripe_payment_method_id: stripe_payment_method_id
                  )

                  nil
                end
            end

          {:error, error} ->
            Logger.warning("Failed to retrieve charge from Stripe",
              charge_id: charge_id,
              error:
                if(is_struct(error), do: error.message, else: inspect(error)),
              invoice_id: invoice_id
            )

            nil
        end
    end
  end

  # Process refund from Stripe refund object (can be struct or map)
  defp process_refund_from_refund_object(%Stripe.Refund{} = refund) do
    # Convert struct to map for unified processing
    process_refund_from_refund_object(Map.from_struct(refund))
  end

  defp process_refund_from_refund_object(refund) when is_map(refund) do
    require Logger

    # Extract fields from refund (handles both struct and map)
    refund_id = Map.get(refund, :id) || Map.get(refund, "id")
    charge_id = Map.get(refund, :charge) || Map.get(refund, "charge")
    amount = Map.get(refund, :amount) || Map.get(refund, "amount")
    metadata = Map.get(refund, :metadata) || Map.get(refund, "metadata") || %{}

    # Get payment intent ID directly from refund object (preferred) or from charge
    payment_intent_id =
      Map.get(refund, :payment_intent) || Map.get(refund, "payment_intent")

    # If payment_intent is not directly available, try to get it from charge
    payment_intent_id =
      if is_nil(payment_intent_id) && charge_id do
        case Stripe.Charge.retrieve(charge_id, %{expand: ["payment_intent"]}) do
          {:ok, charge} ->
            charge.payment_intent

          {:error, reason} ->
            Logger.warning("Failed to retrieve charge for refund",
              charge_id: charge_id,
              refund_id: refund_id,
              error: inspect(reason)
            )

            nil
        end
      else
        payment_intent_id
      end

    if payment_intent_id do
      # Find the payment by external_payment_id
      payment = Ledgers.get_payment_by_external_id(payment_intent_id)

      if payment do
        # Convert refund amount from cents to dollars
        refund_amount = Money.new(MoneyHelper.cents_to_dollars(amount), :USD)

        # Get refund reason from metadata or use default
        reason =
          case metadata do
            %{"reason" => reason} when is_binary(reason) -> reason
            %{reason: reason} when is_binary(reason) -> reason
            _ -> "Booking cancellation refund"
          end

        # Process refund in ledger
        case Ledgers.process_refund(%{
               payment_id: payment.id,
               refund_amount: refund_amount,
               reason: reason,
               external_refund_id: refund_id
             }) do
          {:ok, {_refund, _refund_transaction, _entries}} ->
            Logger.info("Refund processed successfully in ledger",
              payment_id: payment.id,
              refund_id: refund_id,
              amount: Money.to_string!(refund_amount)
            )

            :ok

          {:error, {:already_processed, refund, refund_transaction}} ->
            # Return the error tuple so caller can handle idempotency
            {:error, {:already_processed, refund, refund_transaction}}

          {:error, reason} ->
            Logger.error("Failed to process refund in ledger",
              payment_id: payment.id,
              refund_id: refund_id,
              error: inspect(reason)
            )

            {:error, reason}
        end
      else
        Logger.warning("Payment not found for refund",
          payment_intent_id: payment_intent_id,
          refund_id: refund_id
        )

        :ok
      end
    else
      Logger.warning("No payment intent ID found in refund",
        refund_id: refund_id,
        charge_id: charge_id
      )

      :ok
    end
  end

  # Fetches ALL balance transactions for a given payout ID, handling pagination.
  # Uses Stripe.BalanceTransaction.all with expand to get source objects (charges/refunds).
  defp list_payout_transactions(payout_id) do
    do_fetch_transactions(payout_id, [], nil)
  end

  defp do_fetch_transactions(payout_id, acc, starting_after) do
    require Logger

    params = %{
      payout: payout_id,
      limit: 100,
      expand: ["data.source"]
    }

    # Add the cursor if we have one
    params =
      if starting_after,
        do: Map.put(params, :starting_after, starting_after),
        else: params

    # Check if BalanceTransaction.all is available
    result =
      if Code.ensure_loaded(Stripe.BalanceTransaction) &&
           function_exported?(Stripe.BalanceTransaction, :all, 1) do
        Stripe.BalanceTransaction.all(params)
      else
        {:error, :not_available}
      end

    case result do
      {:ok, %{data: data, has_more: true}} when is_list(data) ->
        last_id = List.last(data) |> extract_balance_transaction_id()

        Logger.debug("Fetched balance transactions page",
          payout_id: payout_id,
          page_size: length(data),
          has_more: true,
          last_id: last_id
        )

        if last_id do
          do_fetch_transactions(payout_id, acc ++ data, last_id)
        else
          Logger.warning(
            "Could not extract last_id from balance transactions, stopping pagination",
            payout_id: payout_id,
            page_size: length(data)
          )

          {:ok, acc ++ data}
        end

      {:ok, %{data: data, has_more: false}} when is_list(data) ->
        Logger.debug("Fetched final balance transactions page",
          payout_id: payout_id,
          page_size: length(data),
          has_more: false
        )

        {:ok, acc ++ data}

      {:ok, %Stripe.List{data: data, has_more: true}} when is_list(data) ->
        # Handle Stripe.List struct format (backwards compatibility)
        last_id = List.last(data) |> extract_balance_transaction_id()

        Logger.debug("Fetched balance transactions page (List format)",
          payout_id: payout_id,
          page_size: length(data),
          has_more: true,
          last_id: last_id
        )

        if last_id do
          do_fetch_transactions(payout_id, acc ++ data, last_id)
        else
          Logger.warning(
            "Could not extract last_id from balance transactions, stopping pagination",
            payout_id: payout_id,
            page_size: length(data)
          )

          {:ok, acc ++ data}
        end

      {:ok, %Stripe.List{data: data, has_more: false}} when is_list(data) ->
        # Handle Stripe.List struct format (backwards compatibility)
        Logger.debug("Fetched final balance transactions page (List format)",
          payout_id: payout_id,
          page_size: length(data),
          has_more: false
        )

        {:ok, acc ++ data}

      {:error, reason} ->
        Logger.error("Failed to fetch balance transactions",
          payout_id: payout_id,
          error: inspect(reason),
          error_type:
            if(is_struct(reason), do: reason.__struct__, else: :unknown)
        )

        {:error, reason}

      unexpected ->
        Logger.error("Unexpected response format from BalanceTransaction.all",
          payout_id: payout_id,
          response_type: inspect(unexpected.__struct__ || :map),
          response_keys:
            if(is_map(unexpected), do: Map.keys(unexpected), else: [])
        )

        {:error, {:unexpected_format, unexpected}}
    end
  end

  # Helper to extract ID from balance transaction (handles both struct and map)
  defp extract_balance_transaction_id(balance_transaction) do
    cond do
      is_struct(balance_transaction) ->
        # For structs, try to access the id field directly
        try do
          Map.get(balance_transaction, :id) ||
            Map.get(balance_transaction, "id")
        rescue
          _ -> nil
        end

      is_map(balance_transaction) ->
        balance_transaction[:id] || balance_transaction["id"]

      true ->
        nil
    end
  end

  # Helper function to link payments and refunds to a payout
  defp link_payout_transactions(payout, stripe_payout_id) do
    require Logger

    Logger.info(
      "[Payout] link_payout_transactions: Starting to link transactions to payout",
      payout_id: payout.id,
      stripe_payout_id: stripe_payout_id,
      payout_amount: Money.to_string!(payout.amount)
    )

    # First, try to get fees from the payout's balance transaction (most reliable)
    # The payout's balance transaction contains the total fees for all charges/refunds in the payout
    updated_payout =
      case Stripe.Payout.retrieve(stripe_payout_id,
             expand: ["balance_transaction"]
           ) do
        {:ok,
         %Stripe.Payout{
           balance_transaction: %Stripe.BalanceTransaction{fee: fee_cents} = bt
         }}
        when is_integer(fee_cents) and fee_cents > 0 ->
          Logger.info("Retrieved payout balance transaction with fee",
            payout_id: stripe_payout_id,
            balance_transaction_id: bt.id,
            fee_cents: fee_cents
          )

          currency = payout.currency || "usd"
          currency_atom = normalize_currency(String.downcase(currency))

          fee_total =
            Money.new(MoneyHelper.cents_to_dollars(fee_cents), currency_atom)

          Logger.info("Extracted fee from payout balance transaction",
            payout_id: stripe_payout_id,
            fee_cents: fee_cents,
            fee_total: Money.to_string!(fee_total)
          )

          # Update the payout's fee_total
          changeset =
            Ysc.Ledgers.Payout.changeset(payout, %{fee_total: fee_total})

          case Repo.update(changeset) do
            {:ok, updated} ->
              Logger.info("Updated payout fee_total from balance transaction",
                payout_id: stripe_payout_id,
                fee_total: Money.to_string!(fee_total)
              )

              updated

            {:error, changeset} ->
              Logger.error("Failed to update payout fee_total",
                payout_id: stripe_payout_id,
                errors: inspect(changeset.errors)
              )

              payout
          end

        {:ok,
         %Stripe.Payout{
           balance_transaction: %Stripe.BalanceTransaction{fee: fee_cents}
         }} ->
          Logger.debug("Payout balance transaction has no fee or zero fee",
            payout_id: stripe_payout_id,
            fee_cents: fee_cents
          )

          # Fallback to listing balance transactions
          try_calculate_fees_from_balance_transactions(payout, stripe_payout_id)

        {:ok, %Stripe.Payout{balance_transaction: nil}} ->
          Logger.warning("Payout balance transaction is nil",
            payout_id: stripe_payout_id
          )

          # Fallback to listing balance transactions
          try_calculate_fees_from_balance_transactions(payout, stripe_payout_id)

        {:ok, %Stripe.Payout{}} ->
          Logger.debug("Payout retrieved but balance transaction not expanded",
            payout_id: stripe_payout_id
          )

          # Fallback to listing balance transactions
          try_calculate_fees_from_balance_transactions(payout, stripe_payout_id)

        {:error, reason} ->
          Logger.warning("Failed to retrieve payout with balance transaction",
            payout_id: stripe_payout_id,
            error: inspect(reason)
          )

          # Fallback to listing balance transactions
          try_calculate_fees_from_balance_transactions(payout, stripe_payout_id)
      end

    # Now link all balance transactions to the payout using BalanceTransaction API with pagination
    try do
      # Fetch ALL balance transactions for this payout from Stripe with pagination
      # Balance transactions show all charges, refunds, and fees included in the payout
      case list_payout_transactions(stripe_payout_id) do
        {:ok, balance_transactions} when is_list(balance_transactions) ->
          Logger.info("[Payout] Found balance transactions for payout",
            payout_id: stripe_payout_id,
            balance_transactions_count: length(balance_transactions),
            balance_transaction_types:
              Enum.map(balance_transactions, fn bt ->
                get_balance_transaction_field(bt, :type, "unknown")
              end)
          )

          # Link transactions to payout
          {linked_count, skipped_count} =
            Enum.reduce(balance_transactions, {0, 0}, fn balance_transaction,
                                                         {linked, skipped} ->
              result =
                link_balance_transaction_to_payout(
                  updated_payout,
                  balance_transaction
                )

              case result do
                :ok -> {linked + 1, skipped}
                :skipped -> {linked, skipped + 1}
                _ -> {linked, skipped + 1}
              end
            end)

          Logger.info(
            "[Payout] Finished linking balance transactions to payout",
            payout_id: stripe_payout_id,
            total_balance_transactions: length(balance_transactions),
            linked_count: linked_count,
            skipped_count: skipped_count
          )

          # Reload payout to get updated payment/refund counts
          updated_payout =
            Repo.reload!(updated_payout) |> Repo.preload([:payments, :refunds])

          Logger.info("[Payout] Final payout transaction counts after linking",
            payout_id: stripe_payout_id,
            payments_count: length(updated_payout.payments),
            refunds_count: length(updated_payout.refunds),
            fee_total:
              if(updated_payout.fee_total,
                do: Money.to_string!(updated_payout.fee_total),
                else: "not set"
              ),
            payment_ids: Enum.map(updated_payout.payments, & &1.id),
            refund_ids: Enum.map(updated_payout.refunds, & &1.id)
          )

          # Return the updated payout so caller can check if linking is complete
          updated_payout

        {:error, reason} ->
          Logger.warning("Failed to fetch balance transactions for payout",
            payout_id: stripe_payout_id,
            error: inspect(reason)
          )

          # Return the payout even if linking failed (caller can check status)
          updated_payout
      end
    rescue
      error ->
        Logger.error("Exception while linking balance transactions",
          payout_id: stripe_payout_id,
          error: Exception.message(error),
          error_type: error.__struct__,
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Report to Sentry for visibility
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            payout_id: stripe_payout_id,
            function: "link_payout_transactions"
          }
        )

        # Return the payout even if linking failed (caller can check status)
        updated_payout
    end
  end

  # Fallback: Calculate fees from listing all balance transactions for the payout
  defp try_calculate_fees_from_balance_transactions(payout, stripe_payout_id) do
    require Logger

    try do
      case list_payout_transactions(stripe_payout_id) do
        {:ok, balance_transactions} when is_list(balance_transactions) ->
          Logger.info(
            "Found #{length(balance_transactions)} balance transactions for fee calculation",
            payout_id: stripe_payout_id
          )

          # Calculate total fees from balance transactions
          # Skip the payout balance transaction itself (type: "payout")
          total_fee_cents =
            Enum.reduce(balance_transactions, 0, fn balance_transaction, acc ->
              try do
                # Skip payout balance transactions
                transaction_type =
                  get_balance_transaction_field(balance_transaction, :type)

                if transaction_type == "payout" do
                  # Skip the payout transaction itself
                  acc
                else
                  fee_cents =
                    get_balance_transaction_field(balance_transaction, :fee, 0) ||
                      0

                  acc + fee_cents
                end
              rescue
                error ->
                  Logger.warning(
                    "Error processing balance transaction for fee calculation",
                    error: Exception.message(error),
                    balance_transaction_id:
                      extract_balance_transaction_id(balance_transaction)
                  )

                  acc
              end
            end)

          if total_fee_cents > 0 do
            currency = payout.currency || "usd"
            currency_atom = normalize_currency(String.downcase(currency))

            fee_total =
              Money.new(
                MoneyHelper.cents_to_dollars(total_fee_cents),
                currency_atom
              )

            Logger.info("Calculated total fees from balance transactions list",
              payout_id: stripe_payout_id,
              fee_cents: total_fee_cents,
              fee_total: Money.to_string!(fee_total)
            )

            changeset =
              Ysc.Ledgers.Payout.changeset(payout, %{fee_total: fee_total})

            case Repo.update(changeset) do
              {:ok, updated} ->
                Logger.info(
                  "Updated payout fee_total from balance transactions list",
                  payout_id: stripe_payout_id,
                  fee_total: Money.to_string!(fee_total)
                )

                updated

              {:error, changeset} ->
                Logger.error("Failed to update payout fee_total",
                  payout_id: stripe_payout_id,
                  errors: inspect(changeset.errors)
                )

                payout
            end
          else
            Logger.debug("No fees found in balance transactions list",
              payout_id: stripe_payout_id
            )

            payout
          end

        {:error, reason} ->
          Logger.warning(
            "Failed to fetch balance transactions for fee calculation",
            payout_id: stripe_payout_id,
            error: inspect(reason)
          )

          payout
      end
    rescue
      error ->
        Logger.error(
          "Exception while calculating fees from balance transactions",
          payout_id: stripe_payout_id,
          error: Exception.message(error),
          error_type: error.__struct__,
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Report to Sentry for visibility
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            payout_id: stripe_payout_id,
            function: "try_calculate_fees_from_balance_transactions"
          }
        )

        payout
    end
  end

  # Helper function to link a single balance transaction to a payout
  defp link_balance_transaction_to_payout(payout, balance_transaction) do
    require Logger

    # Get transaction type - skip payout balance transactions (the payout itself)
    transaction_type =
      get_balance_transaction_field(balance_transaction, :type, "unknown")

    # Skip the payout balance transaction itself (type: "payout")
    if transaction_type == "payout" do
      Logger.debug(
        "[Payout] Skipping payout balance transaction (the payout itself)",
        payout_id: payout.stripe_payout_id,
        transaction_type: transaction_type
      )

      :skipped
    else
      # Use reporting_category to identify charges/refunds (more reliable than type)
      reporting_category =
        get_balance_transaction_field(balance_transaction, :reporting_category)

      # Get source - may be an ID string or an expanded object (Charge/Refund/Payout)
      source = extract_source(balance_transaction)
      source_id = extract_source_id(source)

      Logger.debug(
        "[Payout] link_balance_transaction_to_payout: Processing balance transaction",
        payout_id: payout.stripe_payout_id,
        transaction_type: transaction_type,
        reporting_category: reporting_category,
        source_id: source_id,
        source_expanded:
          is_struct(source) || (is_map(source) && Map.has_key?(source, :id))
      )

      # Balance transactions can be charges, refunds, or other types
      # We need to find the corresponding payment or refund in our system
      # Use reporting_category if available, otherwise fall back to type
      result =
        case reporting_category || transaction_type do
          "charge" ->
            # If source is expanded (Charge object), use it directly; otherwise fetch by ID
            link_charge_to_payout(payout, source, source_id)

          "refund" ->
            # If source is expanded (Refund object), use it directly; otherwise fetch by ID
            link_stripe_refund_to_payout(payout, source, source_id)

          _ ->
            # Other types (fees, adjustments, payout, etc.) - skip for now
            Logger.debug("[Payout] Skipping balance transaction type",
              payout_id: payout.stripe_payout_id,
              transaction_type: transaction_type,
              reporting_category: reporting_category,
              source_id: source_id
            )

            :skipped
        end

      result
    end
  end

  # Helper to extract source from balance transaction (may be ID string or expanded object)
  defp extract_source(balance_transaction) do
    get_balance_transaction_field(balance_transaction, :source)
  end

  # Helper to extract ID from source (handles both ID strings and expanded objects)
  defp extract_source_id(nil), do: nil

  defp extract_source_id(source) when is_binary(source), do: source

  defp extract_source_id(source) when is_struct(source) do
    # For structs, use Map.get to safely access the id field
    try do
      Map.get(source, :id) || Map.get(source, "id")
    rescue
      _ -> nil
    end
  end

  defp extract_source_id(source) when is_map(source) do
    source[:id] || source["id"]
  end

  defp extract_source_id(_), do: nil

  # Helper function to link a charge to a payout
  # source may be an expanded Charge object or nil (if we need to fetch by ID)
  defp link_charge_to_payout(payout, source, charge_id) do
    require Logger

    try do
      # If source is already an expanded Charge object, use it directly
      charge =
        cond do
          is_struct(source) ->
            # Check if it has a payment_intent field (expanded Charge object)
            if Map.has_key?(source, :payment_intent) ||
                 Map.has_key?(source, "payment_intent") do
              source
            else
              nil
            end

          is_map(source) &&
              (Map.has_key?(source, :payment_intent) ||
                 Map.has_key?(source, "payment_intent")) ->
            # Source is an expanded Charge map
            source

          is_binary(charge_id) ->
            # Source is just an ID, fetch the charge
            case Stripe.Charge.retrieve(charge_id) do
              {:ok, charge} ->
                charge

              {:error, reason} ->
                Logger.warning("Failed to retrieve charge",
                  charge_id: charge_id,
                  error: inspect(reason)
                )

                nil
            end

          true ->
            nil
        end

      if charge do
        payment_intent_id =
          cond do
            is_struct(charge) ->
              # For structs, use Map.get to safely access fields
              Map.get(charge, :payment_intent) ||
                Map.get(charge, "payment_intent")

            is_map(charge) ->
              charge[:payment_intent] || charge["payment_intent"]

            true ->
              nil
          end

        invoice_id =
          cond do
            is_struct(charge) ->
              # For structs, use Map.get to safely access fields
              Map.get(charge, :invoice) || Map.get(charge, "invoice")

            is_map(charge) ->
              charge[:invoice] || charge["invoice"]

            true ->
              nil
          end

        # Try to find payment by payment_intent_id first (for booking payments)
        # If not found, try invoice_id (for subscription payments)
        payment =
          cond do
            payment_intent_id ->
              Ledgers.get_payment_by_external_id(payment_intent_id)

            invoice_id ->
              Ledgers.get_payment_by_external_id(invoice_id)

            true ->
              nil
          end

        if payment do
          {:ok, _} = Ledgers.link_payment_to_payout(payout, payment)

          Logger.info("[Payout] Successfully linked payment to payout",
            payout_id: payout.stripe_payout_id,
            payout_db_id: payout.id,
            payment_id: payment.id,
            payment_reference_id: payment.reference_id,
            payment_amount: Money.to_string!(payment.amount),
            charge_id: charge_id,
            payment_intent_id: payment_intent_id,
            invoice_id: invoice_id,
            external_payment_id: payment.external_payment_id
          )

          :ok
        else
          Logger.warning(
            "[Payout] Payment not found for charge - cannot link to payout",
            payout_id: payout.stripe_payout_id,
            charge_id: charge_id,
            payment_intent_id: payment_intent_id,
            invoice_id: invoice_id,
            note:
              "Payment may not exist in database. Tried payment_intent_id and invoice_id as external_payment_id"
          )

          :skipped
        end
      else
        :skipped
      end
    rescue
      error ->
        Logger.error("Exception while linking charge to payout",
          charge_id: charge_id,
          error: Exception.message(error),
          error_type: error.__struct__,
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Report to Sentry for visibility
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            charge_id: charge_id,
            function: "link_charge_to_payout"
          }
        )

        :skipped
    end
  end

  # Helper function to link a Stripe refund to a payout
  # source may be an expanded Refund object or nil (if we need to fetch by ID)
  defp link_stripe_refund_to_payout(payout, source, stripe_refund_id) do
    require Logger

    try do
      # If source is already an expanded Refund object, use it directly
      refund =
        cond do
          is_struct(source) ->
            # Check if it has a charge field (expanded Refund object)
            if Map.has_key?(source, :charge) || Map.has_key?(source, "charge") do
              source
            else
              nil
            end

          is_map(source) &&
              (Map.has_key?(source, :charge) || Map.has_key?(source, "charge")) ->
            # Source is an expanded Refund map
            source

          is_binary(stripe_refund_id) ->
            # Source is just an ID, fetch the refund
            case Stripe.Refund.retrieve(stripe_refund_id) do
              {:ok, refund} ->
                refund

              {:error, reason} ->
                Logger.warning("Failed to retrieve refund",
                  stripe_refund_id: stripe_refund_id,
                  error: inspect(reason)
                )

                nil
            end

          true ->
            nil
        end

      if refund do
        charge_id =
          cond do
            is_struct(refund) ->
              # For structs, use Map.get to safely access fields
              Map.get(refund, :charge) || Map.get(refund, "charge")

            is_map(refund) ->
              refund[:charge] || refund["charge"]

            true ->
              nil
          end

        if charge_id do
          # Get the charge to find the payment intent
          case Stripe.Charge.retrieve(charge_id) do
            {:ok, charge} ->
              payment_intent_id = charge.payment_intent

              if payment_intent_id do
                # Find the payment
                payment = Ledgers.get_payment_by_external_id(payment_intent_id)

                if payment do
                  # Find the Refund by external_refund_id
                  db_refund =
                    Ledgers.get_refund_by_external_id(stripe_refund_id)

                  if db_refund do
                    {:ok, _} = Ledgers.link_refund_to_payout(payout, db_refund)

                    Logger.info("[Payout] Successfully linked refund to payout",
                      payout_id: payout.stripe_payout_id,
                      payout_db_id: payout.id,
                      refund_id: db_refund.id,
                      refund_reference_id: db_refund.reference_id,
                      refund_amount: Money.to_string!(db_refund.amount),
                      stripe_refund_id: stripe_refund_id,
                      payment_id: payment.id
                    )

                    :ok
                  else
                    Logger.warning(
                      "[Payout] Refund not found for Stripe refund ID - cannot link to payout",
                      payout_id: payout.stripe_payout_id,
                      payment_id: payment.id,
                      payment_reference_id: payment.reference_id,
                      stripe_refund_id: stripe_refund_id,
                      note: "Refund may not exist in database"
                    )

                    :skipped
                  end
                else
                  Logger.warning("[Payout] Payment not found for refund",
                    payout_id: payout.stripe_payout_id,
                    payment_intent_id: payment_intent_id,
                    stripe_refund_id: stripe_refund_id
                  )

                  :skipped
                end
              else
                Logger.warning(
                  "[Payout] Charge has no payment_intent for refund",
                  payout_id: payout.stripe_payout_id,
                  charge_id: charge_id,
                  stripe_refund_id: stripe_refund_id
                )

                :skipped
              end

            {:error, reason} ->
              Logger.warning("Failed to retrieve charge for refund",
                charge_id: charge_id,
                error: inspect(reason)
              )

              :skipped
          end
        else
          Logger.warning("[Payout] Refund has no charge",
            payout_id: payout.stripe_payout_id,
            stripe_refund_id: stripe_refund_id
          )

          :skipped
        end
      else
        :skipped
      end
    rescue
      error ->
        Logger.error("Exception while linking refund to payout",
          stripe_refund_id: stripe_refund_id,
          error: Exception.message(error),
          error_type: error.__struct__,
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Report to Sentry for visibility
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            stripe_refund_id: stripe_refund_id,
            function: "link_stripe_refund_to_payout"
          }
        )

        :skipped
    end
  end

  # Helper function to get membership type from subscription ID
  defp get_membership_type_from_subscription_id(subscription_id) do
    require Logger

    # Try to get subscription from our database first
    case Subscriptions.get_subscription_by_stripe_id(subscription_id) do
      nil ->
        # If not in database, try to get from Stripe API
        get_membership_type_from_stripe_subscription(subscription_id)

      subscription ->
        subscription = Repo.preload(subscription, :subscription_items)

        membership_type =
          case subscription.subscription_items do
            [item | _] ->
              membership_plans =
                Application.get_env(:ysc, :membership_plans, [])

              case Enum.find(
                     membership_plans,
                     &(&1.stripe_price_id == item.stripe_price_id)
                   ) do
                %{id: plan_id} when plan_id in [:family, "family"] -> :family
                _ -> :single
              end

            _ ->
              :single
          end

        Logger.debug("Membership type determined from database subscription",
          subscription_id: subscription_id,
          membership_type: membership_type
        )

        membership_type
    end
  end

  # Helper function to get membership type from Stripe subscription API
  defp get_membership_type_from_stripe_subscription(subscription_id) do
    require Logger

    case Stripe.Subscription.retrieve(subscription_id,
           expand: ["items.data.price"]
         ) do
      {:ok, stripe_subscription} ->
        membership_type =
          case stripe_subscription.items.data do
            [item | _] ->
              price_id = item.price.id

              membership_plans =
                Application.get_env(:ysc, :membership_plans, [])

              case Enum.find(
                     membership_plans,
                     &(&1.stripe_price_id == price_id)
                   ) do
                %{id: plan_id} when plan_id in [:family, "family"] -> :family
                _ -> :single
              end

            _ ->
              :single
          end

        Logger.debug("Membership type determined from Stripe subscription",
          subscription_id: subscription_id,
          membership_type: membership_type
        )

        membership_type

      {:error, reason} ->
        Logger.warning(
          "Failed to retrieve subscription from Stripe, defaulting to single",
          subscription_id: subscription_id,
          error: inspect(reason)
        )

        :single
    end
  end

  # Helper function to send membership renewal success email
  defp send_membership_renewal_success_email(
         user,
         membership_type,
         amount,
         renewal_date
       ) do
    require Logger

    try do
      email_module = YscWeb.Emails.MembershipRenewalSuccess

      email_data =
        email_module.prepare_email_data(
          user,
          membership_type,
          amount,
          renewal_date
        )

      subject = email_module.get_subject()
      template_name = email_module.get_template_name()

      # Generate idempotency key from user ID and renewal date to prevent duplicate emails
      idempotency_key =
        "membership_renewal_success_#{user.id}_#{Date.to_iso8601(renewal_date)}"

      Logger.info("Sending membership renewal success email",
        user_id: user.id,
        email: user.email,
        membership_type: membership_type,
        amount: Money.to_string!(amount),
        renewal_date: Date.to_iso8601(renewal_date)
      )

      YscWeb.Emails.Notifier.schedule_email(
        user.email,
        idempotency_key,
        subject,
        template_name,
        email_data,
        "",
        user.id
      )
    rescue
      error ->
        Logger.error("Failed to send membership renewal success email",
          user_id: user.id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  # Helper function to send membership payment failure email
  defp send_membership_payment_failure_email(
         user,
         membership_type,
         is_renewal,
         invoice_id
       ) do
    require Logger

    try do
      email_module = YscWeb.Emails.MembershipPaymentFailure

      email_data =
        email_module.prepare_email_data(
          user,
          membership_type,
          is_renewal,
          invoice_id
        )

      subject = email_module.get_subject()
      template_name = email_module.get_template_name()

      # Generate idempotency key from invoice ID to prevent duplicate emails
      idempotency_key = "membership_payment_failure_#{invoice_id}"

      Logger.info("Sending membership payment failure email",
        user_id: user.id,
        email: user.email,
        membership_type: membership_type,
        is_renewal: is_renewal,
        invoice_id: invoice_id
      )

      YscWeb.Emails.Notifier.schedule_email(
        user.email,
        idempotency_key,
        subject,
        template_name,
        email_data,
        "",
        user.id
      )
    rescue
      error ->
        Logger.error("Failed to send membership payment failure email",
          user_id: user.id,
          invoice_id: invoice_id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  # Helper function to enqueue QuickBooks sync for payout only if:
  # 1. All linked payments/refunds are synced
  # 2. Fee_total is populated
  # 3. Linking is complete (at least one payment or refund linked, or none expected)
  defp enqueue_quickbooks_sync_payout_if_ready(%Ledgers.Payout{} = payout) do
    require Logger

    # Reload payout with payments and refunds
    payout = Ledgers.get_payout!(payout.id)

    # Check if fee_total is populated (required for QuickBooks sync)
    fee_total_populated = payout.fee_total != nil

    # Check if all linked payments are synced
    all_payments_synced =
      Enum.all?(payout.payments, fn payment ->
        payment.quickbooks_sync_status == "synced" &&
          payment.quickbooks_sales_receipt_id != nil
      end)

    # Check if all linked refunds are synced
    all_refunds_synced =
      Enum.all?(payout.refunds, fn refund ->
        refund.quickbooks_sync_status == "synced" &&
          refund.quickbooks_sales_receipt_id != nil
      end)

    # Check if we have at least one payment or refund linked (or none expected)
    # If we have payments/refunds, they must all be synced
    has_transactions = payout.payments != [] || payout.refunds != []

    linking_complete =
      if has_transactions,
        do: all_payments_synced && all_refunds_synced,
        else: true

    if fee_total_populated && linking_complete do
      Logger.info("Payout ready for QuickBooks sync - all conditions met",
        payout_id: payout.id,
        payments_count: length(payout.payments),
        refunds_count: length(payout.refunds),
        fee_total:
          if(payout.fee_total,
            do: Money.to_string!(payout.fee_total),
            else: "not set"
          ),
        all_payments_synced: all_payments_synced,
        all_refunds_synced: all_refunds_synced
      )

      # Mark payout as pending sync
      payout
      |> Ledgers.Payout.changeset(%{quickbooks_sync_status: "pending"})
      |> Ysc.Repo.update()

      # Enqueue sync job
      %{payout_id: to_string(payout.id)}
      |> YscWeb.Workers.QuickbooksSyncPayoutWorker.new()
      |> Oban.insert()

      :ok
    else
      unsynced_payments =
        Enum.count(payout.payments, &(&1.quickbooks_sync_status != "synced"))

      unsynced_refunds =
        Enum.count(payout.refunds, &(&1.quickbooks_sync_status != "synced"))

      Logger.info(
        "Payout not ready for QuickBooks sync - waiting for conditions to be met",
        payout_id: payout.id,
        fee_total_populated: fee_total_populated,
        unsynced_payments: unsynced_payments,
        unsynced_refunds: unsynced_refunds,
        total_payments: length(payout.payments),
        total_refunds: length(payout.refunds),
        all_payments_synced: all_payments_synced,
        all_refunds_synced: all_refunds_synced
      )

      :ok
    end
  rescue
    error ->
      require Logger

      Logger.error("Failed to check if payout is ready for QuickBooks sync",
        payout_id: payout.id,
        error: inspect(error)
      )

      :ok
  end
end
