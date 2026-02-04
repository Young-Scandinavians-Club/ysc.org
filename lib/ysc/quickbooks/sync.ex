defmodule Ysc.Quickbooks.Sync do
  @moduledoc """
  Handles syncing Payment, Refund, and Payout records to QuickBooks.

  This module provides functions to sync ledger records to QuickBooks Online,
  mapping entity types to the appropriate QuickBooks accounts and classes.
  """

  require Logger
  alias Ysc.Repo
  alias Ysc.Ledgers.{Payment, Refund, Payout, LedgerEntry}
  alias Ysc.Quickbooks
  alias Ysc.Accounts.User
  alias Ysc.Bookings
  alias Ysc.Subscriptions
  alias YscWeb.Workers.QuickbooksSyncPayoutWorker
  import Ecto.Query

  # Helper to get the configured QuickBooks client module (for testing with mocks)
  defp client_module do
    Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)
  end

  # QuickBooks Account and Class mappings
  @account_class_mapping %{
    # Event tickets
    event: %{account: "Events Inc", class: "Events"},
    # Donations
    donation: %{account: "Donations", class: "Administration"},
    # Clear Lake bookings
    clear_lake_booking: %{account: "Clear Lake Inc", class: "Clear Lake"},
    # Tahoe bookings
    tahoe_booking: %{account: "Tahoe Inc", class: "Tahoe"},
    # Stripe fees
    stripe_fee: %{account: "Stripe Fees", class: "Administration"}
  }

  @doc """
  Syncs a payment to QuickBooks as a SalesReceipt.

  Returns {:ok, sales_receipt} on success, {:error, reason} on failure.
  """
  @spec sync_payment(Payment.t()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def sync_payment(%Payment{} = payment) do
    Logger.debug("[QB Sync] Starting sync_payment",
      payment_id: payment.id,
      reference_id: payment.reference_id,
      amount: inspect(payment.amount),
      sync_status: payment.quickbooks_sync_status,
      sales_receipt_id: payment.quickbooks_sales_receipt_id,
      user_id: payment.user_id
    )

    # Check if already synced
    if payment.quickbooks_sync_status == "synced" &&
         payment.quickbooks_sales_receipt_id do
      Logger.info("[QB Sync] Payment already synced to QuickBooks",
        payment_id: payment.id,
        sales_receipt_id: payment.quickbooks_sales_receipt_id
      )

      # Even if already synced, check if any payouts are now ready to sync
      Logger.debug("[QB Sync] Checking for payouts to sync after payment",
        payment_id: payment.id
      )

      check_and_enqueue_payout_syncs_for_payment(payment)

      {:ok, %{"Id" => payment.quickbooks_sales_receipt_id}}
    else
      Logger.debug("[QB Sync] Payment not yet synced, proceeding with sync",
        payment_id: payment.id,
        current_status: payment.quickbooks_sync_status
      )

      do_sync_payment(payment)
    end
  end

  @doc """
  Syncs a refund to QuickBooks as a SalesReceipt (negative amount).

  Returns {:ok, sales_receipt} on success, {:error, reason} on failure.
  """
  @spec sync_refund(Refund.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def sync_refund(%Refund{} = refund) do
    Logger.debug("[QB Sync] Starting sync_refund",
      refund_id: refund.id,
      reference_id: refund.reference_id,
      amount: inspect(refund.amount),
      sync_status: refund.quickbooks_sync_status,
      sales_receipt_id: refund.quickbooks_sales_receipt_id,
      payment_id: refund.payment_id
    )

    # Check if already synced
    if refund.quickbooks_sync_status == "synced" &&
         refund.quickbooks_sales_receipt_id do
      Logger.info("[QB Sync] Refund already synced to QuickBooks",
        refund_id: refund.id,
        sales_receipt_id: refund.quickbooks_sales_receipt_id
      )

      # Even if already synced, check if any payouts are now ready to sync
      Logger.debug("[QB Sync] Checking for payouts to sync after refund",
        refund_id: refund.id
      )

      check_and_enqueue_payout_syncs_for_refund(refund)

      {:ok, %{"Id" => refund.quickbooks_sales_receipt_id}}
    else
      Logger.debug("[QB Sync] Refund not yet synced, proceeding with sync",
        refund_id: refund.id,
        current_status: refund.quickbooks_sync_status
      )

      do_sync_refund(refund)
    end
  end

  @doc """
  Syncs a payout to QuickBooks as a Deposit.

  Returns {:ok, deposit} on success, {:error, reason} on failure.
  """
  @spec sync_payout(Payout.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def sync_payout(%Payout{} = payout) do
    Logger.debug("[QB Sync] Starting sync_payout",
      payout_id: payout.id,
      stripe_payout_id: payout.stripe_payout_id,
      amount: inspect(payout.amount),
      sync_status: payout.quickbooks_sync_status,
      deposit_id: payout.quickbooks_deposit_id,
      arrival_date: payout.arrival_date
    )

    # Check if already synced
    if payout.quickbooks_sync_status == "synced" && payout.quickbooks_deposit_id do
      Logger.info("[QB Sync] Payout already synced to QuickBooks",
        payout_id: payout.id,
        deposit_id: payout.quickbooks_deposit_id
      )

      {:ok, %{"Id" => payout.quickbooks_deposit_id}}
    else
      Logger.debug("[QB Sync] Payout not yet synced, proceeding with sync",
        payout_id: payout.id,
        current_status: payout.quickbooks_sync_status
      )

      do_sync_payout(payout)
    end
  end

  # Private functions

  defp do_sync_payment(%Payment{} = payment) do
    Logger.debug("[QB Sync] do_sync_payment: Starting payment sync process",
      payment_id: payment.id
    )

    # Reload payment to ensure we have the latest state
    Logger.debug("[QB Sync] do_sync_payment: Reloading payment from database",
      payment_id: payment.id
    )

    payment = Repo.reload!(payment)

    # Mark as attempting sync
    Logger.debug("[QB Sync] do_sync_payment: Marking payment as pending sync",
      payment_id: payment.id
    )

    update_sync_status(payment, "pending", nil, nil)

    # Reload again after status update to ensure we have the updated payment
    Logger.debug(
      "[QB Sync] do_sync_payment: Reloading payment after status update",
      payment_id: payment.id
    )

    payment = Repo.reload!(payment)

    Logger.debug("[QB Sync] do_sync_payment: Starting sync pipeline",
      payment_id: payment.id,
      user_id: payment.user_id
    )

    with {:ok, user} <- get_user(payment.user_id),
         {:ok, customer_id} <- get_or_create_customer(user),
         {:ok, entity_info} <- get_payment_entity_info(payment),
         {:ok, item_id} <- get_item_id_for_entity(entity_info),
         {:ok, sales_receipt} <-
           create_payment_sales_receipt(
             payment,
             customer_id,
             item_id,
             entity_info
           ) do
      sales_receipt_id = Map.get(sales_receipt, "Id")

      Logger.debug(
        "[QB Sync] do_sync_payment: Sales receipt created successfully",
        payment_id: payment.id,
        sales_receipt_id: sales_receipt_id,
        sales_receipt: inspect(sales_receipt, limit: :infinity)
      )

      # Update payment with sync success
      Logger.debug(
        "[QB Sync] do_sync_payment: Updating payment with sync success",
        payment_id: payment.id,
        sales_receipt_id: sales_receipt_id
      )

      update_sync_success(payment, sales_receipt_id, sales_receipt)

      Logger.info("[QB Sync] Successfully synced payment to QuickBooks",
        payment_id: payment.id,
        sales_receipt_id: sales_receipt_id
      )

      # Check if any payouts are now ready to sync
      Logger.debug("[QB Sync] do_sync_payment: Checking for payouts to sync",
        payment_id: payment.id
      )

      check_and_enqueue_payout_syncs_for_payment(payment)

      {:ok, sales_receipt}
    else
      {:error, reason} = error ->
        Logger.warning(
          "[QB Sync] do_sync_payment: Sync failed in pipeline - Error: #{inspect(reason)}, Payment ID: #{payment.id}, Reference ID: #{payment.reference_id}, User ID: #{payment.user_id}",
          payment_id: payment.id,
          payment_reference_id: payment.reference_id,
          error_reason: reason,
          error_type: inspect(reason),
          full_error: inspect(error),
          user_id: payment.user_id
        )

        # Report to Sentry
        Sentry.capture_message("QuickBooks payment sync failed",
          level: :error,
          extra: %{
            payment_id: payment.id,
            payment_reference_id: payment.reference_id,
            user_id: payment.user_id,
            amount: Money.to_string!(payment.amount),
            error: inspect(reason)
          },
          tags: %{
            quickbooks_operation: "sync_payment",
            error_type: inspect(reason)
          }
        )

        # Update payment with sync failure
        update_sync_failure(payment, reason)
        error
    end
  end

  defp do_sync_refund(%Refund{} = refund) do
    Logger.debug("[QB Sync] do_sync_refund: Starting refund sync process",
      refund_id: refund.id,
      payment_id: refund.payment_id
    )

    # Mark as attempting sync
    Logger.debug("[QB Sync] do_sync_refund: Marking refund as pending sync",
      refund_id: refund.id
    )

    update_sync_status_refund(refund, "pending", nil, nil)

    Logger.debug("[QB Sync] do_sync_refund: Starting sync pipeline",
      refund_id: refund.id,
      payment_id: refund.payment_id
    )

    with {:ok, payment} <- get_payment(refund.payment_id),
         {:ok, user} <- get_user(payment.user_id),
         {:ok, customer_id} <- get_or_create_customer(user),
         {:ok, entity_info} <- get_payment_entity_info(payment),
         {:ok, item_id} <- get_quickbooks_item_id(entity_info),
         {:ok, refund_receipt} <-
           create_refund_sales_receipt(
             refund,
             customer_id,
             item_id,
             entity_info
           ) do
      refund_receipt_id = Map.get(refund_receipt, "Id")

      Logger.debug(
        "[QB Sync] do_sync_refund: Refund receipt created successfully",
        refund_id: refund.id,
        refund_receipt_id: refund_receipt_id,
        refund_receipt: inspect(refund_receipt, limit: :infinity)
      )

      # Update refund with sync success
      Logger.debug(
        "[QB Sync] do_sync_refund: Updating refund with sync success",
        refund_id: refund.id,
        refund_receipt_id: refund_receipt_id
      )

      update_sync_success_refund(refund, refund_receipt_id, refund_receipt)

      Logger.info("[QB Sync] Successfully synced refund to QuickBooks",
        refund_id: refund.id,
        refund_receipt_id: refund_receipt_id
      )

      # Check if any payouts are now ready to sync
      Logger.debug("[QB Sync] do_sync_refund: Checking for payouts to sync",
        refund_id: refund.id
      )

      check_and_enqueue_payout_syncs_for_refund(refund)

      {:ok, refund_receipt}
    else
      {:error, reason} = error ->
        Logger.warning(
          "[QB Sync] do_sync_refund: Sync failed in pipeline - Error: #{inspect(reason)}, Refund ID: #{refund.id}, Reference ID: #{refund.reference_id}, Payment ID: #{refund.payment_id}",
          refund_id: refund.id,
          refund_reference_id: refund.reference_id,
          error_reason: reason,
          error_type: inspect(reason),
          full_error: inspect(error),
          payment_id: refund.payment_id
        )

        # Report to Sentry
        Sentry.capture_message("QuickBooks refund sync failed",
          level: :error,
          extra: %{
            refund_id: refund.id,
            refund_reference_id: refund.reference_id,
            payment_id: refund.payment_id,
            amount: Money.to_string!(refund.amount),
            error: inspect(reason)
          },
          tags: %{
            quickbooks_operation: "sync_refund",
            error_type: inspect(reason)
          }
        )

        # Update refund with sync failure
        update_sync_failure_refund(refund, reason)
        error
    end
  end

  defp do_sync_payout(%Payout{} = payout) do
    Logger.debug("[QB Sync] do_sync_payout: Starting payout sync process",
      payout_id: payout.id
    )

    # Mark as attempting sync
    Logger.debug("[QB Sync] do_sync_payout: Marking payout as pending sync",
      payout_id: payout.id
    )

    update_sync_status_payout(payout, "pending", nil, nil)

    # Load payout with payments and refunds
    Logger.debug(
      "[QB Sync] do_sync_payout: Loading payout with payments and refunds",
      payout_id: payout.id
    )

    # Reload payout fresh from database first, then preload associations
    # This ensures we don't have stale struct with empty associations
    payout = Repo.get!(Payout, payout.id)
    payout = Repo.preload(payout, [:payments, :refunds])

    Logger.info("[QB Sync] do_sync_payout: Loaded payout data",
      payout_id: payout.id,
      stripe_payout_id: payout.stripe_payout_id,
      payout_amount: Money.to_string!(payout.amount),
      fee_total:
        if(payout.fee_total, do: Money.to_string!(payout.fee_total), else: nil),
      payments_count: length(payout.payments),
      refunds_count: length(payout.refunds),
      payment_ids: Enum.map(payout.payments, & &1.id),
      payment_reference_ids: Enum.map(payout.payments, & &1.reference_id),
      refund_ids: Enum.map(payout.refunds, & &1.id),
      refund_reference_ids: Enum.map(payout.refunds, & &1.reference_id),
      quickbooks_sync_status: payout.quickbooks_sync_status
    )

    # Verify all linked payments and refunds are synced before proceeding
    Logger.debug(
      "[QB Sync] do_sync_payout: Verifying all transactions are synced",
      payout_id: payout.id
    )

    with :ok <- verify_all_transactions_synced(payout),
         {:ok, deposit} <- create_payout_deposit(payout) do
      deposit_id = Map.get(deposit, "Id")

      Logger.debug("[QB Sync] do_sync_payout: Deposit created successfully",
        payout_id: payout.id,
        deposit_id: deposit_id,
        deposit: inspect(deposit, limit: :infinity)
      )

      # Update payout with sync success
      Logger.debug(
        "[QB Sync] do_sync_payout: Updating payout with sync success",
        payout_id: payout.id,
        deposit_id: deposit_id
      )

      update_sync_success_payout(payout, deposit_id, deposit)

      Logger.info("[QB Sync] Successfully synced payout to QuickBooks",
        payout_id: payout.id,
        deposit_id: deposit_id,
        payments_count: length(payout.payments),
        refunds_count: length(payout.refunds)
      )

      {:ok, deposit}
    else
      {:error, reason} = error ->
        Logger.warning(
          "[QB Sync] do_sync_payout: Sync failed in pipeline - Error: #{inspect(reason)}, Payout ID: #{payout.id}, Stripe Payout ID: #{inspect(payout.stripe_payout_id)}, Payments: #{length(payout.payments)}, Refunds: #{length(payout.refunds)}",
          payout_id: payout.id,
          stripe_payout_id: payout.stripe_payout_id,
          error_reason: reason,
          error_type: inspect(reason),
          full_error: inspect(error),
          payments_count: length(payout.payments),
          refunds_count: length(payout.refunds)
        )

        # Report to Sentry
        Sentry.capture_message("QuickBooks payout sync failed",
          level: :error,
          extra: %{
            payout_id: payout.id,
            stripe_payout_id: payout.stripe_payout_id,
            amount: Money.to_string!(payout.amount),
            payments_count: length(payout.payments),
            refunds_count: length(payout.refunds),
            error: inspect(reason)
          },
          tags: %{
            quickbooks_operation: "sync_payout",
            error_type: inspect(reason)
          }
        )

        # Update payout with sync failure
        update_sync_failure_payout(payout, reason)
        error
    end
  end

  defp get_user(nil) do
    Logger.debug("[QB Sync] get_user: user_id is nil")
    {:error, :user_not_found}
  end

  defp get_user(user_id) do
    Logger.debug("[QB Sync] get_user: Fetching user",
      user_id: user_id
    )

    case Repo.get(User, user_id) do
      nil ->
        Logger.warning("[QB Sync] get_user: User not found",
          user_id: user_id
        )

        {:error, :user_not_found}

      user ->
        Logger.debug("[QB Sync] get_user: User found",
          user_id: user_id,
          user_email: user.email
        )

        {:ok, user}
    end
  end

  defp get_payment(payment_id) do
    Logger.debug("[QB Sync] get_payment: Fetching payment",
      payment_id: payment_id
    )

    case Repo.get(Payment, payment_id) do
      nil ->
        Logger.warning("[QB Sync] get_payment: Payment not found",
          payment_id: payment_id
        )

        {:error, :payment_not_found}

      payment ->
        Logger.debug("[QB Sync] get_payment: Payment found",
          payment_id: payment_id,
          reference_id: payment.reference_id,
          amount: inspect(payment.amount)
        )

        {:ok, payment}
    end
  end

  defp get_or_create_customer(user) do
    Logger.debug(
      "[QB Sync] get_or_create_customer: Getting or creating QuickBooks customer",
      user_id: user.id,
      user_email: user.email,
      existing_quickbooks_customer_id: user.quickbooks_customer_id
    )

    case Quickbooks.get_or_create_customer(user) do
      {:ok, customer_id} ->
        Logger.debug("[QB Sync] get_or_create_customer: Customer ID obtained",
          user_id: user.id,
          customer_id: customer_id
        )

        {:ok, customer_id}

      {:error, reason} = error ->
        Logger.warning(
          "[QB Sync] get_or_create_customer: Failed to get or create customer - Error: #{inspect(reason)}, User ID: #{user.id}, Email: #{user.email}, Existing QB Customer ID: #{inspect(user.quickbooks_customer_id)}",
          user_id: user.id,
          user_email: user.email,
          existing_quickbooks_customer_id: user.quickbooks_customer_id,
          error_reason: reason,
          error_type: inspect(reason),
          full_error: inspect(error)
        )

        # Report to Sentry
        Sentry.capture_message("QuickBooks customer creation failed",
          level: :error,
          extra: %{
            user_id: user.id,
            user_email: user.email,
            existing_quickbooks_customer_id: user.quickbooks_customer_id,
            error: inspect(reason)
          },
          tags: %{
            quickbooks_operation: "get_or_create_customer",
            error_type: inspect(reason)
          }
        )

        error

      error ->
        Logger.warning(
          "[QB Sync] get_or_create_customer: Failed to get or create customer (unexpected error format) - Error: #{inspect(error)}, User ID: #{user.id}, Email: #{user.email}",
          user_id: user.id,
          user_email: user.email,
          full_error: inspect(error)
        )

        # Report to Sentry
        Sentry.capture_message(
          "QuickBooks customer creation failed (unexpected error)",
          level: :error,
          extra: %{
            user_id: user.id,
            user_email: user.email,
            error: inspect(error)
          },
          tags: %{
            quickbooks_operation: "get_or_create_customer",
            error_type: "unexpected_error_format"
          }
        )

        error
    end
  end

  defp get_payment_entity_info(%Payment{} = payment) do
    Logger.debug(
      "[QB Sync] get_payment_entity_info: Fetching entity info for payment",
      payment_id: payment.id
    )

    # Get all revenue entries for this payment to detect mixed event/donation payments
    entries =
      from(e in LedgerEntry,
        join: a in assoc(e, :account),
        where: e.payment_id == ^payment.id,
        where: e.debit_credit == "credit",
        where:
          e.related_entity_type in ^[
            "event",
            "booking",
            "donation",
            "membership"
          ],
        where: a.account_type == "revenue",
        order_by: [desc: e.inserted_at],
        preload: [:account]
      )
      |> Repo.all()

    Logger.debug("[QB Sync] get_payment_entity_info: Found revenue entries",
      payment_id: payment.id,
      entries_count: length(entries),
      entry_types: Enum.map(entries, fn e -> e.related_entity_type end)
    )

    # Check if we have both event and donation entries (mixed payment)
    event_entry =
      Enum.find(entries, fn e -> e.related_entity_type in [:event, "event"] end)

    donation_entry =
      Enum.find(entries, fn e ->
        e.related_entity_type in [:donation, "donation"]
      end)

    Logger.debug("[QB Sync] get_payment_entity_info: Entry analysis",
      payment_id: payment.id,
      has_event_entry: !is_nil(event_entry),
      has_donation_entry: !is_nil(donation_entry)
    )

    result =
      cond do
        # Mixed event/donation payment
        event_entry && donation_entry ->
          Logger.debug(
            "[QB Sync] get_payment_entity_info: Detected mixed event/donation payment",
            payment_id: payment.id,
            event_amount: inspect(event_entry.amount),
            donation_amount: inspect(donation_entry.amount)
          )

          {:ok,
           %{
             entity_type: :mixed_event_donation,
             property: nil,
             event_entry: event_entry,
             donation_entry: donation_entry,
             entries: entries
           }}

        # Single entity type payment
        event_entry ->
          entity_type =
            case event_entry.related_entity_type do
              atom when is_atom(atom) -> atom
              string when is_binary(string) -> String.to_existing_atom(string)
            end

          Logger.debug(
            "[QB Sync] get_payment_entity_info: Detected event entry",
            payment_id: payment.id,
            entity_type: entity_type
          )

          property =
            if entity_type == :booking do
              Logger.debug(
                "[QB Sync] get_payment_entity_info: Determining booking property",
                payment_id: payment.id
              )

              determine_booking_property(payment)
            else
              nil
            end

          Logger.debug(
            "[QB Sync] get_payment_entity_info: Event entity info determined",
            payment_id: payment.id,
            entity_type: entity_type,
            property: property
          )

          {:ok,
           %{entity_type: entity_type, property: property, entry: event_entry}}

        donation_entry ->
          entity_type =
            case donation_entry.related_entity_type do
              atom when is_atom(atom) -> atom
              string when is_binary(string) -> String.to_existing_atom(string)
            end

          Logger.debug(
            "[QB Sync] get_payment_entity_info: Detected donation entry",
            payment_id: payment.id,
            entity_type: entity_type
          )

          {:ok,
           %{entity_type: entity_type, property: nil, entry: donation_entry}}

        # Try to find any revenue entry
        entry = List.first(entries) ->
          entity_type =
            case entry.related_entity_type do
              atom when is_atom(atom) -> atom
              string when is_binary(string) -> String.to_existing_atom(string)
            end

          Logger.debug(
            "[QB Sync] get_payment_entity_info: Using first revenue entry",
            payment_id: payment.id,
            entity_type: entity_type
          )

          property =
            if entity_type == :booking do
              Logger.debug(
                "[QB Sync] get_payment_entity_info: Determining booking property",
                payment_id: payment.id
              )

              determine_booking_property(payment)
            else
              nil
            end

          {:ok, %{entity_type: entity_type, property: property, entry: entry}}

        # Check for membership entry
        membership_entry =
            Enum.find(entries, fn e ->
              e.related_entity_type in [:membership, "membership"]
            end) ->
          entity_type =
            case membership_entry.related_entity_type do
              atom when is_atom(atom) -> atom
              string when is_binary(string) -> String.to_existing_atom(string)
            end

          Logger.debug(
            "[QB Sync] get_payment_entity_info: Detected membership entry",
            payment_id: payment.id,
            entity_type: entity_type,
            entity_id: membership_entry.related_entity_id
          )

          # Get membership type (single vs family) from subscription
          membership_type =
            get_membership_type_from_entity_id(
              membership_entry.related_entity_id
            )

          Logger.debug(
            "[QB Sync] get_payment_entity_info: Membership type determined",
            payment_id: payment.id,
            membership_type: membership_type
          )

          {:ok,
           %{
             entity_type: entity_type,
             property: membership_type,
             entry: membership_entry
           }}

        # Default to membership if no entity type found
        true ->
          Logger.debug(
            "[QB Sync] get_payment_entity_info: No entity type found, defaulting to membership",
            payment_id: payment.id
          )

          {:ok, %{entity_type: :membership, property: :single, entry: nil}}
      end

    Logger.debug("[QB Sync] get_payment_entity_info: Final result",
      payment_id: payment.id,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  defp get_membership_type_from_entity_id(nil), do: :single

  defp get_membership_type_from_entity_id(subscription_id) do
    Logger.debug(
      "[QB Sync] get_membership_type_from_entity_id: Getting membership type",
      subscription_id: subscription_id
    )

    case Subscriptions.get_subscription(subscription_id) do
      {:ok, subscription} ->
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

        Logger.debug(
          "[QB Sync] get_membership_type_from_entity_id: Membership type determined",
          subscription_id: subscription_id,
          membership_type: membership_type
        )

        membership_type

      _ ->
        Logger.debug(
          "[QB Sync] get_membership_type_from_entity_id: Subscription not found, defaulting to single",
          subscription_id: subscription_id
        )

        :single
    end
  end

  defp determine_booking_property(%Payment{} = payment) do
    Logger.debug(
      "[QB Sync] determine_booking_property: Determining property for booking",
      payment_id: payment.id
    )

    # First, try to get the booking from ledger entries
    booking_entry =
      from(e in LedgerEntry,
        where: e.payment_id == ^payment.id,
        where: e.related_entity_type == :booking,
        limit: 1
      )
      |> Repo.one()

    result =
      if booking_entry && booking_entry.related_entity_id do
        Logger.debug(
          "[QB Sync] determine_booking_property: Found booking entry, fetching booking",
          payment_id: payment.id,
          booking_id: booking_entry.related_entity_id
        )

        try do
          booking = Bookings.get_booking!(booking_entry.related_entity_id)

          Logger.debug(
            "[QB Sync] determine_booking_property: Got booking, using property field",
            payment_id: payment.id,
            booking_id: booking.id,
            property: booking.property
          )

          # Convert atom property to our expected format
          case booking.property do
            :tahoe ->
              :tahoe

            :clear_lake ->
              :clear_lake

            _ ->
              Logger.warning(
                "[QB Sync] determine_booking_property: Unknown booking property, falling back to account check",
                payment_id: payment.id,
                booking_property: booking.property
              )

              nil
          end
        rescue
          Ecto.NoResultsError ->
            Logger.warning(
              "[QB Sync] determine_booking_property: Booking not found, falling back to account check",
              payment_id: payment.id,
              booking_id: booking_entry.related_entity_id
            )

            nil
        end
      else
        Logger.debug(
          "[QB Sync] determine_booking_property: No booking entry found, checking account names",
          payment_id: payment.id
        )

        nil
      end

    # If we couldn't determine from booking, check account names
    result =
      if is_nil(result) do
        Logger.debug(
          "[QB Sync] determine_booking_property: Checking ledger account names",
          payment_id: payment.id
        )

        entries =
          from(e in LedgerEntry,
            join: a in assoc(e, :account),
            where: e.payment_id == ^payment.id,
            where:
              a.name in ["tahoe_booking_revenue", "clear_lake_booking_revenue"],
            preload: [account: a]
          )
          |> Repo.all()

        Logger.debug(
          "[QB Sync] determine_booking_property: Found entries with account names",
          payment_id: payment.id,
          entries_count: length(entries),
          account_names: Enum.map(entries, fn e -> e.account.name end)
        )

        case entries do
          [%{account: %{name: "tahoe_booking_revenue"}} | _] ->
            Logger.debug(
              "[QB Sync] determine_booking_property: Determined as Tahoe from account name",
              payment_id: payment.id
            )

            :tahoe

          [%{account: %{name: "clear_lake_booking_revenue"}} | _] ->
            Logger.debug(
              "[QB Sync] determine_booking_property: Determined as Clear Lake from account name",
              payment_id: payment.id
            )

            :clear_lake

          _ ->
            Logger.warning(
              "[QB Sync] determine_booking_property: Could not determine property",
              payment_id: payment.id
            )

            nil
        end
      else
        result
      end

    Logger.debug("[QB Sync] determine_booking_property: Final result",
      payment_id: payment.id,
      property: result
    )

    result
  end

  defp get_item_id_for_entity(%{entity_type: :mixed_event_donation}) do
    Logger.debug(
      "[QB Sync] get_item_id_for_entity: Mixed event/donation payment, item_id not needed"
    )

    # For mixed payments, item_id is not needed (handled in create_payment_sales_receipt)
    {:ok, nil}
  end

  defp get_item_id_for_entity(entity_info) do
    Logger.debug("[QB Sync] get_item_id_for_entity: Getting item ID for entity",
      entity_type: entity_info.entity_type,
      property: entity_info.property
    )

    get_quickbooks_item_id(entity_info)
  end

  defp get_quickbooks_item_id(%{entity_type: entity_type, property: property}) do
    Logger.debug("[QB Sync] get_quickbooks_item_id: Getting or creating item",
      entity_type: entity_type,
      property: property
    )

    item_name = determine_item_name(entity_type, property)

    Logger.debug("[QB Sync] get_quickbooks_item_id: Item name determined",
      entity_type: entity_type,
      property: property,
      item_name: item_name
    )

    config_key = determine_config_key(entity_type, property)

    case Application.get_env(:ysc, :quickbooks, [])[config_key] do
      nil ->
        get_or_create_item_via_api(item_name, entity_type, property)

      configured_item_id ->
        Logger.debug(
          "[QB Sync] get_quickbooks_item_id: Using configured item ID override",
          item_name: item_name,
          item_id: configured_item_id
        )

        {:ok, configured_item_id}
    end
  end

  defp determine_item_name(entity_type, property) do
    case {entity_type, property} do
      {:event, _} -> "Event Tickets"
      {:donation, _} -> "Donations"
      {:booking, :tahoe} -> "Tahoe Bookings"
      {:booking, :clear_lake} -> "Clear Lake Bookings"
      {:membership, :family} -> "Family Membership"
      {:membership, :single} -> "Single Membership"
      {:membership, _} -> "Single Membership"
      _ -> "General Revenue"
    end
  end

  defp determine_config_key(entity_type, property) do
    case {entity_type, property} do
      {:event, _} -> :event_item_id
      {:donation, _} -> :donation_item_id
      {:booking, :tahoe} -> :tahoe_booking_item_id
      {:booking, :clear_lake} -> :clear_lake_booking_item_id
      {:membership, :family} -> :family_membership_item_id
      {:membership, :single} -> :single_membership_item_id
      {:membership, _} -> :single_membership_item_id
      _ -> :default_item_id
    end
  end

  defp get_or_create_item_via_api(item_name, entity_type, property) do
    Logger.debug(
      "[QB Sync] get_quickbooks_item_id: No config override, getting/creating via API",
      item_name: item_name
    )

    income_account_name = determine_income_account_name(entity_type, property)

    Logger.debug("[QB Sync] get_quickbooks_item_id: Getting income account",
      income_account_name: income_account_name
    )

    income_account_ref = query_income_account(income_account_name)

    case client_module().get_or_create_item(item_name,
           income_account_ref: income_account_ref
         ) do
      {:ok, item_id} ->
        Logger.debug(
          "[QB Sync] get_quickbooks_item_id: Item ID obtained via API",
          item_name: item_name,
          item_id: item_id
        )

        {:ok, item_id}

      error ->
        Logger.warning(
          "[QB Sync] get_quickbooks_item_id: Failed to get or create item",
          item_name: item_name,
          error: inspect(error)
        )

        error
    end
  end

  defp determine_income_account_name(entity_type, property) do
    case {entity_type, property} do
      {:event, _} -> "Events Inc"
      {:donation, _} -> "Donations"
      {:booking, :tahoe} -> "Tahoe Inc"
      {:booking, :clear_lake} -> "Clear Lake Inc"
      {:membership, _} -> "Membership Revenue"
      _ -> "General Revenue"
    end
  end

  defp query_income_account(income_account_name) do
    case client_module().query_account_by_name(income_account_name) do
      {:ok, account_id} ->
        Logger.debug("[QB Sync] get_quickbooks_item_id: Found income account",
          account_name: income_account_name,
          account_id: account_id
        )

        %{value: account_id}

      {:error, :not_found} ->
        Logger.warning(
          "[QB Sync] get_quickbooks_item_id: Income account not found, item creation may fail",
          account_name: income_account_name
        )

        nil

      error ->
        Logger.warning(
          "[QB Sync] get_quickbooks_item_id: Failed to query income account, item creation may fail",
          account_name: income_account_name,
          error: inspect(error)
        )

        nil
    end
  end

  defp get_account_and_class(%{entity_type: entity_type, property: property}) do
    Logger.debug("[QB Sync] get_account_and_class: Getting account and class",
      entity_type: entity_type,
      property: property
    )

    result =
      case {entity_type, property} do
        {:event, _} ->
          @account_class_mapping[:event]

        {:donation, _} ->
          @account_class_mapping[:donation]

        {:booking, :tahoe} ->
          @account_class_mapping[:tahoe_booking]

        {:booking, :clear_lake} ->
          @account_class_mapping[:clear_lake_booking]

        {:membership, _} ->
          %{account: "Membership Revenue", class: "Administration"}

        _ ->
          %{account: nil, class: "Administration"}
      end

    Logger.debug("[QB Sync] get_account_and_class: Result",
      entity_type: entity_type,
      property: property,
      account: result && result.account,
      class: result && result.class
    )

    result
  end

  defp create_payment_sales_receipt(payment, customer_id, item_id, entity_info) do
    Logger.debug(
      "[QB Sync] create_payment_sales_receipt: Creating sales receipt",
      payment_id: payment.id,
      customer_id: customer_id,
      item_id: item_id,
      entity_type: entity_info.entity_type
    )

    # Handle mixed event/donation payments with separate line items
    if entity_info.entity_type == :mixed_event_donation do
      Logger.debug(
        "[QB Sync] create_payment_sales_receipt: Creating mixed payment sales receipt",
        payment_id: payment.id
      )

      create_mixed_payment_sales_receipt(payment, customer_id, entity_info)
    else
      Logger.debug(
        "[QB Sync] create_payment_sales_receipt: Creating single entity payment sales receipt",
        payment_id: payment.id,
        entity_type: entity_info.entity_type
      )

      # Single entity type payment - use existing logic
      # Money.to_decimal returns dollars (database stores amounts in dollars)
      amount =
        Money.to_decimal(payment.amount)
        |> Decimal.round(2)

      Logger.debug("[QB Sync] create_payment_sales_receipt: Calculated amount",
        payment_id: payment.id,
        amount_cents: inspect(payment.amount),
        amount_dollars: Decimal.to_string(amount)
      )

      account_class = get_account_and_class(entity_info)

      # Get or create "Undeposited Funds" account for deposit
      deposit_account_ref =
        case client_module().query_account_by_name("Undeposited Funds") do
          {:ok, account_id} ->
            Logger.debug(
              "[QB Sync] create_payment_sales_receipt: Found Undeposited Funds account",
              payment_id: payment.id,
              account_id: account_id
            )

            %{value: account_id, name: "Undeposited Funds"}

          {:error, :not_found} ->
            Logger.warning(
              "[QB Sync] create_payment_sales_receipt: Undeposited Funds account not found, sales receipt may fail",
              payment_id: payment.id
            )

            nil

          error ->
            Logger.warning(
              "[QB Sync] create_payment_sales_receipt: Failed to query Undeposited Funds account",
              payment_id: payment.id,
              error: inspect(error)
            )

            nil
        end

      params = %{
        customer_id: customer_id,
        item_id: item_id,
        quantity: 1,
        unit_price: amount,
        txn_date: payment.payment_date || payment.inserted_at,
        description: "Payment #{payment.reference_id}",
        memo: "Payment: #{payment.reference_id}",
        private_note: "External Payment ID: #{payment.external_payment_id}",
        deposit_to_account_id: deposit_account_ref && deposit_account_ref.value,
        deposit_to_account_name: deposit_account_ref && deposit_account_ref.name
      }

      # Always set a class - get_account_and_class now always returns a class (defaults to "Administration")
      # Query QuickBooks to get the class ID (not just the name)
      class_name = account_class.class

      Logger.debug(
        "[QB Sync] create_payment_sales_receipt: Querying for class ID",
        payment_id: payment.id,
        class_name: class_name
      )

      class_ref =
        case client_module().query_class_by_name(class_name) do
          {:ok, class_id} ->
            Logger.debug(
              "[QB Sync] create_payment_sales_receipt: Found class ID",
              payment_id: payment.id,
              class_name: class_name,
              class_id: class_id
            )

            %{value: class_id, name: class_name}

          {:error, :not_found} ->
            Logger.warning(
              "[QB Sync] create_payment_sales_receipt: Class '#{class_name}' not found, falling back to Administration",
              payment_id: payment.id,
              class_name: class_name
            )

            # Fallback to Administration - ALL exports must have a class
            get_administration_class_ref()

          error ->
            Logger.warning(
              "[QB Sync] create_payment_sales_receipt: Failed to query class, falling back to Administration",
              payment_id: payment.id,
              class_name: class_name,
              error: inspect(error)
            )

            # Fallback to Administration - ALL exports must have a class
            get_administration_class_ref()
        end

      # ALWAYS include class_ref - it's required for all QuickBooks exports
      params = Map.put(params, :class_ref, class_ref)

      Logger.debug(
        "[QB Sync] create_payment_sales_receipt: Calling Quickbooks.create_purchase_sales_receipt",
        payment_id: payment.id,
        params: inspect(params, limit: :infinity)
      )

      result = Quickbooks.create_purchase_sales_receipt(params)

      Logger.debug(
        "[QB Sync] create_payment_sales_receipt: Quickbooks.create_purchase_sales_receipt result",
        payment_id: payment.id,
        result: inspect(result, limit: :infinity)
      )

      result
    end
  end

  defp create_mixed_payment_sales_receipt(payment, customer_id, entity_info) do
    Logger.debug(
      "[QB Sync] create_mixed_payment_sales_receipt: Creating mixed payment sales receipt",
      payment_id: payment.id,
      customer_id: customer_id
    )

    # Get or create item IDs for event and donation
    Logger.debug(
      "[QB Sync] create_mixed_payment_sales_receipt: Getting or creating item IDs",
      payment_id: payment.id
    )

    with {:ok, event_item_id} <-
           get_or_create_item_with_fallback(
             "Event Tickets",
             :event_item_id,
             "Events Inc"
           ),
         {:ok, donation_item_id} <-
           get_or_create_item_with_fallback(
             "Donations",
             :donation_item_id,
             "Donations"
           ) do
      Logger.debug(
        "[QB Sync] create_mixed_payment_sales_receipt: Item IDs obtained",
        payment_id: payment.id,
        event_item_id: event_item_id,
        donation_item_id: donation_item_id
      )

      # Build line items - only include non-zero amounts
      line_items = []

      # Add event line item if event entry exists and has positive amount
      Logger.debug(
        "[QB Sync] create_mixed_payment_sales_receipt: Checking event entry",
        payment_id: payment.id,
        has_event_entry: !is_nil(entity_info.event_entry),
        event_amount:
          if(entity_info.event_entry,
            do: inspect(entity_info.event_entry.amount),
            else: nil
          )
      )

      line_items =
        if entity_info.event_entry &&
             Money.positive?(entity_info.event_entry.amount) do
          # Money.to_decimal returns dollars (database stores amounts in dollars)
          event_amount =
            Money.to_decimal(entity_info.event_entry.amount)
            |> Decimal.round(2)

          Logger.debug(
            "[QB Sync] create_mixed_payment_sales_receipt: Building event line item",
            payment_id: payment.id,
            event_amount: Decimal.to_string(event_amount)
          )

          event_line_item =
            build_sales_line_item(
              event_item_id,
              event_amount,
              "Event tickets - Order #{payment.reference_id}",
              @account_class_mapping[:event].class
            )

          Logger.debug(
            "[QB Sync] create_mixed_payment_sales_receipt: Event line item built",
            payment_id: payment.id,
            line_item: inspect(event_line_item, limit: :infinity)
          )

          [event_line_item | line_items]
        else
          Logger.debug(
            "[QB Sync] create_mixed_payment_sales_receipt: Skipping event line item",
            payment_id: payment.id
          )

          line_items
        end

      # Add donation line item if donation entry exists and has positive amount
      Logger.debug(
        "[QB Sync] create_mixed_payment_sales_receipt: Checking donation entry",
        payment_id: payment.id,
        has_donation_entry: !is_nil(entity_info.donation_entry),
        donation_amount:
          if(entity_info.donation_entry,
            do: inspect(entity_info.donation_entry.amount),
            else: nil
          )
      )

      line_items =
        if entity_info.donation_entry &&
             Money.positive?(entity_info.donation_entry.amount) do
          # Money.to_decimal returns dollars (database stores amounts in dollars)
          donation_amount =
            Money.to_decimal(entity_info.donation_entry.amount)
            |> Decimal.round(2)

          Logger.debug(
            "[QB Sync] create_mixed_payment_sales_receipt: Building donation line item",
            payment_id: payment.id,
            donation_amount: Decimal.to_string(donation_amount)
          )

          donation_line_item =
            build_sales_line_item(
              donation_item_id,
              donation_amount,
              "Donation - Order #{payment.reference_id}",
              @account_class_mapping[:donation].class
            )

          Logger.debug(
            "[QB Sync] create_mixed_payment_sales_receipt: Donation line item built",
            payment_id: payment.id,
            line_item: inspect(donation_line_item, limit: :infinity)
          )

          [donation_line_item | line_items]
        else
          Logger.debug(
            "[QB Sync] create_mixed_payment_sales_receipt: Skipping donation line item",
            payment_id: payment.id
          )

          line_items
        end

      Logger.debug(
        "[QB Sync] create_mixed_payment_sales_receipt: Line items built",
        payment_id: payment.id,
        line_items_count: length(line_items),
        line_items: inspect(line_items, limit: :infinity)
      )

      # Calculate total from line items
      total_amount =
        Enum.reduce(line_items, Decimal.new(0), fn item, acc ->
          Decimal.add(acc, item.amount)
        end)

      Logger.debug(
        "[QB Sync] create_mixed_payment_sales_receipt: Total calculated",
        payment_id: payment.id,
        total_amount: Decimal.to_string(total_amount)
      )

      # Build sales receipt params
      sales_receipt_params = %{
        customer_ref: %{value: customer_id},
        line: Enum.reverse(line_items),
        total_amt: total_amount,
        txn_date:
          format_payment_date(payment.payment_date || payment.inserted_at),
        memo: "Payment: #{payment.reference_id}",
        private_note: "External Payment ID: #{payment.external_payment_id}"
      }

      Logger.debug(
        "[QB Sync] create_mixed_payment_sales_receipt: Sales receipt params built",
        payment_id: payment.id,
        params: inspect(sales_receipt_params, limit: :infinity)
      )

      # Use client directly to create sales receipt with multiple line items
      client_module =
        Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)

      Logger.debug(
        "[QB Sync] create_mixed_payment_sales_receipt: Calling client.create_sales_receipt",
        payment_id: payment.id,
        client_module: inspect(client_module)
      )

      result = client_module.create_sales_receipt(sales_receipt_params)

      Logger.debug(
        "[QB Sync] create_mixed_payment_sales_receipt: Client.create_sales_receipt result",
        payment_id: payment.id,
        result: inspect(result, limit: :infinity)
      )

      result
    else
      error ->
        Logger.warning(
          "[QB Sync] create_mixed_payment_sales_receipt: Failed to get or create item IDs",
          payment_id: payment.id,
          error: inspect(error)
        )

        error
    end
  end

  defp get_or_create_item_with_fallback(
         item_name,
         config_key,
         income_account_name
       ) do
    # First check if there's a configured override
    case Application.get_env(:ysc, :quickbooks, [])[config_key] do
      nil ->
        # No override, get or create via API
        # Get income account if provided
        income_account_ref =
          if income_account_name do
            case client_module().query_account_by_name(income_account_name) do
              {:ok, account_id} ->
                Logger.debug(
                  "[QB Sync] get_or_create_item_with_fallback: Found income account",
                  account_name: income_account_name,
                  account_id: account_id
                )

                %{value: account_id}

              _ ->
                nil
            end
          else
            nil
          end

        Quickbooks.Client.get_or_create_item(item_name,
          income_account_ref: income_account_ref
        )

      configured_item_id ->
        # Use configured override
        {:ok, configured_item_id}
    end
  end

  # Helper function to get the Administration class ID (used as default/fallback)
  defp get_administration_class_ref do
    case client_module().query_class_by_name("Administration") do
      {:ok, class_id} ->
        %{value: class_id, name: "Administration"}

      _ ->
        Logger.warning(
          "[QB Sync] get_administration_class_ref: CRITICAL - Administration class not found! Using hardcoded fallback (this may fail)"
        )

        Sentry.capture_message("QuickBooks Administration class not found",
          level: :error,
          tags: %{quickbooks_operation: "get_administration_class_ref"}
        )

        # Last resort fallback - this may fail, but we must provide a class
        %{value: "Administration", name: "Administration"}
    end
  end

  defp build_sales_line_item(item_id, amount, description, class_ref) do
    # class_ref should be a map with {value: class_id, name: class_name} or nil
    # If it's a string (class name), we need to query for the ID
    # CRITICAL: ALL QuickBooks exports MUST include a class reference
    class_ref_map =
      case class_ref do
        %{value: _} = ref ->
          # Already a proper ref map
          ref

        class_name when is_binary(class_name) ->
          # Query for class ID
          case client_module().query_class_by_name(class_name) do
            {:ok, class_id} ->
              Logger.debug("[QB Sync] build_sales_line_item: Found class ID",
                class_name: class_name,
                class_id: class_id
              )

              %{value: class_id, name: class_name}

            _ ->
              Logger.warning(
                "[QB Sync] build_sales_line_item: Class '#{class_name}' not found, falling back to Administration",
                class_name: class_name
              )

              # Fallback to Administration if the requested class is not found
              get_administration_class_ref()
          end

        _ ->
          # Default to "Administration" if not provided
          Logger.debug(
            "[QB Sync] build_sales_line_item: Using default Administration class"
          )

          get_administration_class_ref()
      end

    Logger.debug(
      "[QB Sync] build_sales_line_item: Building line item with class",
      item_id: item_id,
      class_ref: inspect(class_ref_map),
      was_provided: not is_nil(class_ref)
    )

    # ALWAYS include class_ref - it's required for all QuickBooks exports
    sales_item_detail = %{
      item_ref: %{value: item_id},
      quantity: Decimal.new(1),
      unit_price: amount,
      class_ref: class_ref_map
    }

    %{
      amount: amount,
      detail_type: "SalesItemLineDetail",
      sales_item_line_detail: sales_item_detail,
      description: description
    }
  end

  defp format_payment_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp format_payment_date(nil), do: nil

  defp create_refund_sales_receipt(refund, customer_id, item_id, entity_info) do
    # Best Practice: Use the same ItemRef as the original sale for correct revenue reversal
    # We get entity_info from the original payment, ensuring we use the same item
    Logger.debug(
      "[QB Sync] create_refund_sales_receipt: Creating refund receipt",
      refund_id: refund.id,
      customer_id: customer_id,
      item_id: item_id,
      entity_type: entity_info.entity_type,
      note: "Using same ItemRef as original sale for correct revenue reversal"
    )

    # Money.to_decimal returns dollars (database stores amounts in dollars)
    # RefundReceipts use positive amounts - the transaction type determines direction
    amount =
      Money.to_decimal(refund.amount)
      |> Decimal.round(2)

    Logger.debug("[QB Sync] create_refund_sales_receipt: Calculated amount",
      refund_id: refund.id,
      amount_cents: inspect(refund.amount),
      amount_dollars: Decimal.to_string(amount)
    )

    account_class = get_account_and_class(entity_info)

    # Best Practice: Set DepositToAccountRef (QuickBooks API field name) to the correct settlement account
    # For Stripe, we use "Undeposited Funds" since funds take time to land
    # This ensures proper accounting for money going back to the customer
    # Note: QuickBooks uses "DepositToAccountRef" for RefundReceipts (same as SalesReceipts)
    refund_from_account_ref =
      case client_module().query_account_by_name("Undeposited Funds") do
        {:ok, account_id} ->
          Logger.debug(
            "[QB Sync] create_refund_sales_receipt: Found Undeposited Funds account",
            refund_id: refund.id,
            account_id: account_id
          )

          %{value: account_id, name: "Undeposited Funds"}

        {:error, :not_found} ->
          Logger.warning(
            "[QB Sync] create_refund_sales_receipt: Undeposited Funds account not found, refund receipt may fail",
            refund_id: refund.id
          )

          nil

        error ->
          Logger.warning(
            "[QB Sync] create_refund_sales_receipt: Failed to query Undeposited Funds account",
            refund_id: refund.id,
            error: inspect(error)
          )

          nil
      end

    # Best Practice: Add traceability via PrivateNote
    # QuickBooks doesn't support direct linking of RefundReceipt to SalesReceipt,
    # so we include the original transaction ID in PrivateNote for audit trail
    Logger.debug(
      "[QB Sync] create_refund_sales_receipt: Getting original payment",
      refund_id: refund.id,
      payment_id: refund.payment_id
    )

    original_payment = get_payment(refund.payment_id)

    private_note =
      case original_payment do
        {:ok, payment}
        when not is_nil(payment.quickbooks_sales_receipt_id) and
               payment.quickbooks_sales_receipt_id != "" and
               payment.quickbooks_sales_receipt_id != "qb_sr_default" and
               payment.quickbooks_sync_status == "synced" ->
          Logger.debug(
            "[QB Sync] create_refund_sales_receipt: Found original payment sales receipt",
            refund_id: refund.id,
            payment_sales_receipt_id: payment.quickbooks_sales_receipt_id
          )

          "External Refund ID: #{refund.external_refund_id}\nOriginal Payment SalesReceipt: #{payment.quickbooks_sales_receipt_id}"

        _ ->
          Logger.debug(
            "[QB Sync] create_refund_sales_receipt: No original payment sales receipt found",
            refund_id: refund.id
          )

          "External Refund ID: #{refund.external_refund_id}"
      end

    params = %{
      customer_id: customer_id,
      item_id: item_id,
      quantity: 1,
      unit_price: amount,
      txn_date: refund.inserted_at,
      description: "Refund #{refund.reference_id}",
      memo: "Refund: #{refund.reference_id}",
      private_note: private_note
    }

    # CRITICAL: refund_from_account_id is required for create_refund_receipt
    # Always set it, even if we have to use a fallback
    params =
      if refund_from_account_ref do
        Map.merge(params, %{
          refund_from_account_id: refund_from_account_ref.value,
          refund_from_account_name: refund_from_account_ref.name
        })
      else
        # Fallback: try to get "Undeposited Funds" account ID directly
        # If that fails, we'll use a hardcoded value (this should not happen in production)
        Logger.warning(
          "[QB Sync] create_refund_sales_receipt: refund_from_account_ref is nil, attempting fallback",
          refund_id: refund.id
        )

        case client_module().query_account_by_name("Undeposited Funds") do
          {:ok, account_id} ->
            Logger.debug(
              "[QB Sync] create_refund_sales_receipt: Found Undeposited Funds account via fallback",
              refund_id: refund.id,
              account_id: account_id
            )

            Map.merge(params, %{
              refund_from_account_id: account_id,
              refund_from_account_name: "Undeposited Funds"
            })

          _ ->
            Logger.warning(
              "[QB Sync] create_refund_sales_receipt: CRITICAL - Cannot find Undeposited Funds account, refund receipt will fail",
              refund_id: refund.id
            )

            Sentry.capture_message(
              "QuickBooks Undeposited Funds account not found",
              level: :error,
              extra: %{refund_id: refund.id},
              tags: %{quickbooks_operation: "create_refund_sales_receipt"}
            )

            # This will likely fail, but we must provide something
            Map.merge(params, %{
              refund_from_account_id: "undeposited_funds_account_default",
              refund_from_account_name: "Undeposited Funds"
            })
        end
      end

    # Always set a class - get_account_and_class now always returns a class (defaults to "Administration")
    # Query QuickBooks to get the class ID (not just the name)
    class_name = account_class.class

    Logger.debug("[QB Sync] create_refund_sales_receipt: Querying for class ID",
      refund_id: refund.id,
      class_name: class_name
    )

    class_ref =
      case client_module().query_class_by_name(class_name) do
        {:ok, class_id} ->
          Logger.debug("[QB Sync] create_refund_sales_receipt: Found class ID",
            refund_id: refund.id,
            class_name: class_name,
            class_id: class_id
          )

          %{value: class_id, name: class_name}

        {:error, :not_found} ->
          Logger.warning(
            "[QB Sync] create_refund_sales_receipt: Class '#{class_name}' not found, falling back to Administration",
            refund_id: refund.id,
            class_name: class_name
          )

          # Fallback to Administration - ALL exports must have a class
          get_administration_class_ref()

        error ->
          Logger.warning(
            "[QB Sync] create_refund_sales_receipt: Failed to query class, falling back to Administration",
            refund_id: refund.id,
            class_name: class_name,
            error: inspect(error)
          )

          # Fallback to Administration - ALL exports must have a class
          get_administration_class_ref()
      end

    # ALWAYS include class_ref - it's required for all QuickBooks exports
    params = Map.put(params, :class_ref, class_ref)

    # CRITICAL: Ensure refund_from_account_id is always present (create_refund_receipt requires it)
    # The code above (lines 1599-1638) should have already set refund_from_account_id,
    # but we also handle the case where refund_from_account_ref might be in params
    # (though this shouldn't happen in normal flow)
    params =
      cond do
        # If refund_from_account_id is already set, we're good
        Map.has_key?(params, :refund_from_account_id) ->
          # Remove refund_from_account_ref if it exists (shouldn't be there, but clean up)
          Map.delete(params, :refund_from_account_ref)

        # If refund_from_account_ref is in params, convert it
        Map.has_key?(params, :refund_from_account_ref) ->
          ref = params.refund_from_account_ref

          params
          |> Map.merge(%{
            refund_from_account_id: ref.value,
            refund_from_account_name: ref.name
          })
          |> Map.delete(:refund_from_account_ref)

        # Fallback: this shouldn't happen, but provide a default
        true ->
          Logger.warning(
            "[QB Sync] create_refund_sales_receipt: refund_from_account_id not set, using fallback",
            refund_id: refund.id
          )

          Map.merge(params, %{
            refund_from_account_id: "undeposited_funds_account_default",
            refund_from_account_name: "Undeposited Funds"
          })
      end

    Logger.debug(
      "[QB Sync] create_refund_sales_receipt: Calling Quickbooks.create_refund_receipt",
      refund_id: refund.id,
      params: inspect(params, limit: :infinity)
    )

    result = Quickbooks.create_refund_receipt(params)

    Logger.debug(
      "[QB Sync] create_refund_sales_receipt: Quickbooks.create_refund_receipt result",
      refund_id: refund.id,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  defp create_payout_deposit(%Payout{} = payout) do
    Logger.debug("[QB Sync] create_payout_deposit: Creating payout deposit",
      payout_id: payout.id
    )

    bank_account_id = Application.get_env(:ysc, :quickbooks)[:bank_account_id]

    stripe_account_id =
      Application.get_env(:ysc, :quickbooks)[:stripe_account_id]

    Logger.debug("[QB Sync] create_payout_deposit: Account IDs",
      payout_id: payout.id,
      bank_account_id: bank_account_id,
      stripe_account_id: stripe_account_id
    )

    if bank_account_id && stripe_account_id do
      # Check if payout has any linked payments or refunds
      payments_count = length(payout.payments || [])
      refunds_count = length(payout.refunds || [])

      Logger.info("[QB Sync] create_payout_deposit: Payout transaction counts",
        payout_id: payout.id,
        stripe_payout_id: payout.stripe_payout_id,
        payments_count: payments_count,
        refunds_count: refunds_count,
        total_transactions: payments_count + refunds_count,
        payout_amount: Money.to_string!(payout.amount),
        fee_total:
          if(payout.fee_total,
            do: Money.to_string!(payout.fee_total),
            else: nil
          )
      )

      if payments_count == 0 && refunds_count == 0 do
        Logger.warning(
          "[QB Sync] create_payout_deposit: Payout has no linked payments or refunds - creating simple deposit",
          payout_id: payout.id,
          stripe_payout_id: payout.stripe_payout_id,
          payout_amount: Money.to_string!(payout.amount)
        )

        # Create a simple deposit without line items for payouts with no linked transactions
        # Money.to_decimal returns dollars (database stores amounts in dollars)
        amount =
          Money.to_decimal(payout.amount)
          |> Decimal.round(2)

        # Get Administration class for simple deposit
        administration_class_ref = get_administration_class_ref()

        params = %{
          bank_account_id: bank_account_id,
          deposit_to_account_ref: %{value: bank_account_id},
          line: [
            %{
              amount: amount,
              detail_type: "DepositLineDetail",
              deposit_line_detail: %{
                entity_ref: %{value: stripe_account_id, type: "Account"},
                class_ref: administration_class_ref
              },
              description: "Stripe Payout: #{payout.stripe_payout_id}"
            }
          ],
          total_amt: amount,
          txn_date:
            format_payout_date(payout.arrival_date || payout.inserted_at),
          memo: "Stripe Payout: #{payout.stripe_payout_id}",
          private_note: "Payout with no linked transactions"
        }

        Logger.debug("[QB Sync] create_payout_deposit: Simple deposit params",
          payout_id: payout.id,
          params: inspect(params, limit: :infinity)
        )

        client_module().create_deposit(params)
      else
        # Build line items for each payment and refund
        Logger.debug("[QB Sync] create_payout_deposit: Building line items",
          payout_id: payout.id
        )

        line_items = build_payout_line_items(payout)

        Logger.debug("[QB Sync] create_payout_deposit: Line items built",
          payout_id: payout.id,
          line_items_count: length(line_items),
          line_items: inspect(line_items, limit: :infinity)
        )

        if Enum.empty?(line_items) do
          Logger.warning(
            "[QB Sync] No synced payments or refunds found for payout, creating single line item",
            payout_id: payout.id
          )

          # Fallback: create single line item with total amount
          # Money.to_decimal returns dollars (database stores amounts in dollars)
          amount =
            Money.to_decimal(payout.amount)
            |> Decimal.round(2)

          Logger.debug(
            "[QB Sync] create_payout_deposit: Using fallback single line item",
            payout_id: payout.id,
            amount: Decimal.to_string(amount)
          )

          # Get Administration class for fallback line item
          administration_class_ref = get_administration_class_ref()

          params = %{
            bank_account_id: bank_account_id,
            stripe_account_id: stripe_account_id,
            amount: amount,
            txn_date: payout.arrival_date || payout.inserted_at,
            memo: "Stripe Payout: #{payout.stripe_payout_id}",
            description: payout.description || "Stripe payout",
            class_ref: administration_class_ref
          }

          Logger.debug(
            "[QB Sync] create_payout_deposit: Calling Quickbooks.create_stripe_payout_deposit",
            payout_id: payout.id,
            params: inspect(params, limit: :infinity)
          )

          result = Quickbooks.create_stripe_payout_deposit(params)

          Logger.debug(
            "[QB Sync] create_payout_deposit: Quickbooks.create_stripe_payout_deposit result",
            payout_id: payout.id,
            result: inspect(result, limit: :infinity)
          )

          result
        else
          # Use cached fee_total from payout (set by webhook handler)
          # Fall back to calculating from ledger entries if fee_total is not available (for old payouts)
          stripe_fees =
            if payout.fee_total do
              Logger.debug(
                "[QB Sync] create_payout_deposit: Using cached fee_total from payout",
                payout_id: payout.id,
                fee_total: Money.to_string!(payout.fee_total)
              )

              payout.fee_total
            else
              Logger.debug(
                "[QB Sync] create_payout_deposit: fee_total not available, calculating from ledger entries",
                payout_id: payout.id
              )

              calculate_payout_stripe_fees(payout, payout.payments)
            end

          Logger.debug(
            "[QB Sync] create_payout_deposit: Stripe fees determined",
            payout_id: payout.id,
            stripe_fees: inspect(stripe_fees),
            using_cached: not is_nil(payout.fee_total)
          )

          # Add Stripe fees line item if there are fees
          # Get Administration class for Stripe fees (they're administrative expenses)
          administration_class_ref = get_administration_class_ref()

          line_items =
            if stripe_fees && Money.positive?(stripe_fees) do
              case get_or_create_stripe_fee_item() do
                {:ok, stripe_fee_item_id} ->
                  # Fees are expenses, so they should be negative in the deposit
                  # Money.to_decimal returns dollars (database stores amounts in dollars)
                  fee_amount =
                    Money.to_decimal(stripe_fees)
                    |> Decimal.round(2)
                    |> Decimal.negate()

                  fee_line_item = %{
                    amount: fee_amount,
                    detail_type: "SalesItemLineDetail",
                    sales_item_line_detail: %{
                      item_ref: %{value: stripe_fee_item_id},
                      quantity: Decimal.new(1),
                      unit_price: fee_amount,
                      class_ref: administration_class_ref
                    },
                    description:
                      "Stripe processing fees for payout #{payout.stripe_payout_id}"
                  }

                  Logger.debug(
                    "[QB Sync] create_payout_deposit: Added Stripe fees line item",
                    payout_id: payout.id,
                    fee_amount: Decimal.to_string(fee_amount),
                    item_id: stripe_fee_item_id
                  )

                  [fee_line_item | line_items]

                error ->
                  Logger.warning(
                    "[QB Sync] create_payout_deposit: Failed to get/create Stripe fee item, continuing without fee line item",
                    payout_id: payout.id,
                    error: inspect(error)
                  )

                  line_items
              end
            else
              Logger.debug(
                "[QB Sync] create_payout_deposit: No Stripe fees to include",
                payout_id: payout.id
              )

              line_items
            end

          # Calculate total from line items (including fees)
          total_amount =
            Enum.reduce(line_items, Decimal.new(0), fn item, acc ->
              Decimal.add(acc, item.amount)
            end)

          Logger.debug("[QB Sync] create_payout_deposit: Total calculated",
            payout_id: payout.id,
            total_amount: Decimal.to_string(total_amount),
            line_items_count: length(line_items)
          )

          # Create deposit with multiple line items
          create_payout_deposit_with_lines(
            payout,
            bank_account_id,
            line_items,
            total_amount
          )
        end
      end
    else
      Logger.warning(
        "[QB Sync] create_payout_deposit: QuickBooks accounts not configured",
        payout_id: payout.id,
        bank_account_id: bank_account_id,
        stripe_account_id: stripe_account_id
      )

      {:error, :quickbooks_accounts_not_configured}
    end
  end

  defp build_payout_line_items(%Payout{payments: payments, refunds: refunds}) do
    Logger.debug("[QB Sync] build_payout_line_items: Building line items",
      payments_count: length(payments),
      refunds_count: length(refunds)
    )

    # Get Administration class for deposit line items (payouts are administrative transactions)
    administration_class_ref = get_administration_class_ref()

    # Build line items for payments (positive amounts)
    Logger.debug("[QB Sync] build_payout_line_items: Processing payments",
      payments_count: length(payments)
    )

    payment_lines =
      Enum.map(payments, fn payment ->
        Logger.debug("[QB Sync] build_payout_line_items: Processing payment",
          payment_id: payment.id,
          sync_status: payment.quickbooks_sync_status,
          sales_receipt_id: payment.quickbooks_sales_receipt_id
        )

        # Only include payments that have been synced to QuickBooks
        if payment.quickbooks_sync_status == "synced" &&
             payment.quickbooks_sales_receipt_id do
          # Money.to_decimal returns dollars (database stores amounts in dollars)
          amount =
            Money.to_decimal(payment.amount)
            |> Decimal.round(2)

          Logger.debug(
            "[QB Sync] build_payout_line_items: Payment line item created",
            payment_id: payment.id,
            amount: Decimal.to_string(amount),
            sales_receipt_id: payment.quickbooks_sales_receipt_id
          )

          %{
            amount: amount,
            detail_type: "DepositLineDetail",
            deposit_line_detail: %{
              class_ref: administration_class_ref
            },
            # LinkedTxn is required to link a Deposit to a SalesReceipt in QuickBooks
            linked_txn: [
              %{
                txn_id: payment.quickbooks_sales_receipt_id,
                txn_type: "SalesReceipt"
              }
            ],
            description: "Payment #{payment.reference_id}"
          }
        else
          Logger.debug(
            "[QB Sync] build_payout_line_items: Skipping unsynced payment",
            payment_id: payment.id,
            sync_status: payment.quickbooks_sync_status,
            sales_receipt_id: payment.quickbooks_sales_receipt_id
          )

          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    Logger.info("[QB Sync] build_payout_line_items: Payment line items built",
      payment_lines_count: length(payment_lines),
      payment_line_details:
        Enum.map(payment_lines, fn line ->
          %{
            amount: Decimal.to_string(line.amount),
            description: line.description,
            linked_txn_id: List.first(line.linked_txn).txn_id
          }
        end)
    )

    # Build line items for refunds (negative amounts)
    Logger.debug("[QB Sync] build_payout_line_items: Processing refunds",
      refunds_count: length(refunds)
    )

    refund_lines =
      Enum.map(refunds, fn refund ->
        Logger.debug("[QB Sync] build_payout_line_items: Processing refund",
          refund_id: refund.id,
          sync_status: refund.quickbooks_sync_status,
          sales_receipt_id: refund.quickbooks_sales_receipt_id
        )

        # Only include refunds that have been synced to QuickBooks
        if refund.quickbooks_sync_status == "synced" &&
             refund.quickbooks_sales_receipt_id do
          # Money.to_decimal returns dollars (database stores amounts in dollars)
          # Negate for refunds (negative amounts)
          amount =
            Money.to_decimal(refund.amount)
            |> Decimal.round(2)
            |> Decimal.negate()

          Logger.debug(
            "[QB Sync] build_payout_line_items: Refund line item created",
            refund_id: refund.id,
            amount: Decimal.to_string(amount),
            sales_receipt_id: refund.quickbooks_sales_receipt_id
          )

          %{
            amount: amount,
            detail_type: "DepositLineDetail",
            deposit_line_detail: %{
              class_ref: administration_class_ref
            },
            # LinkedTxn is required to link a Deposit to a RefundReceipt in QuickBooks
            linked_txn: [
              %{
                txn_id: refund.quickbooks_sales_receipt_id,
                txn_type: "RefundReceipt"
              }
            ],
            description: "Refund #{refund.reference_id}"
          }
        else
          Logger.debug(
            "[QB Sync] build_payout_line_items: Skipping unsynced refund",
            refund_id: refund.id,
            sync_status: refund.quickbooks_sync_status,
            sales_receipt_id: refund.quickbooks_sales_receipt_id
          )

          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    Logger.info("[QB Sync] build_payout_line_items: Refund line items built",
      refund_lines_count: length(refund_lines),
      refund_line_details:
        Enum.map(refund_lines, fn line ->
          %{
            amount: Decimal.to_string(line.amount),
            description: line.description,
            linked_txn_id: List.first(line.linked_txn).txn_id
          }
        end)
    )

    all_lines = payment_lines ++ refund_lines

    Logger.info("[QB Sync] build_payout_line_items: All line items built",
      total_lines_count: length(all_lines),
      total_amount:
        Enum.reduce(all_lines, Decimal.new(0), fn line, acc ->
          Decimal.add(acc, line.amount)
        end)
        |> Decimal.to_string()
    )

    all_lines
  end

  defp calculate_payout_stripe_fees(%Payout{} = payout, payments) do
    Logger.debug(
      "[QB Sync] calculate_payout_stripe_fees: Calculating total Stripe fees",
      payout_id: payout.id,
      payments_count: length(payments),
      payment_ids: Enum.map(payments, & &1.id)
    )

    # Get all Stripe fee entries for payments in this payout
    payment_ids = Enum.map(payments, & &1.id)

    if Enum.empty?(payment_ids) do
      Logger.debug(
        "[QB Sync] calculate_payout_stripe_fees: No payments, returning zero",
        payout_id: payout.id
      )

      Money.new(0, :USD)
    else
      fees =
        from(e in LedgerEntry,
          join: a in assoc(e, :account),
          where: e.payment_id in ^payment_ids,
          where: a.name == "stripe_fees",
          where: e.debit_credit == "debit",
          select: sum(fragment("(?.amount).amount", e))
        )
        |> Repo.one()

      total_fees =
        case fees do
          nil -> Money.new(0, :USD)
          amount when is_integer(amount) -> Money.new(amount, :USD)
          _ -> Money.new(0, :USD)
        end

      Logger.debug(
        "[QB Sync] calculate_payout_stripe_fees: Total fees calculated",
        payout_id: payout.id,
        total_fees: inspect(total_fees),
        fees_cents:
          if(total_fees,
            do: total_fees.amount |> Decimal.mult(100) |> Decimal.to_integer(),
            else: 0
          )
      )

      total_fees
    end
  end

  defp get_or_create_stripe_fee_item do
    Logger.debug(
      "[QB Sync] get_or_create_stripe_fee_item: Getting or creating Stripe Fees item"
    )

    # Check for config override first
    case Application.get_env(:ysc, :quickbooks, [])[:stripe_fee_item_id] do
      nil ->
        # No override, get or create via API
        Logger.debug(
          "[QB Sync] get_or_create_stripe_fee_item: No config override, using API"
        )

        # Stripe fees use the "Stripe Fees" expense account, but Service items require IncomeAccountRef
        # Query for an income account (we'll use a general revenue account as fallback)
        income_account_ref =
          case client_module().query_account_by_name("Stripe Fees") do
            {:ok, account_id} ->
              Logger.debug(
                "[QB Sync] get_or_create_stripe_fee_item: Found Stripe Fees account",
                account_id: account_id
              )

              %{value: account_id}

            _ ->
              # Fallback to a general revenue account if Stripe Fees account not found
              case client_module().query_account_by_name("General Revenue") do
                {:ok, account_id} ->
                  Logger.debug(
                    "[QB Sync] get_or_create_stripe_fee_item: Using General Revenue as fallback",
                    account_id: account_id
                  )

                  %{value: account_id}

                _ ->
                  nil
              end
          end

        client_module().get_or_create_item("Stripe Fees",
          income_account_ref: income_account_ref
        )

      configured_item_id ->
        Logger.debug(
          "[QB Sync] get_or_create_stripe_fee_item: Using configured item ID",
          item_id: configured_item_id
        )

        {:ok, configured_item_id}
    end
  end

  defp create_payout_deposit_with_lines(
         payout,
         bank_account_id,
         line_items,
         total_amount
       ) do
    Logger.debug(
      "[QB Sync] create_payout_deposit_with_lines: Creating deposit with line items",
      payout_id: payout.id,
      bank_account_id: bank_account_id,
      line_items_count: length(line_items),
      total_amount: Decimal.to_string(total_amount)
    )

    # Build deposit params with line items in the format expected by Client.create_deposit
    deposit_params = %{
      deposit_to_account_ref: %{value: bank_account_id},
      line: line_items,
      total_amt: total_amount,
      txn_date: format_payout_date(payout.arrival_date || payout.inserted_at),
      memo: "Stripe Payout: #{payout.stripe_payout_id}",
      private_note:
        "Payout includes #{length(payout.payments)} payments and #{length(payout.refunds)} refunds"
    }

    Logger.debug(
      "[QB Sync] create_payout_deposit_with_lines: Deposit params built",
      payout_id: payout.id,
      params: inspect(deposit_params, limit: :infinity)
    )

    # Use the client directly to create deposit with custom line items
    client_module =
      Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)

    Logger.debug(
      "[QB Sync] create_payout_deposit_with_lines: Calling client.create_deposit",
      payout_id: payout.id,
      client_module: inspect(client_module)
    )

    result = client_module.create_deposit(deposit_params)

    Logger.debug(
      "[QB Sync] create_payout_deposit_with_lines: Client.create_deposit result",
      payout_id: payout.id,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  defp format_payout_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp format_payout_date(nil), do: nil

  defp check_and_enqueue_payout_syncs_for_payment(%Payment{} = payment) do
    Logger.debug(
      "[QB Sync] check_and_enqueue_payout_syncs_for_payment: Finding payouts for payment",
      payment_id: payment.id
    )

    # Find all payouts that contain this payment
    # Convert ULID to binary for comparison with join table's binary_id column
    payment_id_binary =
      case Ecto.ULID.dump(payment.id) do
        {:ok, binary} -> binary
        _ -> payment.id
      end

    Logger.debug(
      "[QB Sync] check_and_enqueue_payout_syncs_for_payment: Payment ID binary",
      payment_id: payment.id,
      payment_id_binary: inspect(payment_id_binary)
    )

    payouts =
      from(p in Payout,
        join: pp in "payout_payments",
        on: pp.payout_id == p.id,
        where: pp.payment_id == ^payment_id_binary,
        where: p.quickbooks_sync_status != "synced"
      )
      |> Repo.all()

    Logger.debug(
      "[QB Sync] check_and_enqueue_payout_syncs_for_payment: Found payouts",
      payment_id: payment.id,
      payouts_count: length(payouts),
      payout_ids: Enum.map(payouts, & &1.id)
    )

    Enum.each(payouts, fn payout ->
      Logger.debug(
        "[QB Sync] check_and_enqueue_payout_syncs_for_payment: Checking payout",
        payment_id: payment.id,
        payout_id: payout.id
      )

      check_and_enqueue_payout_sync(payout)
    end)
  end

  defp check_and_enqueue_payout_syncs_for_refund(%Refund{} = refund) do
    Logger.debug(
      "[QB Sync] check_and_enqueue_payout_syncs_for_refund: Finding payouts for refund",
      refund_id: refund.id
    )

    # Find all payouts that contain this refund
    # Convert ULID to binary for comparison with join table's binary_id column
    refund_id_binary =
      case Ecto.ULID.dump(refund.id) do
        {:ok, binary} -> binary
        _ -> refund.id
      end

    Logger.debug(
      "[QB Sync] check_and_enqueue_payout_syncs_for_refund: Refund ID binary",
      refund_id: refund.id,
      refund_id_binary: inspect(refund_id_binary)
    )

    payouts =
      from(p in Payout,
        join: pr in "payout_refunds",
        on: pr.payout_id == p.id,
        where: pr.refund_id == ^refund_id_binary,
        where: p.quickbooks_sync_status != "synced"
      )
      |> Repo.all()

    Logger.debug(
      "[QB Sync] check_and_enqueue_payout_syncs_for_refund: Found payouts",
      refund_id: refund.id,
      payouts_count: length(payouts),
      payout_ids: Enum.map(payouts, & &1.id)
    )

    Enum.each(payouts, fn payout ->
      Logger.debug(
        "[QB Sync] check_and_enqueue_payout_syncs_for_refund: Checking payout",
        refund_id: refund.id,
        payout_id: payout.id
      )

      check_and_enqueue_payout_sync(payout)
    end)
  end

  defp check_and_enqueue_payout_sync(%Payout{} = payout) do
    Logger.debug(
      "[QB Sync] check_and_enqueue_payout_sync: Checking if payout can be synced",
      payout_id: payout.id
    )

    # Reload payout with payments and refunds
    payout = Repo.preload(payout, [:payments, :refunds])

    Logger.debug("[QB Sync] check_and_enqueue_payout_sync: Loaded payout data",
      payout_id: payout.id,
      payments_count: length(payout.payments),
      refunds_count: length(payout.refunds)
    )

    # Check if all linked payments are synced
    all_payments_synced =
      Enum.all?(payout.payments, fn payment ->
        payment.quickbooks_sync_status == "synced" &&
          payment.quickbooks_sales_receipt_id != nil
      end)

    Logger.debug("[QB Sync] check_and_enqueue_payout_sync: Payment sync status",
      payout_id: payout.id,
      all_payments_synced: all_payments_synced,
      payment_statuses:
        Enum.map(payout.payments, fn p ->
          %{
            id: p.id,
            sync_status: p.quickbooks_sync_status,
            sales_receipt_id: p.quickbooks_sales_receipt_id
          }
        end)
    )

    # Check if all linked refunds are synced
    all_refunds_synced =
      Enum.all?(payout.refunds, fn refund ->
        refund.quickbooks_sync_status == "synced" &&
          refund.quickbooks_sales_receipt_id != nil
      end)

    Logger.debug("[QB Sync] check_and_enqueue_payout_sync: Refund sync status",
      payout_id: payout.id,
      all_refunds_synced: all_refunds_synced,
      refund_statuses:
        Enum.map(payout.refunds, fn r ->
          %{
            id: r.id,
            sync_status: r.quickbooks_sync_status,
            sales_receipt_id: r.quickbooks_sales_receipt_id
          }
        end)
    )

    # Only enqueue if we have transactions and they're all synced
    if all_payments_synced && all_refunds_synced &&
         (payout.payments != [] || payout.refunds != []) do
      Logger.info(
        "[QB Sync] All payments and refunds synced, enqueueing QuickBooks sync for payout",
        payout_id: payout.id,
        payments_count: length(payout.payments),
        refunds_count: length(payout.refunds)
      )

      # Mark payout as pending sync
      Logger.debug(
        "[QB Sync] check_and_enqueue_payout_sync: Marking payout as pending",
        payout_id: payout.id
      )

      payout
      |> Payout.changeset(%{quickbooks_sync_status: "pending"})
      |> Repo.update()

      # Enqueue sync job
      Logger.debug(
        "[QB Sync] check_and_enqueue_payout_sync: Enqueueing sync job",
        payout_id: payout.id
      )

      job =
        %{payout_id: to_string(payout.id)}
        |> QuickbooksSyncPayoutWorker.new()
        |> Oban.insert()

      Logger.debug("[QB Sync] check_and_enqueue_payout_sync: Job enqueued",
        payout_id: payout.id,
        job: inspect(job, limit: :infinity)
      )
    else
      Logger.debug(
        "[QB Sync] check_and_enqueue_payout_sync: Not ready to sync payout",
        payout_id: payout.id,
        all_payments_synced: all_payments_synced,
        all_refunds_synced: all_refunds_synced,
        has_transactions: payout.payments != [] || payout.refunds != []
      )
    end
  end

  defp verify_all_transactions_synced(%Payout{
         payments: payments,
         refunds: refunds
       }) do
    Logger.debug(
      "[QB Sync] verify_all_transactions_synced: Verifying all transactions are synced",
      payments_count: length(payments),
      refunds_count: length(refunds)
    )

    # Check all payments are synced
    unsynced_payments =
      Enum.filter(payments, fn payment ->
        payment.quickbooks_sync_status != "synced" ||
          payment.quickbooks_sales_receipt_id == nil
      end)

    Logger.info("[QB Sync] verify_all_transactions_synced: Payment sync check",
      total_payments: length(payments),
      unsynced_payments_count: length(unsynced_payments),
      unsynced_payment_ids: Enum.map(unsynced_payments, & &1.id),
      unsynced_payment_details:
        Enum.map(unsynced_payments, fn p ->
          %{
            id: p.id,
            reference_id: p.reference_id,
            sync_status: p.quickbooks_sync_status,
            sales_receipt_id: p.quickbooks_sales_receipt_id
          }
        end)
    )

    # Check all refunds are synced
    unsynced_refunds =
      Enum.filter(refunds, fn refund ->
        refund.quickbooks_sync_status != "synced" ||
          refund.quickbooks_sales_receipt_id == nil
      end)

    Logger.info("[QB Sync] verify_all_transactions_synced: Refund sync check",
      total_refunds: length(refunds),
      unsynced_refunds_count: length(unsynced_refunds),
      unsynced_refund_ids: Enum.map(unsynced_refunds, & &1.id),
      unsynced_refund_details:
        Enum.map(unsynced_refunds, fn r ->
          %{
            id: r.id,
            reference_id: r.reference_id,
            sync_status: r.quickbooks_sync_status,
            sales_receipt_id: r.quickbooks_sales_receipt_id
          }
        end)
    )

    if Enum.empty?(unsynced_payments) && Enum.empty?(unsynced_refunds) do
      Logger.debug(
        "[QB Sync] verify_all_transactions_synced: All transactions synced",
        payments_count: length(payments),
        refunds_count: length(refunds)
      )

      :ok
    else
      Logger.warning(
        "[QB Sync] Cannot sync payout - some payments or refunds are not synced yet",
        unsynced_payments_count: length(unsynced_payments),
        unsynced_refunds_count: length(unsynced_refunds),
        total_payments: length(payments),
        total_refunds: length(refunds)
      )

      {:error, :transactions_not_fully_synced}
    end
  end

  # Update functions for Payment
  defp update_sync_status(%Payment{} = payment, status, error, response) do
    Logger.debug("[QB Sync] update_sync_status: Updating payment sync status",
      payment_id: payment.id,
      status: status
    )

    result =
      payment
      |> Payment.changeset(%{
        quickbooks_sync_status: status,
        quickbooks_sync_error: error,
        quickbooks_response: response,
        quickbooks_last_sync_attempt_at: DateTime.utc_now()
      })
      |> Repo.update()

    Logger.debug("[QB Sync] update_sync_status: Payment status updated",
      payment_id: payment.id,
      status: status,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  defp update_sync_success(%Payment{} = payment, sales_receipt_id, response) do
    Logger.debug(
      "[QB Sync] update_sync_success: Updating payment with sync success",
      payment_id: payment.id,
      sales_receipt_id: sales_receipt_id
    )

    result =
      payment
      |> Payment.changeset(%{
        quickbooks_sales_receipt_id: sales_receipt_id,
        quickbooks_sync_status: "synced",
        quickbooks_synced_at: DateTime.utc_now(),
        quickbooks_response: response,
        quickbooks_last_sync_attempt_at: DateTime.utc_now()
      })
      |> Repo.update()

    Logger.debug("[QB Sync] update_sync_success: Payment updated with success",
      payment_id: payment.id,
      sales_receipt_id: sales_receipt_id,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  defp update_sync_failure(%Payment{} = payment, reason) do
    Logger.debug(
      "[QB Sync] update_sync_failure: Updating payment with sync failure",
      payment_id: payment.id,
      reason: inspect(reason)
    )

    error_map = %{
      error: inspect(reason),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Reload payment to ensure we have the latest state
    payment = Repo.reload!(payment)

    case payment
         |> Payment.changeset(%{
           quickbooks_sync_status: "failed",
           quickbooks_sync_error: error_map,
           quickbooks_last_sync_attempt_at: DateTime.utc_now()
         })
         |> Repo.update() do
      {:ok, _updated_payment} ->
        Logger.debug(
          "[QB Sync] update_sync_failure: Payment updated with failure",
          payment_id: payment.id
        )

        :ok

      {:error, changeset} ->
        Logger.warning("[QB Sync] Failed to update payment sync failure",
          payment_id: payment.id,
          error: inspect(changeset.errors)
        )

        # Report to Sentry
        Sentry.capture_message("Failed to update payment sync failure status",
          level: :error,
          extra: %{
            payment_id: payment.id,
            changeset_errors: inspect(changeset.errors)
          },
          tags: %{
            quickbooks_operation: "update_sync_failure",
            error_type: "changeset_validation"
          }
        )
    end
  end

  # Update functions for Refund
  defp update_sync_status_refund(%Refund{} = refund, status, error, response) do
    Logger.debug(
      "[QB Sync] update_sync_status_refund: Updating refund sync status",
      refund_id: refund.id,
      status: status
    )

    result =
      refund
      |> Refund.changeset(%{
        quickbooks_sync_status: status,
        quickbooks_sync_error: error,
        quickbooks_response: response,
        quickbooks_last_sync_attempt_at: DateTime.utc_now()
      })
      |> Repo.update()

    Logger.debug("[QB Sync] update_sync_status_refund: Refund status updated",
      refund_id: refund.id,
      status: status,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  defp update_sync_success_refund(
         %Refund{} = refund,
         sales_receipt_id,
         response
       ) do
    Logger.debug(
      "[QB Sync] update_sync_success_refund: Updating refund with sync success",
      refund_id: refund.id,
      sales_receipt_id: sales_receipt_id
    )

    result =
      refund
      |> Refund.changeset(%{
        quickbooks_sales_receipt_id: sales_receipt_id,
        quickbooks_sync_status: "synced",
        quickbooks_synced_at: DateTime.utc_now(),
        quickbooks_response: response,
        quickbooks_last_sync_attempt_at: DateTime.utc_now()
      })
      |> Repo.update()

    Logger.debug(
      "[QB Sync] update_sync_success_refund: Refund updated with success",
      refund_id: refund.id,
      sales_receipt_id: sales_receipt_id,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  defp update_sync_failure_refund(%Refund{} = refund, reason) do
    Logger.debug(
      "[QB Sync] update_sync_failure_refund: Updating refund with sync failure",
      refund_id: refund.id,
      reason: inspect(reason)
    )

    error_map = %{
      error: inspect(reason),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    result =
      refund
      |> Refund.changeset(%{
        quickbooks_sync_status: "failed",
        quickbooks_sync_error: error_map,
        quickbooks_last_sync_attempt_at: DateTime.utc_now()
      })
      |> Repo.update()

    Logger.debug(
      "[QB Sync] update_sync_failure_refund: Refund updated with failure",
      refund_id: refund.id,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  # Update functions for Payout
  defp update_sync_status_payout(%Payout{} = payout, status, error, response) do
    Logger.debug(
      "[QB Sync] update_sync_status_payout: Updating payout sync status",
      payout_id: payout.id,
      status: status
    )

    result =
      payout
      |> Payout.changeset(%{
        quickbooks_sync_status: status,
        quickbooks_sync_error: error,
        quickbooks_response: response,
        quickbooks_last_sync_attempt_at: DateTime.utc_now()
      })
      |> Repo.update()

    Logger.debug("[QB Sync] update_sync_status_payout: Payout status updated",
      payout_id: payout.id,
      status: status,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  defp update_sync_success_payout(%Payout{} = payout, deposit_id, response) do
    Logger.debug(
      "[QB Sync] update_sync_success_payout: Updating payout with sync success",
      payout_id: payout.id,
      deposit_id: deposit_id
    )

    result =
      payout
      |> Payout.changeset(%{
        quickbooks_deposit_id: deposit_id,
        quickbooks_sync_status: "synced",
        quickbooks_synced_at: DateTime.utc_now(),
        quickbooks_response: response,
        quickbooks_last_sync_attempt_at: DateTime.utc_now()
      })
      |> Repo.update()

    Logger.debug(
      "[QB Sync] update_sync_success_payout: Payout updated with success",
      payout_id: payout.id,
      deposit_id: deposit_id,
      result: inspect(result, limit: :infinity)
    )

    result
  end

  defp update_sync_failure_payout(%Payout{} = payout, reason) do
    Logger.debug(
      "[QB Sync] update_sync_failure_payout: Updating payout with sync failure",
      payout_id: payout.id,
      reason: inspect(reason)
    )

    error_map = %{
      error: inspect(reason),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    result =
      payout
      |> Payout.changeset(%{
        quickbooks_sync_status: "failed",
        quickbooks_sync_error: error_map,
        quickbooks_last_sync_attempt_at: DateTime.utc_now()
      })
      |> Repo.update()

    Logger.debug(
      "[QB Sync] update_sync_failure_payout: Payout updated with failure",
      payout_id: payout.id,
      result: inspect(result, limit: :infinity)
    )

    result
  end
end
