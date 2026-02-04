defmodule Ysc.Ledgers do
  @moduledoc """
  The Ledgers context for managing double-entry accounting.

  This module provides utilities for:
  - Creating and managing ledger accounts
  - Processing payments with double-entry bookkeeping
  - Handling refunds and credits
  - Tracking Stripe fees
  - Managing subscription, event, and booking payments
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo

  alias Ysc.Ledgers.{
    LedgerAccount,
    LedgerEntry,
    LedgerTransaction,
    Payment,
    Refund,
    Payout
  }

  alias YscWeb.Workers.{
    QuickbooksSyncPaymentWorker,
    QuickbooksSyncRefundWorker
  }

  # Basic account names for the system
  # Format: {name, account_type, normal_balance, description}
  # Assets and Expenses are debit-normal
  # Liabilities, Revenue, and Equity are credit-normal
  @basic_accounts [
    # Asset accounts (debit-normal)
    {"cash", "asset", "debit", "Cash account for holding funds"},
    {"stripe_account", "asset", "debit", "Stripe account balance"},
    {"accounts_receivable", "asset", "debit",
     "Outstanding payments from customers"},

    # Liability accounts (credit-normal)
    {"accounts_payable", "liability", "credit",
     "Outstanding payments to vendors"},
    {"deferred_revenue", "liability", "credit",
     "Prepaid subscriptions and bookings"},
    {"refund_liability", "liability", "credit", "Pending refunds"},

    # Revenue accounts (credit-normal)
    {"membership_revenue", "revenue", "credit",
     "Revenue from membership subscriptions"},
    {"event_revenue", "revenue", "credit", "Revenue from event registrations"},
    {"tahoe_booking_revenue", "revenue", "credit",
     "Revenue from Tahoe cabin bookings"},
    {"clear_lake_booking_revenue", "revenue", "credit",
     "Revenue from Clear Lake cabin bookings"},
    {"donation_revenue", "revenue", "credit", "Revenue from donations"},

    # Expense accounts (debit-normal)
    {"stripe_fees", "expense", "debit", "Stripe processing fees"},
    {"operating_expenses", "expense", "debit", "General operating expenses"},
    {"refund_expense", "expense", "debit", "Refunds issued to customers"},
    {"discount_expense", "expense", "debit", "Reserved ticket discounts"}
  ]

  ## Account Management

  @doc """
  Ensures all basic ledger accounts exist in the system.
  Creates accounts if they don't exist.

  Uses INSERT ON CONFLICT DO NOTHING to avoid race conditions
  when multiple processes try to initialize accounts concurrently.
  """
  def ensure_basic_accounts do
    Enum.each(@basic_accounts, fn {name, type, normal_balance, description} ->
      # Use INSERT ON CONFLICT to avoid race condition
      # Unique constraint is on [:account_type, :name]
      %LedgerAccount{}
      |> LedgerAccount.changeset(%{
        name: name,
        account_type: type,
        normal_balance: normal_balance,
        description: description
      })
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:account_type, :name]
      )
    end)
  end

  @doc """
  Gets a ledger account by name.
  """
  def get_account_by_name(name) do
    Repo.get_by(LedgerAccount, name: name)
  end

  @doc """
  Gets all ledger accounts.
  """
  def list_accounts do
    Repo.all(LedgerAccount)
  end

  @doc """
  Gets a ledger account by ID.
  """
  def get_account(id), do: Repo.get(LedgerAccount, id)

  @doc """
  Creates a new ledger account.
  """
  def create_account(attrs \\ %{}) do
    %LedgerAccount{}
    |> LedgerAccount.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a ledger account.
  """
  def update_account(%LedgerAccount{} = account, attrs) do
    account
    |> LedgerAccount.changeset(attrs)
    |> Repo.update()
  end

  ## Payment Processing

  @doc """
  Processes a payment with double-entry bookkeeping.

  Creates:
  1. A payment record
  2. A ledger transaction
  3. Debit and credit entries

  ## Parameters:
  - `user_id`: The user making the payment
  - `amount`: Payment amount
  - `entity_type`: Type of entity being paid for (event, membership, booking, donation)
  - `entity_id`: ID of the entity being paid for
  - `external_payment_id`: External payment provider ID (e.g., Stripe payment intent)
  - `stripe_fee`: Stripe processing fee (optional)
  - `description`: Description of the payment
  - `property`: Property for booking payments (:tahoe, :clear_lake, or nil)
  - `payment_method_id`: ID of the payment method used (optional)
  """
  def process_payment(attrs) do
    %{
      user_id: user_id,
      amount: amount,
      entity_type: entity_type,
      entity_id: entity_id,
      external_payment_id: external_payment_id,
      stripe_fee: stripe_fee,
      description: description,
      property: property,
      payment_method_id: payment_method_id
    } = attrs

    ensure_basic_accounts()

    # Check if payment already exists (idempotency check)
    case get_payment_by_external_id(external_payment_id) do
      nil ->
        # Payment doesn't exist, create it
        Repo.transaction(fn ->
          # Create payment record
          {:ok, payment} =
            create_payment(%{
              user_id: user_id,
              amount: amount,
              external_provider: :stripe,
              external_payment_id: external_payment_id,
              status: :completed,
              payment_date: DateTime.utc_now(),
              payment_method_id: payment_method_id
            })

          # Create ledger transaction
          {:ok, transaction} =
            create_transaction(%{
              type: :payment,
              payment_id: payment.id,
              total_amount: amount,
              status: :completed
            })

          # Create double-entry entries
          entries =
            create_payment_entries(%{
              payment: payment,
              transaction: transaction,
              amount: amount,
              entity_type: entity_type,
              entity_id: entity_id,
              stripe_fee: stripe_fee,
              description: description,
              property: property
            })

          {payment, transaction, entries}
        end)

      existing_payment ->
        # Payment already exists - this is a duplicate request (e.g., from CashApp retry)
        # If payment is completed, return existing payment with its transaction and entries
        require Logger

        Logger.info("Payment already exists, returning existing payment",
          external_payment_id: external_payment_id,
          payment_id: existing_payment.id,
          status: existing_payment.status
        )

        if existing_payment.status == :completed do
          # Get existing transaction and entries
          transaction =
            from(t in LedgerTransaction,
              where: t.payment_id == ^existing_payment.id,
              limit: 1
            )
            |> Repo.one()

          entries = get_entries_by_payment(existing_payment.id)

          # Return existing payment data
          {:ok, {existing_payment, transaction, entries}}
        else
          # Payment exists but isn't completed - this is unexpected, return error
          {:error, :payment_exists_but_not_completed}
        end
    end
    |> case do
      {:ok, {payment, transaction, entries}} ->
        # Emit telemetry event for payment recording
        :telemetry.execute(
          [:ysc, :ledgers, :payment_recorded],
          %{count: 1},
          %{
            payment_id: payment.id,
            entity_type: to_string(entity_type),
            user_id: user_id,
            amount: Money.to_decimal(amount)
          }
        )

        # Enqueue QuickBooks sync job after successful payment creation
        enqueue_quickbooks_sync_payment(payment)
        {:ok, {payment, transaction, entries}}

      error ->
        # Report to Sentry
        require Logger

        Logger.error("Failed to process payment in ledger",
          user_id: user_id,
          amount: Money.to_string!(amount),
          entity_type: entity_type,
          entity_id: entity_id,
          external_payment_id: external_payment_id,
          error: inspect(error)
        )

        Sentry.capture_message("Failed to process payment in ledger",
          level: :error,
          extra: %{
            user_id: user_id,
            amount: Money.to_string!(amount),
            entity_type: inspect(entity_type),
            entity_id: entity_id,
            external_payment_id: external_payment_id,
            error: inspect(error)
          },
          tags: %{
            ledger_operation: "process_payment",
            entity_type: inspect(entity_type)
          }
        )

        error
    end
  end

  @doc """
  Processes an event payment that may include donations and discounts.

  This function handles ticket orders that contain regular tickets, donation tickets, and discounts.
  It creates separate revenue entries for event revenue, donation revenue, and discount expense entries.

  ## Parameters:
  - `user_id`: The user making the payment
  - `total_amount`: Total payment amount (net after discounts)
  - `gross_event_amount`: Gross event amount before discounts
  - `event_amount`: Amount for regular event tickets (same as gross_event_amount)
  - `donation_amount`: Amount for donation tickets
  - `discount_amount`: Total discount amount applied
  - `event_id`: Event ID
  - `external_payment_id`: External payment provider ID (e.g., Stripe payment intent)
  - `stripe_fee`: Stripe processing fee (optional)
  - `description`: Description of the payment
  - `payment_method_id`: ID of the payment method used (optional)
  - `ticket_order_id`: Ticket order ID for traceability (optional)
  """
  def process_event_payment_with_donations_and_discounts(attrs) do
    %{
      user_id: user_id,
      total_amount: total_amount,
      gross_event_amount: gross_event_amount,
      event_amount: _event_amount,
      donation_amount: donation_amount,
      discount_amount: discount_amount,
      event_id: event_id,
      external_payment_id: external_payment_id,
      stripe_fee: stripe_fee,
      description: description,
      payment_method_id: payment_method_id,
      ticket_order_id: ticket_order_id
    } = attrs

    ensure_basic_accounts()

    Repo.transaction(fn ->
      # Create payment record
      {:ok, payment} =
        create_payment(%{
          user_id: user_id,
          amount: total_amount,
          external_provider: :stripe,
          external_payment_id: external_payment_id,
          status: :completed,
          payment_date: DateTime.utc_now(),
          payment_method_id: payment_method_id
        })

      # Create ledger transaction
      {:ok, transaction} =
        create_transaction(%{
          type: :payment,
          payment_id: payment.id,
          total_amount: total_amount,
          status: :completed
        })

      # Create double-entry entries for mixed event/donation/discount payment
      entries =
        create_mixed_event_donation_discount_entries(%{
          payment: payment,
          transaction: transaction,
          total_amount: total_amount,
          gross_event_amount: gross_event_amount,
          donation_amount: donation_amount,
          discount_amount: discount_amount,
          event_id: event_id,
          stripe_fee: stripe_fee,
          description: description,
          ticket_order_id: ticket_order_id
        })

      {payment, transaction, entries}
    end)
    |> case do
      {:ok, {payment, transaction, entries}} ->
        # Enqueue QuickBooks sync job after successful payment creation
        enqueue_quickbooks_sync_payment(payment)
        {:ok, {payment, transaction, entries}}

      error ->
        # Report to Sentry
        require Logger

        Logger.error(
          "Failed to process event payment with donations and discounts in ledger",
          user_id: user_id,
          total_amount: Money.to_string!(total_amount),
          gross_event_amount: Money.to_string!(gross_event_amount),
          donation_amount: Money.to_string!(donation_amount),
          discount_amount: Money.to_string!(discount_amount),
          event_id: event_id,
          external_payment_id: external_payment_id,
          error: inspect(error)
        )

        Sentry.capture_message(
          "Failed to process event payment with discounts in ledger",
          level: :error,
          extra: %{
            user_id: user_id,
            total_amount: Money.to_string!(total_amount),
            gross_event_amount: Money.to_string!(gross_event_amount),
            donation_amount: Money.to_string!(donation_amount),
            discount_amount: Money.to_string!(discount_amount),
            event_id: event_id,
            external_payment_id: external_payment_id,
            error: inspect(error)
          },
          tags: %{
            ledger_operation: "process_event_payment_with_discounts",
            entity_type: "event"
          }
        )

        error
    end
  end

  @doc """
  Processes an event payment that may include donations.

  This function handles ticket orders that contain both regular tickets and donation tickets.
  It creates separate revenue entries for event revenue and donation revenue.

  ## Parameters:
  - `user_id`: The user making the payment
  - `total_amount`: Total payment amount
  - `event_amount`: Amount for regular event tickets
  - `donation_amount`: Amount for donation tickets
  - `event_id`: Event ID
  - `external_payment_id`: External payment provider ID (e.g., Stripe payment intent)
  - `stripe_fee`: Stripe processing fee (optional)
  - `description`: Description of the payment
  - `payment_method_id`: ID of the payment method used (optional)
  """
  def process_event_payment_with_donations(attrs) do
    %{
      user_id: user_id,
      total_amount: total_amount,
      event_amount: event_amount,
      donation_amount: donation_amount,
      event_id: event_id,
      external_payment_id: external_payment_id,
      stripe_fee: stripe_fee,
      description: description,
      payment_method_id: payment_method_id
    } = attrs

    ensure_basic_accounts()

    Repo.transaction(fn ->
      # Create payment record
      {:ok, payment} =
        create_payment(%{
          user_id: user_id,
          amount: total_amount,
          external_provider: :stripe,
          external_payment_id: external_payment_id,
          status: :completed,
          payment_date: DateTime.utc_now(),
          payment_method_id: payment_method_id
        })

      # Create ledger transaction
      {:ok, transaction} =
        create_transaction(%{
          type: :payment,
          payment_id: payment.id,
          total_amount: total_amount,
          status: :completed
        })

      # Create double-entry entries for mixed event/donation payment
      entries =
        create_mixed_event_donation_entries(%{
          payment: payment,
          transaction: transaction,
          total_amount: total_amount,
          event_amount: event_amount,
          donation_amount: donation_amount,
          event_id: event_id,
          stripe_fee: stripe_fee,
          description: description
        })

      {payment, transaction, entries}
    end)
    |> case do
      {:ok, {payment, transaction, entries}} ->
        # Enqueue QuickBooks sync job after successful payment creation
        enqueue_quickbooks_sync_payment(payment)
        {:ok, {payment, transaction, entries}}

      error ->
        # Report to Sentry
        require Logger

        Logger.error("Failed to process mixed event/donation payment in ledger",
          user_id: user_id,
          total_amount: Money.to_string!(total_amount),
          event_amount: Money.to_string!(event_amount),
          donation_amount: Money.to_string!(donation_amount),
          event_id: event_id,
          external_payment_id: external_payment_id,
          error: inspect(error)
        )

        Sentry.capture_message(
          "Failed to process mixed event/donation payment in ledger",
          level: :error,
          extra: %{
            user_id: user_id,
            total_amount: Money.to_string!(total_amount),
            event_amount: Money.to_string!(event_amount),
            donation_amount: Money.to_string!(donation_amount),
            event_id: event_id,
            external_payment_id: external_payment_id,
            error: inspect(error)
          },
          tags: %{
            ledger_operation: "process_mixed_event_donation_payment",
            entity_type: "event_donation"
          }
        )

        error
    end
  end

  defp enqueue_quickbooks_sync_payment(%Payment{} = payment) do
    # Mark payment as pending sync
    payment
    |> Payment.changeset(%{quickbooks_sync_status: "pending"})
    |> Repo.update()

    # Enqueue sync job
    %{payment_id: to_string(payment.id)}
    |> QuickbooksSyncPaymentWorker.new()
    |> Oban.insert()

    :ok
  rescue
    error ->
      require Logger

      Logger.warning("Failed to enqueue QuickBooks sync for payment",
        payment_id: payment.id,
        error: inspect(error)
      )

      # Report to Sentry
      Sentry.capture_exception(error,
        stacktrace: __STACKTRACE__,
        extra: %{
          payment_id: payment.id,
          error_message: Exception.message(error)
        },
        tags: %{
          ledger_operation: "enqueue_quickbooks_sync_payment"
        }
      )

      :ok
  end

  @doc """
  Creates a payment record.
  """
  def create_payment(attrs \\ %{}) do
    %Payment{}
    |> Payment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a refund record.
  """
  def create_refund(attrs \\ %{}) do
    %Refund{}
    |> Refund.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a ledger transaction.
  """
  def create_transaction(attrs \\ %{}) do
    %LedgerTransaction{}
    |> LedgerTransaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates double-entry ledger entries for a payment.

  NOTE: This function should be called within a Repo.transaction block
  to ensure atomicity of all entry creations.
  """
  def create_payment_entries(attrs) do
    %{
      payment: payment,
      amount: amount,
      entity_type: entity_type,
      entity_id: entity_id,
      stripe_fee: stripe_fee,
      description: description,
      property: property
    } = attrs

    # Determine revenue account based on entity type and property
    revenue_account_name =
      case entity_type do
        :membership ->
          "membership_revenue"

        :event ->
          "event_revenue"

        :booking ->
          case property do
            :tahoe ->
              "tahoe_booking_revenue"

            :clear_lake ->
              "clear_lake_booking_revenue"

            _ ->
              require Logger

              error_message =
                "Booking payment requires property to be specified (tahoe or clear_lake)"

              Logger.warning(
                error_message,
                entity_id: entity_id,
                property: property
              )

              # Report to Sentry before raising
              Sentry.capture_message(error_message,
                level: :error,
                extra: %{
                  entity_id: entity_id,
                  property: inspect(property),
                  entity_type: "booking"
                },
                tags: %{
                  ledger_operation: "create_payment_entries",
                  entity_type: "booking",
                  error_type: "missing_property"
                }
              )

              raise error_message
          end

        :donation ->
          "donation_revenue"

        _ ->
          "membership_revenue"
      end

    revenue_account = get_account_by_name(revenue_account_name)

    unless revenue_account do
      raise "Revenue account '#{revenue_account_name}' not found"
    end

    stripe_receivable_account = get_account_by_name("stripe_account")

    unless stripe_receivable_account do
      raise "Stripe account not found"
    end

    # Entry 1: Debit Stripe Receivable (Asset) - money owed to us by Stripe
    {:ok, stripe_receivable_entry} =
      create_entry(%{
        account_id: stripe_receivable_account.id,
        payment_id: payment.id,
        amount: amount,
        debit_credit: :debit,
        description: "Payment receivable from Stripe: #{description}",
        related_entity_type: entity_type,
        related_entity_id: entity_id
      })

    # Entry 2: Credit Revenue (explicit credit with positive amount)
    {:ok, revenue_entry} =
      create_entry(%{
        account_id: revenue_account.id,
        payment_id: payment.id,
        amount: amount,
        debit_credit: :credit,
        description: "Revenue from #{entity_type}: #{description}",
        related_entity_type: entity_type,
        related_entity_id: entity_id
      })

    # Entry 3: If there's a Stripe fee, track the flow through Stripe account
    entries =
      if stripe_fee && Money.positive?(stripe_fee) do
        stripe_fee_account = get_account_by_name("stripe_fees")

        unless stripe_fee_account do
          raise "Stripe fees account not found"
        end

        stripe_account = get_account_by_name("stripe_account")

        unless stripe_account do
          raise "Stripe account not found"
        end

        # Entry 3a: Debit Stripe Fee Expense
        {:ok, fee_expense_entry} =
          create_entry(%{
            account_id: stripe_fee_account.id,
            payment_id: payment.id,
            amount: stripe_fee,
            debit_credit: :debit,
            description:
              "Stripe processing fee for payment #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        # Entry 3b: Credit Stripe Account (reducing receivable by fee amount)
        {:ok, stripe_fee_deduction_entry} =
          create_entry(%{
            account_id: stripe_account.id,
            payment_id: payment.id,
            amount: stripe_fee,
            debit_credit: :credit,
            description:
              "Stripe fee deduction from receivable - #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        [
          stripe_receivable_entry,
          revenue_entry,
          fee_expense_entry,
          stripe_fee_deduction_entry
        ]
      else
        [stripe_receivable_entry, revenue_entry]
      end

    entries
  end

  @doc """
  Creates double-entry ledger entries for a mixed event/donation payment.

  This handles ticket orders that contain both regular tickets and donation tickets.
  Creates separate revenue entries for each type while maintaining double-entry balance.

  NOTE: This function should be called within a Repo.transaction block
  to ensure atomicity of all entry creations.
  """
  def create_mixed_event_donation_entries(attrs) do
    %{
      payment: payment,
      total_amount: total_amount,
      event_amount: event_amount,
      donation_amount: donation_amount,
      event_id: event_id,
      stripe_fee: stripe_fee,
      description: description
    } = attrs

    entries = []

    stripe_receivable_account = get_account_by_name("stripe_account")

    unless stripe_receivable_account do
      raise "Stripe account not found"
    end

    event_revenue_account = get_account_by_name("event_revenue")

    unless event_revenue_account do
      raise "Event revenue account not found"
    end

    donation_revenue_account = get_account_by_name("donation_revenue")

    unless donation_revenue_account do
      raise "Donation revenue account not found"
    end

    # Entry 1: Debit Stripe Receivable (Asset) - money owed to us by Stripe
    {:ok, stripe_receivable_entry} =
      create_entry(%{
        account_id: stripe_receivable_account.id,
        payment_id: payment.id,
        amount: total_amount,
        debit_credit: :debit,
        description: "Payment receivable from Stripe: #{description}",
        related_entity_type: :event,
        related_entity_id: event_id
      })

    entries = [stripe_receivable_entry | entries]

    # Entry 2a: Credit Event Revenue (if there's event revenue)
    entries =
      if Money.positive?(event_amount) do
        {:ok, event_revenue_entry} =
          create_entry(%{
            account_id: event_revenue_account.id,
            payment_id: payment.id,
            amount: event_amount,
            debit_credit: :credit,
            description: "Event revenue from tickets: #{description}",
            related_entity_type: :event,
            related_entity_id: event_id
          })

        [event_revenue_entry | entries]
      else
        entries
      end

    # Entry 2b: Credit Donation Revenue (if there's donation revenue)
    entries =
      if Money.positive?(donation_amount) do
        {:ok, donation_revenue_entry} =
          create_entry(%{
            account_id: donation_revenue_account.id,
            payment_id: payment.id,
            amount: donation_amount,
            debit_credit: :credit,
            description: "Donation revenue from tickets: #{description}",
            related_entity_type: :donation,
            related_entity_id: event_id
          })

        [donation_revenue_entry | entries]
      else
        entries
      end

    # Entry 3: If there's a Stripe fee, track the flow through Stripe account
    # We'll assign the fee proportionally or to event revenue (simpler approach)
    entries =
      if stripe_fee && Money.positive?(stripe_fee) do
        stripe_fee_account = get_account_by_name("stripe_fees")

        unless stripe_fee_account do
          raise "Stripe fees account not found"
        end

        stripe_account = get_account_by_name("stripe_account")

        unless stripe_account do
          raise "Stripe account not found"
        end

        # Entry 3a: Debit Stripe Fee Expense
        {:ok, fee_expense_entry} =
          create_entry(%{
            account_id: stripe_fee_account.id,
            payment_id: payment.id,
            amount: stripe_fee,
            debit_credit: :debit,
            description:
              "Stripe processing fee for payment #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        # Entry 3b: Credit Stripe Account (reducing receivable by fee amount)
        {:ok, stripe_fee_deduction_entry} =
          create_entry(%{
            account_id: stripe_account.id,
            payment_id: payment.id,
            amount: stripe_fee,
            debit_credit: :credit,
            description:
              "Stripe fee deduction from receivable - #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        [fee_expense_entry, stripe_fee_deduction_entry | entries]
      else
        entries
      end

    entries
  end

  defp create_mixed_event_donation_discount_entries(attrs) do
    %{
      payment: payment,
      total_amount: total_amount,
      gross_event_amount: gross_event_amount,
      donation_amount: donation_amount,
      discount_amount: discount_amount,
      event_id: event_id,
      stripe_fee: stripe_fee,
      description: description,
      ticket_order_id: ticket_order_id
    } = attrs

    entries = []

    stripe_receivable_account = get_account_by_name("stripe_account")

    unless stripe_receivable_account do
      raise "Stripe account not found"
    end

    event_revenue_account = get_account_by_name("event_revenue")

    unless event_revenue_account do
      raise "Event revenue account not found"
    end

    donation_revenue_account = get_account_by_name("donation_revenue")

    unless donation_revenue_account do
      raise "Donation revenue account not found"
    end

    discount_expense_account = get_account_by_name("discount_expense")

    unless discount_expense_account do
      raise "Discount expense account not found"
    end

    # Entry 1: Debit Stripe Receivable (Asset) - money owed to us by Stripe (net amount received)
    {:ok, stripe_receivable_entry} =
      create_entry(%{
        account_id: stripe_receivable_account.id,
        payment_id: payment.id,
        amount: total_amount,
        debit_credit: :debit,
        description: "Payment receivable from Stripe: #{description}",
        related_entity_type: :event,
        related_entity_id: event_id
      })

    entries = [stripe_receivable_entry | entries]

    # Entry 2: Credit Event Revenue (gross amount before discounts)
    # We credit the gross revenue first, then reduce it with discount entries
    entries =
      if Money.positive?(gross_event_amount) do
        {:ok, event_revenue_entry} =
          create_entry(%{
            account_id: event_revenue_account.id,
            payment_id: payment.id,
            amount: gross_event_amount,
            debit_credit: :credit,
            description: "Event revenue from tickets: #{description}",
            related_entity_type: :event,
            related_entity_id: event_id
          })

        [event_revenue_entry | entries]
      else
        entries
      end

    # Entry 3 & 4: Discount entries (if discounts were applied)
    # The discount reduces revenue, so we:
    # - Debit Event Revenue (to reduce the gross revenue credit to net)
    # - Credit Discount Expense (to balance the debit and track the discount)
    # This properly balances: revenue reduction (debit) is offset by discount expense credit
    entries =
      if Money.positive?(discount_amount) do
        # Entry 3: Debit Event Revenue (reducing revenue by discount amount)
        {:ok, discount_revenue_reduction_entry} =
          create_entry(%{
            account_id: event_revenue_account.id,
            payment_id: payment.id,
            amount: discount_amount,
            debit_credit: :debit,
            description:
              "Revenue reduction from discount - Order #{ticket_order_id || "N/A"}",
            related_entity_type: :event,
            related_entity_id: event_id
          })

        # Entry 4: Credit Discount Expense (to balance the revenue reduction debit)
        # This tracks the discount as an expense while balancing the entry
        {:ok, discount_expense_entry} =
          create_entry(%{
            account_id: discount_expense_account.id,
            payment_id: payment.id,
            amount: discount_amount,
            debit_credit: :credit,
            description:
              "Reserved ticket discount - Order #{ticket_order_id || "N/A"}",
            related_entity_type: :event,
            related_entity_id: event_id
          })

        [discount_expense_entry, discount_revenue_reduction_entry | entries]
      else
        entries
      end

    # Entry 5: Credit Donation Revenue (if there are donations)
    entries =
      if Money.positive?(donation_amount) do
        {:ok, donation_revenue_entry} =
          create_entry(%{
            account_id: donation_revenue_account.id,
            payment_id: payment.id,
            amount: donation_amount,
            debit_credit: :credit,
            description: "Donation revenue from tickets: #{description}",
            related_entity_type: :donation,
            related_entity_id: event_id
          })

        [donation_revenue_entry | entries]
      else
        entries
      end

    # Entry 6: Stripe fee entries (if there's a fee)
    entries =
      if stripe_fee && Money.positive?(stripe_fee) do
        stripe_fee_account = get_account_by_name("stripe_fees")

        unless stripe_fee_account do
          raise "Stripe fees account not found"
        end

        stripe_account = get_account_by_name("stripe_account")

        unless stripe_account do
          raise "Stripe account not found"
        end

        # Entry 6a: Debit Stripe Fee Expense
        {:ok, fee_expense_entry} =
          create_entry(%{
            account_id: stripe_fee_account.id,
            payment_id: payment.id,
            amount: stripe_fee,
            debit_credit: :debit,
            description:
              "Stripe processing fee for payment #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        # Entry 6b: Credit Stripe Account (reducing receivable by fee amount)
        {:ok, stripe_fee_deduction_entry} =
          create_entry(%{
            account_id: stripe_account.id,
            payment_id: payment.id,
            amount: stripe_fee,
            debit_credit: :credit,
            description:
              "Stripe fee deduction from receivable - #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        [fee_expense_entry, stripe_fee_deduction_entry | entries]
      else
        entries
      end

    entries
  end

  @doc """
  Creates a ledger entry.
  """
  def create_entry(attrs \\ %{}) do
    %LedgerEntry{}
    |> LedgerEntry.changeset(attrs)
    |> Repo.insert()
  end

  ## Refund Management

  @doc """
  Processes a refund with double-entry bookkeeping.

  ## Parameters:
  - `payment_id`: Original payment ID
  - `refund_amount`: Amount to refund (can be partial)
  - `reason`: Reason for refund
  - `external_refund_id`: External refund ID from payment provider
  """
  def process_refund(attrs) do
    %{
      payment_id: payment_id,
      refund_amount: refund_amount,
      reason: reason,
      external_refund_id: external_refund_id
    } = attrs

    ensure_basic_accounts()

    Repo.transaction(fn ->
      # Get original payment
      payment = Repo.get!(Payment, payment_id)

      # Check if this refund has already been processed (idempotency)
      if external_refund_id do
        existing_refund = get_refund_by_external_id(external_refund_id)

        if existing_refund do
          require Logger

          Logger.info(
            "Refund already processed, returning existing refund (idempotency)",
            external_refund_id: external_refund_id,
            refund_id: existing_refund.id
          )

          # Find the transaction for this refund
          existing_transaction =
            from(t in LedgerTransaction,
              where: t.refund_id == ^existing_refund.id,
              where: t.type == "refund"
            )
            |> Repo.one()

          # Return the existing refund wrapped in the error tuple for the caller to handle
          Repo.rollback(
            {:already_processed, existing_refund, existing_transaction}
          )
        end
      end

      # Create refund record
      {:ok, refund} =
        create_refund(%{
          payment_id: payment_id,
          user_id: payment.user_id,
          amount: refund_amount,
          external_provider: :stripe,
          external_refund_id: external_refund_id,
          reason: reason,
          status: :completed
        })

      # Create refund transaction
      {:ok, refund_transaction} =
        create_transaction(%{
          type: :refund,
          payment_id: payment_id,
          refund_id: refund.id,
          total_amount: refund_amount,
          status: :completed
        })

      # Create double-entry entries for refund
      entries =
        create_refund_entries(%{
          payment: payment,
          refund: refund,
          transaction: refund_transaction,
          refund_amount: refund_amount,
          reason: reason
        })

      # Update original payment status if fully refunded
      if Money.equal?(refund_amount, payment.amount) do
        update_payment(payment, %{status: :refunded})
      end

      {refund, refund_transaction, entries}
    end)
    |> case do
      {:ok, {refund, refund_transaction, entries}} ->
        # Emit telemetry event for refund recording
        :telemetry.execute(
          [:ysc, :ledgers, :refund_recorded],
          %{count: 1},
          %{
            refund_id: refund.id,
            payment_id: payment_id,
            user_id: refund.user_id,
            amount: Money.to_decimal(refund_amount)
          }
        )

        # Enqueue QuickBooks sync job after successful refund creation
        enqueue_quickbooks_sync_refund(refund)
        # Send refund confirmation email
        # Reload payment with associations for email
        payment = get_payment_with_associations(payment_id)
        send_refund_email(refund, payment)
        {:ok, {refund, refund_transaction, entries}}

      {:error, {:already_processed, existing_refund, existing_transaction}} ->
        # Refund was already processed, return it
        {:ok, {existing_refund, existing_transaction, []}}

      error ->
        # Report to Sentry
        require Logger

        Logger.error("Failed to process refund in ledger",
          payment_id: payment_id,
          refund_amount: Money.to_string!(refund_amount),
          external_refund_id: external_refund_id,
          error: inspect(error)
        )

        Sentry.capture_message("Failed to process refund in ledger",
          level: :error,
          extra: %{
            payment_id: payment_id,
            refund_amount: Money.to_string!(refund_amount),
            external_refund_id: external_refund_id,
            error: inspect(error)
          },
          tags: %{
            ledger_operation: "process_refund"
          }
        )

        error
    end
  end

  defp send_refund_email(refund, payment) do
    require Logger

    try do
      # Reload payment with associations
      payment = get_payment_with_associations(payment.id)

      if payment.user do
        # Determine if this is for a booking or ticket order
        case get_payment_related_entity(payment) do
          {:booking, booking} ->
            # Send booking refund processed email
            send_booking_refund_processed_email(refund, booking, payment)

          {:ticket_order, ticket_order} ->
            # Send ticket order refund email
            send_ticket_order_refund_email(refund, ticket_order)

          _ ->
            # Unknown entity type, skip email
            Logger.debug("Skipping refund email - unknown entity type",
              refund_id: refund.id,
              payment_id: payment.id
            )
        end
      else
        Logger.warning("Skipping refund email - payment missing user",
          refund_id: refund.id,
          payment_id: payment.id
        )
      end
    rescue
      error ->
        Logger.error("Failed to send refund email",
          refund_id: refund.id,
          payment_id: payment.id,
          error: inspect(error),
          stacktrace: __STACKTRACE__
        )

        # Report to Sentry
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            refund_id: refund.id,
            payment_id: payment.id,
            error_message: Exception.message(error)
          },
          tags: %{
            ledger_operation: "send_refund_email"
          }
        )
    end
  end

  defp send_booking_refund_processed_email(refund, booking, payment) do
    require Logger

    try do
      # Reload booking with associations
      booking =
        Repo.get(Ysc.Bookings.Booking, booking.id) |> Repo.preload(:user)

      if booking && booking.user && payment && payment.user do
        # Prepare email data
        email_data =
          YscWeb.Emails.BookingRefundProcessed.prepare_email_data(
            refund,
            booking,
            payment
          )

        # Generate idempotency key
        idempotency_key = "booking_refund_processed_#{refund.id}"

        # Schedule email
        result =
          YscWeb.Emails.Notifier.schedule_email(
            payment.user.email,
            idempotency_key,
            YscWeb.Emails.BookingRefundProcessed.get_subject(),
            "booking_refund_processed",
            email_data,
            "",
            payment.user_id
          )

        case result do
          %Oban.Job{} = job ->
            Logger.info("Booking refund processed email scheduled successfully",
              refund_id: refund.id,
              booking_id: booking.id,
              user_id: payment.user_id,
              user_email: payment.user.email,
              job_id: job.id
            )

          {:error, reason} ->
            Logger.error("Failed to schedule booking refund processed email",
              refund_id: refund.id,
              booking_id: booking.id,
              user_id: payment.user_id,
              error: reason
            )
        end
      else
        Logger.warning(
          "Skipping booking refund processed email - missing booking or user",
          refund_id: refund.id,
          booking_id: booking && booking.id
        )
      end
    rescue
      error ->
        Logger.error("Failed to send booking refund processed email",
          refund_id: refund.id,
          booking_id: booking && booking.id,
          error: inspect(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  defp send_ticket_order_refund_email(refund, ticket_order) do
    require Logger

    try do
      # Reload ticket order with associations
      ticket_order =
        case Ysc.Tickets.get_ticket_order(ticket_order.id) do
          nil ->
            Logger.warning("Ticket order not found for refund email",
              refund_id: refund.id,
              ticket_order_id: ticket_order.id
            )

            nil

          loaded_order ->
            loaded_order
        end

      if ticket_order && ticket_order.user do
        # Get refunded tickets - we need to find which tickets were refunded
        # For now, we'll get all tickets from the order and filter by cancelled status
        # This is a simplification - ideally we'd track which specific tickets were refunded
        refunded_tickets =
          from(t in Ysc.Events.Ticket,
            where: t.ticket_order_id == ^ticket_order.id,
            where: t.status == :cancelled,
            preload: [:ticket_tier]
          )
          |> Repo.all()

        if Enum.empty?(refunded_tickets) do
          Logger.warning(
            "No refunded tickets found for ticket order refund email",
            refund_id: refund.id,
            ticket_order_id: ticket_order.id
          )
        else
          # Prepare email data
          email_data =
            YscWeb.Emails.TicketOrderRefund.prepare_email_data(
              refund,
              ticket_order,
              refunded_tickets
            )

          # Generate idempotency key
          idempotency_key = "ticket_order_refund_#{refund.id}"

          # Schedule email
          result =
            YscWeb.Emails.Notifier.schedule_email(
              ticket_order.user.email,
              idempotency_key,
              YscWeb.Emails.TicketOrderRefund.get_subject(),
              "ticket_order_refund",
              email_data,
              "",
              ticket_order.user_id
            )

          case result do
            %Oban.Job{} = job ->
              Logger.info("Ticket order refund email scheduled successfully",
                refund_id: refund.id,
                ticket_order_id: ticket_order.id,
                user_id: ticket_order.user_id,
                user_email: ticket_order.user.email,
                job_id: job.id
              )

            {:error, reason} ->
              Logger.error("Failed to schedule ticket order refund email",
                refund_id: refund.id,
                ticket_order_id: ticket_order.id,
                user_id: ticket_order.user_id,
                error: reason
              )
          end
        end
      else
        Logger.warning(
          "Skipping ticket order refund email - missing ticket order or user",
          refund_id: refund.id,
          ticket_order_id: ticket_order && ticket_order.id
        )
      end
    rescue
      error ->
        Logger.error("Failed to send ticket order refund email",
          refund_id: refund.id,
          ticket_order_id: ticket_order && ticket_order.id,
          error: inspect(error),
          stacktrace: __STACKTRACE__
        )
    end
  end

  defp enqueue_quickbooks_sync_refund(%Refund{} = refund) do
    # Mark refund as pending sync
    refund
    |> Refund.changeset(%{quickbooks_sync_status: "pending"})
    |> Repo.update()

    # Enqueue sync job
    %{refund_id: to_string(refund.id)}
    |> QuickbooksSyncRefundWorker.new()
    |> Oban.insert()

    :ok
  rescue
    error ->
      require Logger

      Logger.warning("Failed to enqueue QuickBooks sync for refund",
        refund_id: refund.id,
        error: inspect(error)
      )

      :ok
  end

  @doc """
  Creates double-entry ledger entries for a refund.

  Uses revenue reversal approach: reverses the original payment entries
  by debiting revenue and crediting the stripe account.

  For a $100 refund:
  - DR: Revenue $100 (reverses original revenue recognition)
  - CR: Stripe Account $100 (reduces receivable)

  NOTE: This function should be called within a Repo.transaction block
  to ensure atomicity of all entry creations.
  """
  def create_refund_entries(attrs) do
    %{
      payment: payment,
      refund: refund,
      refund_amount: refund_amount,
      reason: reason
    } = attrs

    # Determine original revenue account
    original_entries = get_entries_by_payment(payment.id)

    # Find the revenue entry (should be a credit entry)
    revenue_entry =
      Enum.find(original_entries, fn entry ->
        # Convert to strings to handle EctoEnum atoms
        to_string(entry.account.account_type) == "revenue" &&
          to_string(entry.debit_credit) == "credit"
      end)

    unless revenue_entry do
      raise "Cannot process refund: no revenue entry found for payment #{payment.id}"
    end

    stripe_account = get_account_by_name("stripe_account")

    unless stripe_account do
      raise "Cannot process refund: stripe_account not found"
    end

    # Entry 1: Debit revenue account (reverses original revenue)
    {:ok, revenue_reversal_entry} =
      create_entry(%{
        account_id: revenue_entry.account_id,
        payment_id: payment.id,
        refund_id: refund.id,
        amount: refund_amount,
        debit_credit: :debit,
        description: "Revenue reversal for refund: #{reason}",
        related_entity_type: revenue_entry.related_entity_type,
        related_entity_id: revenue_entry.related_entity_id
      })

    # Entry 2: Credit stripe_account (reduces receivable)
    {:ok, stripe_credit_entry} =
      create_entry(%{
        account_id: stripe_account.id,
        payment_id: payment.id,
        refund_id: refund.id,
        amount: refund_amount,
        debit_credit: :credit,
        description: "Stripe account reduction for refund: #{reason}",
        related_entity_type: revenue_entry.related_entity_type,
        related_entity_id: revenue_entry.related_entity_id
      })

    [revenue_reversal_entry, stripe_credit_entry]
  end

  ## Stripe Payout Management

  @doc """
  Processes a Stripe payout - moves money from Stripe receivable to Cash.

  ## Parameters:
  - `payout_amount`: Amount being paid out by Stripe
  - `stripe_payout_id`: Stripe payout ID
  - `description`: Description of the payout
  - `currency`: Currency code (optional, defaults to :USD)
  - `status`: Payout status (optional, defaults to "paid")
  - `arrival_date`: When the payout arrives (optional)
  - `metadata`: Additional metadata (optional)
  - `fee_total`: Total fees charged by Stripe for this payout (optional)
  """
  def process_stripe_payout(attrs) do
    %{
      payout_amount: payout_amount,
      stripe_payout_id: stripe_payout_id,
      description: description
    } = attrs

    currency = Map.get(attrs, :currency, "usd")
    status = Map.get(attrs, :status, "paid")
    arrival_date = Map.get(attrs, :arrival_date)
    metadata = Map.get(attrs, :metadata, %{})
    fee_total = Map.get(attrs, :fee_total)

    ensure_basic_accounts()

    Repo.transaction(fn ->
      # Create a virtual payment record for the payout
      {:ok, payout_payment} =
        create_payment(%{
          # System payout, not user-specific
          user_id: nil,
          amount: payout_amount,
          external_provider: :stripe,
          external_payment_id: stripe_payout_id,
          status: :completed,
          payment_date: DateTime.utc_now()
        })

      # Create transaction
      {:ok, transaction} =
        create_transaction(%{
          type: :payout,
          payment_id: payout_payment.id,
          total_amount: payout_amount,
          status: :completed
        })

      # Create double-entry entries
      entries =
        create_payout_entries(%{
          payment: payout_payment,
          transaction: transaction,
          payout_amount: payout_amount,
          description: description
        })

      # Create payout record
      {:ok, payout} =
        create_payout(%{
          stripe_payout_id: stripe_payout_id,
          amount: payout_amount,
          fee_total: fee_total,
          currency: currency,
          status: status,
          arrival_date: arrival_date,
          description: description,
          metadata: metadata,
          payment_id: payout_payment.id
        })

      {payout_payment, transaction, entries, payout}
    end)
    |> case do
      {:ok, {payout_payment, transaction, entries, payout}} ->
        # Don't enqueue QuickBooks sync yet - wait for payments/refunds to be linked
        # The sync will be triggered after linking is complete (see webhook handler)
        {:ok, {payout_payment, transaction, entries, payout}}

      error ->
        error
    end
  end

  @doc """
  Creates double-entry ledger entries for a Stripe payout.
  """
  def create_payout_entries(attrs) do
    %{
      payment: payment,
      payout_amount: payout_amount,
      description: description
    } = attrs

    entries = []

    cash_account = get_account_by_name("cash")
    stripe_account = get_account_by_name("stripe_account")

    # Entry 1: Debit Cash (Asset) - money coming into our bank account
    {:ok, cash_entry} =
      create_entry(%{
        account_id: cash_account.id,
        payment_id: payment.id,
        amount: payout_amount,
        debit_credit: :debit,
        description: "Stripe payout received: #{description}",
        related_entity_type: :administration,
        related_entity_id: payment.id
      })

    entries = [cash_entry | entries]

    # Entry 2: Credit Stripe Account (Asset) - reducing our receivable
    {:ok, stripe_credit_entry} =
      create_entry(%{
        account_id: stripe_account.id,
        payment_id: payment.id,
        amount: payout_amount,
        debit_credit: :credit,
        description: "Stripe payout processed: #{description}",
        related_entity_type: :administration,
        related_entity_id: payment.id
      })

    entries = [stripe_credit_entry | entries]

    entries
  end

  ## Payout Management

  @doc """
  Creates a payout record.
  """
  def create_payout(attrs \\ %{}) do
    %Payout{}
    |> Payout.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a payout by Stripe payout ID.
  """
  def get_payout_by_stripe_id(stripe_payout_id) do
    Repo.get_by(Payout, stripe_payout_id: stripe_payout_id)
  end

  @doc """
  Gets a payout by ID with preloaded payments and refunds (including their users).
  """
  def get_payout!(id) do
    Repo.get!(Payout, id)
    |> Repo.preload([:payment, payments: :user, refunds: :user])
  end

  @doc """
  Links a payment to a payout.
  """
  def link_payment_to_payout(payout, payment) do
    # Check if already linked
    # Convert ULIDs to binary for comparison with join table's binary_id columns
    payout_id_binary =
      case Ecto.ULID.dump(payout.id) do
        {:ok, binary} -> binary
        _ -> payout.id
      end

    payment_id_binary =
      case Ecto.ULID.dump(payment.id) do
        {:ok, binary} -> binary
        _ -> payment.id
      end

    existing_link =
      from(pp in "payout_payments",
        where:
          pp.payout_id == ^payout_id_binary and
            pp.payment_id == ^payment_id_binary,
        select: pp.id,
        limit: 1
      )
      |> Repo.one()

    if existing_link do
      {:ok, payout}
    else
      # Insert directly into join table instead of using put_assoc
      # This avoids changeset validation issues with many-to-many associations
      payout_id_binary =
        case Ecto.ULID.dump(payout.id) do
          {:ok, binary} -> binary
          _ -> payout.id
        end

      payment_id_binary =
        case Ecto.ULID.dump(payment.id) do
          {:ok, binary} -> binary
          _ -> payment.id
        end

      join_table_id =
        Ecto.ULID.generate()
        |> Ecto.ULID.dump()
        |> case do
          {:ok, binary} -> binary
          _ -> raise "Failed to dump ULID to binary"
        end

      Repo.insert_all("payout_payments", [
        %{
          id: join_table_id,
          payout_id: payout_id_binary,
          payment_id: payment_id_binary,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ])

      {:ok, Repo.reload!(payout)}
    end
  end

  @doc """
  Links a refund to a payout.
  """
  def link_refund_to_payout(payout, refund) do
    # Check if already linked
    # Convert ULIDs to binary for comparison with join table's binary_id columns
    payout_id_binary =
      case Ecto.ULID.dump(payout.id) do
        {:ok, binary} -> binary
        _ -> payout.id
      end

    refund_id_binary =
      case Ecto.ULID.dump(refund.id) do
        {:ok, binary} -> binary
        _ -> refund.id
      end

    existing_link =
      from(pr in "payout_refunds",
        where:
          pr.payout_id == ^payout_id_binary and
            pr.refund_id == ^refund_id_binary,
        select: pr.id,
        limit: 1
      )
      |> Repo.one()

    if existing_link do
      {:ok, payout}
    else
      # Insert directly into join table instead of using put_assoc
      # This avoids changeset validation issues with many-to-many associations
      join_table_id =
        Ecto.ULID.generate()
        |> Ecto.ULID.dump()
        |> case do
          {:ok, binary} -> binary
          _ -> raise "Failed to dump ULID to binary"
        end

      Repo.insert_all("payout_refunds", [
        %{
          id: join_table_id,
          payout_id: payout_id_binary,
          refund_id: refund_id_binary,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ])

      {:ok, Repo.reload!(payout)}
    end
  end

  @doc """
  Gets all payments linked to a payout with preloaded associations.
  """
  def get_payout_payments(payout_id) do
    # Convert ULID to binary for comparison with join table's binary_id column
    payout_id_binary =
      cond do
        is_binary(payout_id) and byte_size(payout_id) == 16 ->
          # Already a binary UUID
          payout_id

        is_binary(payout_id) ->
          # ULID string, convert to binary
          case Ecto.ULID.dump(payout_id) do
            {:ok, binary} -> binary
            _ -> payout_id
          end

        true ->
          payout_id
      end

    from(p in Payment,
      join: pp in "payout_payments",
      on: pp.payment_id == p.id,
      where: pp.payout_id == ^payout_id_binary,
      preload: [:user, :payment_method]
    )
    |> Repo.all()
  end

  @doc """
  Gets all refunds linked to a payout.
  """
  def get_payout_refunds(payout_id) do
    # Convert ULID to binary for comparison with join table's binary_id column
    payout_id_binary =
      cond do
        is_binary(payout_id) and byte_size(payout_id) == 16 ->
          # Already a binary UUID
          payout_id

        is_binary(payout_id) ->
          # ULID string, convert to binary
          case Ecto.ULID.dump(payout_id) do
            {:ok, binary} -> binary
            _ -> payout_id
          end

        true ->
          payout_id
      end

    from(r in Refund,
      join: pr in "payout_refunds",
      on: pr.refund_id == r.id,
      where: pr.payout_id == ^payout_id_binary,
      preload: [:payment, :user]
    )
    |> Repo.all()
  end

  ## Credit Management

  @doc """
  Adds credit to a user's account.

  ## Parameters:
  - `user_id`: User to credit
  - `amount`: Credit amount
  - `reason`: Reason for credit
  - `entity_type`: Type of entity (optional)
  - `entity_id`: Entity ID (optional)
  """
  def add_credit(attrs) do
    %{
      user_id: user_id,
      amount: amount,
      reason: reason,
      entity_type: entity_type,
      entity_id: entity_id
    } = attrs

    ensure_basic_accounts()

    Repo.transaction(fn ->
      # Create a virtual payment for the credit
      {:ok, credit_payment} =
        create_payment(%{
          user_id: user_id,
          amount: amount,
          external_provider: :stripe,
          external_payment_id: "credit_#{Ecto.ULID.generate()}",
          status: :completed,
          payment_date: DateTime.utc_now()
        })

      # Create transaction
      {:ok, transaction} =
        create_transaction(%{
          type: :adjustment,
          payment_id: credit_payment.id,
          total_amount: amount,
          status: :completed
        })

      # Create double-entry entries
      entries =
        create_credit_entries(%{
          payment: credit_payment,
          transaction: transaction,
          amount: amount,
          reason: reason,
          entity_type: entity_type,
          entity_id: entity_id
        })

      {credit_payment, transaction, entries}
    end)
  end

  @doc """
  Creates double-entry ledger entries for a credit.
  """
  def create_credit_entries(attrs) do
    %{
      payment: payment,
      amount: amount,
      reason: reason,
      entity_type: entity_type,
      entity_id: entity_id
    } = attrs

    entries = []

    cash_account = get_account_by_name("cash")
    accounts_receivable_account = get_account_by_name("accounts_receivable")

    # Entry 1: Debit Accounts Receivable (Asset)
    {:ok, ar_entry} =
      create_entry(%{
        account_id: accounts_receivable_account.id,
        payment_id: payment.id,
        amount: amount,
        debit_credit: :debit,
        description: "Credit issued: #{reason}",
        related_entity_type: entity_type || :administration,
        related_entity_id: entity_id || payment.id
      })

    entries = [ar_entry | entries]

    # Entry 2: Credit Cash (Asset) - This represents the liability to the customer
    {:ok, cash_entry} =
      create_entry(%{
        account_id: cash_account.id,
        payment_id: payment.id,
        amount: amount,
        debit_credit: :credit,
        description: "Customer credit liability: #{reason}",
        related_entity_type: entity_type || :administration,
        related_entity_id: entity_id || payment.id
      })

    entries = [cash_entry | entries]

    entries
  end

  ## Query Functions

  @doc """
  Gets all ledger entries for a payment.
  """
  def get_entries_by_payment(payment_id) do
    from(e in LedgerEntry,
      where: e.payment_id == ^payment_id,
      preload: [:account]
    )
    |> Repo.all()
  end

  @doc """
  Gets all ledger entries for a specific refund.
  """
  def get_entries_by_refund(refund_id) do
    from(e in LedgerEntry,
      where: e.refund_id == ^refund_id,
      preload: [:account]
    )
    |> Repo.all()
  end

  @doc """
  Gets the related entity (booking or ticket order) for a payment.

  Returns:
  - `{:booking, booking}` if payment is for a booking
  - `{:ticket_order, ticket_order}` if payment is for a ticket order
  - `nil` if no related entity found
  """
  def get_payment_related_entity(payment) do
    # Look for ledger entries with related_entity_type
    entries = get_entries_by_payment(payment.id)

    # Check for booking entry
    booking_entry =
      Enum.find(entries, fn entry ->
        to_string(entry.related_entity_type) == "booking" &&
          entry.related_entity_id
      end)

    if booking_entry do
      case Repo.get(Ysc.Bookings.Booking, booking_entry.related_entity_id) do
        nil -> nil
        booking -> {:booking, booking}
      end
    else
      # Check for ticket order by looking for event entry or checking payment_id on ticket_order
      ticket_order =
        from(to in Ysc.Tickets.TicketOrder,
          where: to.payment_id == ^payment.id,
          preload: [:user, :event, :payment, tickets: :ticket_tier],
          limit: 1
        )
        |> Repo.one()

      if ticket_order do
        {:ticket_order, ticket_order}
      else
        nil
      end
    end
  end

  @doc """
  Gets a single ledger entry by ID with preloaded associations.
  """
  def get_entry(id) do
    from(e in LedgerEntry,
      where: e.id == ^id,
      preload: [:account, :payment]
    )
    |> Repo.one()
  end

  @doc """
  Updates a ledger entry and its corresponding entry to maintain double-entry balance.

  This is a development tool and should be used with caution.
  When updating an entry's amount, the corresponding entry (same payment_id, opposite debit_credit)
  will be updated to maintain balance.
  """
  def update_entry_with_balance(entry_id, attrs) do
    Repo.transaction(fn ->
      entry = get_entry(entry_id)

      if is_nil(entry) do
        Repo.rollback({:error, :not_found})
      end

      # If amount is being changed and entry has a payment, find and update the corresponding entry
      updated_entry =
        if Map.has_key?(attrs, :amount) && entry.payment_id do
          new_amount = Map.get(attrs, :amount, entry.amount)

          # Find the corresponding entry (same payment, opposite debit_credit, same amount)
          # We look for entries with the same amount to find the matching pair
          # Convert to string to handle EctoEnum atoms
          entry_debit_credit_str = to_string(entry.debit_credit)

          opposite_type =
            if entry_debit_credit_str == "debit", do: "credit", else: "debit"

          # Find the corresponding entry by loading matching entries and filtering in Elixir
          # This avoids PostgreSQL type recognition issues with Money composite types in WHERE clauses
          # The fragment approach can fail with "wrong_object_type" errors
          candidate_entries =
            from(e in LedgerEntry,
              where: e.payment_id == ^entry.payment_id,
              where: e.debit_credit == ^opposite_type,
              where: e.id != ^entry.id,
              preload: [:account]
            )
            |> Repo.all()

          # Find the entry with matching amount by comparing Money values
          corresponding_entry =
            Enum.find(candidate_entries, fn candidate ->
              Money.equal?(candidate.amount, entry.amount)
            end)

          # Update the main entry
          case update_entry(entry, attrs) do
            {:ok, updated_entry} ->
              # If we found a corresponding entry, update it too to maintain balance
              if corresponding_entry do
                case update_entry(corresponding_entry, %{amount: new_amount}) do
                  {:ok, _updated_corresponding} ->
                    updated_entry

                  {:error, changeset} ->
                    Repo.rollback(
                      {:error, {:corresponding_entry_update_failed, changeset}}
                    )
                end
              else
                # No corresponding entry found - this might be okay for some entries
                # but we'll still update the main entry
                updated_entry
              end

            {:error, changeset} ->
              Repo.rollback({:error, changeset})
          end
        else
          # No amount change, just update the entry normally
          case update_entry(entry, attrs) do
            {:ok, updated_entry} -> updated_entry
            {:error, changeset} -> Repo.rollback({:error, changeset})
          end
        end

      # Reload with associations
      get_entry(updated_entry.id)
    end)
    |> case do
      {:ok, entry} -> {:ok, entry}
      {:error, {:error, :not_found}} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Updates a ledger entry.
  """
  def update_entry(%LedgerEntry{} = entry, attrs) do
    entry
    |> LedgerEntry.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets all payments for a user.
  """
  def get_payments_by_user(user_id) do
    from(p in Payment,
      where: p.user_id == ^user_id,
      preload: [:user, :payment_method],
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets all payments and free ticket orders for a user with enriched details (tickets, bookings, donations, membership).
  Returns items ordered by inserted_at (created date) descending.
  """
  def list_all_user_payments(user_id) do
    # Get all payments
    payments =
      from(p in Payment,
        where: p.user_id == ^user_id,
        preload: [:user, :payment_method],
        order_by: [desc: p.inserted_at]
      )
      |> Repo.all()
      |> Enum.map(&enrich_payment_with_details/1)

    # Get all free ticket orders (completed orders without payment_id)
    alias Ysc.Tickets.TicketOrder

    free_ticket_orders =
      from(to in TicketOrder,
        where: to.user_id == ^user_id,
        where: to.status == :completed,
        where: is_nil(to.payment_id),
        preload: [:event, tickets: :ticket_tier],
        order_by: [desc: to.inserted_at]
      )
      |> Repo.all()
      |> Enum.map(&enrich_free_ticket_order/1)

    # Combine and sort by inserted_at
    (payments ++ free_ticket_orders)
    |> Enum.sort_by(
      fn item ->
        case item do
          %{payment: payment} when not is_nil(payment) ->
            payment.inserted_at

          %{ticket_order: ticket_order} when not is_nil(ticket_order) ->
            ticket_order.inserted_at

          _ ->
            DateTime.utc_now()
        end
      end,
      {:desc, DateTime}
    )
  end

  @doc """
  Gets all payments for a specific subscription.
  Returns payments ordered by payment_date descending.
  """
  def get_payments_for_subscription(subscription_id) do
    from(p in Payment,
      join: e in LedgerEntry,
      on: e.payment_id == p.id,
      where: e.related_entity_type == "membership",
      where: e.related_entity_id == ^subscription_id,
      preload: [:user, :payment_method],
      order_by: [desc: p.payment_date],
      distinct: true
    )
    |> Repo.all()
  end

  @doc """
  Gets paginated payments and free ticket orders for a user with ticket order and membership information.
  Returns items ordered by inserted_at (created date) descending.

  Optimized to batch load all related data to avoid N+1 queries.
  """
  def list_user_payments_paginated(user_id, page \\ 1, per_page \\ 20) do
    alias Ysc.Tickets.TicketOrder

    # Get total count for payments and free ticket orders separately
    payment_count =
      from(p in Payment, where: p.user_id == ^user_id, select: count())
      |> Repo.one()

    free_ticket_order_count =
      from(to in TicketOrder,
        where: to.user_id == ^user_id,
        where: to.status == :completed,
        where: is_nil(to.payment_id),
        select: count()
      )
      |> Repo.one()

    total_count = payment_count + free_ticket_order_count

    # Calculate offset
    offset = (page - 1) * per_page

    # We need to fetch more items than per_page to account for mixing payments and free orders
    # Fetch enough to cover the page, then sort and slice
    fetch_limit = per_page + offset + 10

    # Get payments with pagination (don't preload user - we already have it)
    payments =
      from(p in Payment,
        where: p.user_id == ^user_id,
        order_by: [desc: p.inserted_at],
        limit: ^fetch_limit
      )
      |> Repo.all()

    # Get free ticket orders
    free_ticket_orders =
      from(to in TicketOrder,
        where: to.user_id == ^user_id,
        where: to.status == :completed,
        where: is_nil(to.payment_id),
        preload: [:event, tickets: :ticket_tier],
        order_by: [desc: to.inserted_at],
        limit: ^fetch_limit
      )
      |> Repo.all()

    # Batch enrich all payments at once (this will batch load payment_methods too)
    enriched_payments = batch_enrich_payments(payments)

    # Enrich free ticket orders (already preloaded, just need to format)
    enriched_free_orders =
      Enum.map(free_ticket_orders, &enrich_free_ticket_order/1)

    # Combine and sort by inserted_at
    all_items =
      (enriched_payments ++ enriched_free_orders)
      |> Enum.sort_by(
        fn item ->
          case item do
            %{payment: payment} when not is_nil(payment) ->
              payment.inserted_at

            %{ticket_order: ticket_order} when not is_nil(ticket_order) ->
              ticket_order.inserted_at

            _ ->
              DateTime.utc_now()
          end
        end,
        {:desc, DateTime}
      )

    # Apply pagination
    paginated_items = Enum.slice(all_items, offset, per_page)

    {paginated_items, total_count}
  end

  # Batch enrich payments to avoid N+1 queries
  defp batch_enrich_payments(payments) when payments == [], do: []

  defp batch_enrich_payments(payments) do
    payment_ids = Enum.map(payments, & &1.id)

    # Batch load payment methods for all payments
    payment_method_ids =
      payments
      |> Enum.map(& &1.payment_method_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    payment_methods_map =
      if payment_method_ids != [] do
        from(pm in Ysc.Payments.PaymentMethod,
          where: pm.id in ^payment_method_ids
        )
        |> Repo.all()
        |> Enum.map(fn pm -> {pm.id, pm} end)
        |> Map.new()
      else
        %{}
      end

    # Attach payment methods to payments
    payments =
      Enum.map(payments, fn payment ->
        payment_method =
          if payment.payment_method_id,
            do: Map.get(payment_methods_map, payment.payment_method_id),
            else: nil

        %{payment | payment_method: payment_method}
      end)

    # Batch load all revenue entries for all payments
    revenue_entries_map =
      from(e in LedgerEntry,
        join: a in LedgerAccount,
        on: e.account_id == a.id,
        where: e.payment_id in ^payment_ids,
        where: a.account_type == ^"revenue",
        where: e.debit_credit == ^:credit,
        preload: [:account]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.payment_id)
      |> Enum.map(fn {payment_id, entries} ->
        {payment_id, List.first(entries)}
      end)
      |> Map.new()

    # Extract entity types and IDs
    event_payment_ids =
      revenue_entries_map
      |> Enum.filter(fn {_id, entry} ->
        entry && entry.related_entity_type == :event
      end)
      |> Enum.map(fn {id, _entry} -> id end)

    booking_payment_ids =
      revenue_entries_map
      |> Enum.filter(fn {_id, entry} ->
        entry && entry.related_entity_type == :booking
      end)
      |> Enum.map(fn {id, _entry} -> id end)

    membership_payment_ids =
      revenue_entries_map
      |> Enum.filter(fn {_id, entry} ->
        entry && entry.related_entity_type == :membership
      end)
      |> Enum.map(fn {id, _entry} -> id end)

    # Batch load ticket orders for event payments
    ticket_orders_map =
      if event_payment_ids != [] do
        from(to in Ysc.Tickets.TicketOrder,
          where: to.payment_id in ^event_payment_ids,
          preload: [:event, tickets: :ticket_tier]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.payment_id)
        |> Enum.map(fn {payment_id, orders} ->
          {payment_id, List.first(orders)}
        end)
        |> Map.new()
      else
        %{}
      end

    # Batch load bookings for booking payments
    bookings_map =
      if booking_payment_ids != [] do
        booking_entity_ids =
          revenue_entries_map
          |> Enum.filter(fn {id, entry} ->
            id in booking_payment_ids && entry && entry.related_entity_id
          end)
          |> Enum.map(fn {_id, entry} -> entry.related_entity_id end)

        if booking_entity_ids != [] do
          from(b in Ysc.Bookings.Booking,
            where: b.id in ^booking_entity_ids,
            preload: [rooms: :room_category]
          )
          |> Repo.all()
          |> Enum.map(fn booking -> {booking.id, booking} end)
          |> Map.new()
        else
          %{}
        end
      else
        %{}
      end

    # Create a reverse map from payment_id to booking_id for lookup
    payment_to_booking_id_map =
      revenue_entries_map
      |> Enum.filter(fn {_id, entry} ->
        entry && entry.related_entity_type == :booking
      end)
      |> Enum.map(fn {payment_id, entry} ->
        {payment_id, entry.related_entity_id}
      end)
      |> Map.new()

    # Batch load subscriptions for membership payments
    subscriptions_map =
      if membership_payment_ids != [] do
        subscription_ids =
          revenue_entries_map
          |> Enum.filter(fn {id, entry} ->
            id in membership_payment_ids && entry && entry.related_entity_id
          end)
          |> Enum.map(fn {_id, entry} -> entry.related_entity_id end)

        if subscription_ids != [] do
          from(s in Ysc.Subscriptions.Subscription,
            where: s.id in ^subscription_ids,
            preload: [:subscription_items]
          )
          |> Repo.all()
          |> Enum.map(fn subscription -> {subscription.id, subscription} end)
          |> Map.new()
        else
          %{}
        end
      else
        %{}
      end

    # Create a reverse map from payment_id to subscription_id for lookup
    payment_to_subscription_id_map =
      revenue_entries_map
      |> Enum.filter(fn {_id, entry} ->
        entry && entry.related_entity_type == :membership
      end)
      |> Enum.map(fn {payment_id, entry} ->
        {payment_id, entry.related_entity_id}
      end)
      |> Map.new()

    # Enrich each payment using the preloaded data
    Enum.map(payments, fn payment ->
      revenue_entry = Map.get(revenue_entries_map, payment.id)

      entity_type =
        if revenue_entry, do: revenue_entry.related_entity_type, else: nil

      ticket_order = Map.get(ticket_orders_map, payment.id)

      booking_id = Map.get(payment_to_booking_id_map, payment.id)
      booking = if booking_id, do: Map.get(bookings_map, booking_id), else: nil

      subscription_id = Map.get(payment_to_subscription_id_map, payment.id)

      subscription =
        if subscription_id,
          do: Map.get(subscriptions_map, subscription_id),
          else: nil

      payment_info = %{
        payment: payment,
        type: determine_payment_type(entity_type),
        ticket_order: ticket_order,
        event: if(ticket_order, do: ticket_order.event, else: nil),
        booking: booking,
        subscription: subscription,
        description:
          build_payment_description(%{
            entity_type: entity_type,
            ticket_order: ticket_order,
            booking: booking,
            subscription: subscription
          })
      }

      payment_info
    end)
  end

  defp enrich_payment_with_details(payment) do
    # Get the revenue ledger entry to determine payment type
    revenue_entry = get_revenue_entry_for_payment(payment.id)

    entity_type =
      if revenue_entry, do: revenue_entry.related_entity_type, else: nil

    entity_id = if revenue_entry, do: revenue_entry.related_entity_id, else: nil

    # Get ticket order if this is an event payment
    ticket_order =
      if entity_type == :event do
        case from(to in Ysc.Tickets.TicketOrder,
               where: to.payment_id == ^payment.id,
               preload: [:event, tickets: :ticket_tier]
             )
             |> Repo.one() do
          nil -> nil
          order -> Repo.preload(order, [:event, tickets: :ticket_tier])
        end
      else
        nil
      end

    # Get booking if this is a booking payment
    booking =
      if entity_type == :booking && entity_id do
        try do
          booking = Repo.get!(Ysc.Bookings.Booking, entity_id)
          Repo.preload(booking, rooms: :room_category)
        rescue
          Ecto.NoResultsError -> nil
        end
      else
        nil
      end

    # Get membership subscription if this is a membership payment
    subscription =
      if entity_type == :membership && entity_id do
        # get_subscription already preloads subscription_items
        subscription = Ysc.Subscriptions.get_subscription(entity_id)
        # Ensure subscription_items are loaded
        if subscription do
          case subscription.subscription_items do
            %Ecto.Association.NotLoaded{} ->
              Repo.preload(subscription, :subscription_items)

            _ ->
              subscription
          end
        else
          nil
        end
      else
        nil
      end

    payment_info = %{
      payment: payment,
      type: determine_payment_type(entity_type),
      ticket_order: ticket_order,
      event: if(ticket_order, do: ticket_order.event, else: nil),
      booking: booking,
      subscription: subscription,
      description:
        build_payment_description(%{
          entity_type: entity_type,
          ticket_order: ticket_order,
          booking: booking,
          subscription: subscription
        })
    }

    payment_info
  end

  defp determine_payment_type(:membership), do: :membership
  defp determine_payment_type(:event), do: :ticket
  defp determine_payment_type(:booking), do: :booking
  defp determine_payment_type(:donation), do: :donation
  defp determine_payment_type(_), do: :unknown

  defp enrich_free_ticket_order(ticket_order) do
    # Preload event if not already loaded
    ticket_order = Repo.preload(ticket_order, [:event, tickets: :ticket_tier])

    description = build_ticket_order_description(ticket_order)

    %{
      payment: nil,
      type: :ticket,
      ticket_order: ticket_order,
      event: ticket_order.event,
      booking: nil,
      subscription: nil,
      description: description
    }
  end

  defp build_ticket_order_description(ticket_order) do
    event_title =
      if ticket_order.event, do: ticket_order.event.title, else: "Event"

    if ticket_order.tickets && ticket_order.tickets != [] do
      tickets = ticket_order.tickets

      ticket_summary =
        tickets
        |> Enum.group_by(fn t -> t.ticket_tier && t.ticket_tier.name end)
        |> Enum.map_join(", ", fn {tier_name, tier_tickets} ->
          count = length(tier_tickets)
          tier_display = tier_name || "General Admission"
          "#{count}x #{tier_display}"
        end)

      "Free Tickets: #{event_title} (#{ticket_summary})"
    else
      "Free Tickets: #{event_title}"
    end
  end

  defp build_payment_description(%{
         entity_type: :membership,
         subscription: subscription
       }) do
    if subscription do
      plan_type = get_membership_plan_type(subscription)
      "Membership Payment - #{String.capitalize(to_string(plan_type))}"
    else
      "Membership Payment"
    end
  end

  defp build_payment_description(%{entity_type: :membership}),
    do: "Membership Payment"

  defp build_payment_description(%{
         entity_type: :event,
         ticket_order: ticket_order
       })
       when not is_nil(ticket_order) do
    event = ticket_order.event
    ticket_count = length(ticket_order.tickets || [])
    ticket_text = if ticket_count == 1, do: "ticket", else: "tickets"

    if event do
      "#{event.title} - #{ticket_count} #{ticket_text}"
    else
      "Event Tickets - #{ticket_count} #{ticket_text}"
    end
  end

  defp build_payment_description(%{entity_type: :booking, booking: booking})
       when not is_nil(booking) do
    property_name =
      case booking.property do
        :tahoe -> "Tahoe"
        :clear_lake -> "Clear Lake"
        _ -> "Cabin"
      end

    "#{property_name} Booking"
  end

  defp build_payment_description(%{entity_type: :booking}), do: "Cabin Booking"
  defp build_payment_description(%{entity_type: :donation}), do: "Donation"
  defp build_payment_description(_), do: "Payment"

  defp get_membership_plan_type(subscription) do
    subscription_items =
      case subscription.subscription_items do
        %Ecto.Association.NotLoaded{} ->
          # Preload subscription items if not loaded
          subscription = Repo.preload(subscription, :subscription_items)
          subscription.subscription_items

        items when is_list(items) ->
          items

        _ ->
          []
      end

    case subscription_items do
      [item | _] ->
        plans = Application.get_env(:ysc, :membership_plans)
        plan = Enum.find(plans, &(&1.stripe_price_id == item.stripe_price_id))
        if plan, do: plan.id, else: :single

      _ ->
        :single
    end
  end

  @doc """
  Gets account balance for a specific account.

  The balance is calculated using explicit debit/credit fields:
  - Debits increase debit-normal accounts (assets, expenses) and decrease credit-normal accounts (revenue, liabilities)
  - Credits decrease debit-normal accounts and increase credit-normal accounts
  """
  def get_account_balance(account_id) do
    account = get_account(account_id)

    entries =
      from(e in LedgerEntry,
        where: e.account_id == ^account_id,
        select: {e.amount, e.debit_credit}
      )
      |> Repo.all()

    # Calculate balance based on debit/credit and account's normal_balance
    balance =
      Enum.reduce(entries, Money.new(0, :USD), fn {entry_amount, debit_credit},
                                                  acc ->
        # Determine if this entry increases or decreases the account balance
        # Convert to strings to handle EctoEnum atoms/strings
        normal_balance_str = to_string(account.normal_balance)
        debit_credit_str = to_string(debit_credit)

        increases_balance? =
          case {normal_balance_str, debit_credit_str} do
            {"debit", "debit"} -> true
            {"debit", "credit"} -> false
            {"credit", "debit"} -> false
            {"credit", "credit"} -> true
            _ -> false
          end

        if increases_balance? do
          case Money.add(acc, entry_amount) do
            {:ok, result} -> result
            {:error, _reason} -> acc
          end
        else
          case Money.sub(acc, entry_amount) do
            {:ok, result} -> result
            {:error, _reason} -> acc
          end
        end
      end)

    balance
  end

  @doc """
  Gets account balance for a specific account within a date range.

  The balance is calculated using explicit debit/credit fields:
  - Debits increase debit-normal accounts (assets, expenses) and decrease credit-normal accounts (revenue, liabilities)
  - Credits decrease debit-normal accounts and increase credit-normal accounts
  """
  def get_account_balance(account_id, start_date, end_date) do
    account = get_account(account_id)

    entries =
      from(e in LedgerEntry,
        join: p in Payment,
        on: e.payment_id == p.id,
        where: e.account_id == ^account_id,
        where: p.payment_date >= ^start_date,
        where: p.payment_date <= ^end_date,
        select: {e.amount, e.debit_credit}
      )
      |> Repo.all()

    # Calculate balance based on debit/credit and account's normal_balance
    balance =
      Enum.reduce(entries, Money.new(0, :USD), fn {entry_amount, debit_credit},
                                                  acc ->
        # Determine if this entry increases or decreases the account balance
        # Convert to strings to handle EctoEnum atoms/strings
        normal_balance_str = to_string(account.normal_balance)
        debit_credit_str = to_string(debit_credit)

        increases_balance? =
          case {normal_balance_str, debit_credit_str} do
            {"debit", "debit"} -> true
            {"debit", "credit"} -> false
            {"credit", "debit"} -> false
            {"credit", "credit"} -> true
            _ -> false
          end

        if increases_balance? do
          case Money.add(acc, entry_amount) do
            {:ok, result} -> result
            {:error, _reason} -> acc
          end
        else
          case Money.sub(acc, entry_amount) do
            {:ok, result} -> result
            {:error, _reason} -> acc
          end
        end
      end)

    balance
  end

  @doc """
  Gets all ledger accounts with their balances.
  """
  def get_accounts_with_balances do
    # First get all accounts
    accounts = Repo.all(LedgerAccount)

    # Then calculate balances for each account
    # Note: get_account_balance already normalizes based on normal_balance
    Enum.map(accounts, fn account ->
      balance = get_account_balance(account.id)
      %{account: account, balance: balance}
    end)
  end

  @doc """
  Gets all ledger accounts with their balances within a date range.
  """
  def get_accounts_with_balances(start_date, end_date) do
    # First get all accounts
    accounts = Repo.all(LedgerAccount)

    # Batch fetch all ledger entries for all accounts in one query
    account_ids = Enum.map(accounts, & &1.id)

    entries_by_account =
      from(e in LedgerEntry,
        join: p in Payment,
        on: e.payment_id == p.id,
        where: e.account_id in ^account_ids,
        where: p.payment_date >= ^start_date,
        where: p.payment_date <= ^end_date,
        select: {e.account_id, e.amount, e.debit_credit}
      )
      |> Repo.all()
      |> Enum.group_by(fn {account_id, _amount, _debit_credit} ->
        account_id
      end)

    # Calculate balance for each account using the pre-fetched entries
    Enum.map(accounts, fn account ->
      entries = Map.get(entries_by_account, account.id, [])

      balance =
        Enum.reduce(entries, Money.new(0, :USD), fn {_account_id, entry_amount,
                                                     debit_credit},
                                                    acc ->
          normal_balance_str = to_string(account.normal_balance)
          debit_credit_str = to_string(debit_credit)

          increases_balance? =
            case {normal_balance_str, debit_credit_str} do
              {"debit", "debit"} -> true
              {"debit", "credit"} -> false
              {"credit", "debit"} -> false
              {"credit", "credit"} -> true
              _ -> false
            end

          if increases_balance? do
            case Money.add(acc, entry_amount) do
              {:ok, result} -> result
              {:error, _reason} -> acc
            end
          else
            case Money.sub(acc, entry_amount) do
              {:ok, result} -> result
              {:error, _reason} -> acc
            end
          end
        end)

      %{account: account, balance: balance}
    end)
  end

  @doc """
  Updates a payment.
  """
  def update_payment(%Payment{} = payment, attrs) do
    payment
    |> Payment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a payment by ID with preloaded associations.
  """
  def get_payment(id) do
    case Repo.get(Payment, id) do
      nil -> nil
      payment -> Repo.preload(payment, [:user, :payment_method])
    end
  end

  @doc """
  Gets a payment by ID with preloaded associations.
  """
  def get_payment_with_associations(id) do
    Repo.get(Payment, id)
    |> case do
      nil -> nil
      payment -> Repo.preload(payment, [:user, :payment_method])
    end
  end

  @doc """
  Gets a payment by external payment ID with preloaded associations.
  """
  def get_payment_by_external_id(external_payment_id) do
    case Repo.get_by(Payment, external_payment_id: external_payment_id) do
      nil -> nil
      payment -> Repo.preload(payment, [:user, :payment_method])
    end
  end

  @doc """
  Gets a refund by external refund ID with preloaded associations.
  """
  def get_refund_by_external_id(external_refund_id) do
    case Repo.get_by(Refund, external_refund_id: external_refund_id) do
      nil -> nil
      refund -> Repo.preload(refund, [:user])
    end
  end

  @doc """
  Gets a refund by ID with preloaded associations.
  """
  def get_refund(id) do
    case Repo.get(Refund, id) do
      nil -> nil
      refund -> Repo.preload(refund, [:user])
    end
  end

  @doc """
  Updates a refund record.
  """
  def update_refund(%Refund{} = refund, attrs) do
    refund
    |> Refund.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets recent payments within a date range.
  """
  def get_recent_payments(start_date, end_date, limit \\ 50) do
    from(p in Payment,
      preload: [:user, :payment_method],
      where: p.payment_date >= ^start_date,
      where: p.payment_date <= ^end_date,
      order_by: [desc: p.payment_date],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&add_payment_type_info/1)
  end

  @doc """
  Gets recent payments with payment type information.
  """
  def get_recent_payments_with_types(start_date, end_date, limit \\ 50) do
    from(p in Payment,
      preload: [:user, :payment_method],
      where: p.payment_date >= ^start_date,
      where: p.payment_date <= ^end_date,
      order_by: [desc: p.payment_date],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&add_payment_type_info/1)
  end

  @doc """
  Gets ledger entries within a date range.
  """
  def get_ledger_entries(start_date, end_date, limit \\ 500) do
    from(e in LedgerEntry,
      preload: [:account, :payment],
      where: e.inserted_at >= ^start_date,
      where: e.inserted_at <= ^end_date,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Adds payment type information to a payment struct.
  """
  def add_payment_type_info(payment) do
    # Check if this payment is linked to a payout
    payout = get_payout_by_payment_id(payment.id)

    if payout do
      # This is a payout payment
      payment_type_info = %{
        type: "Payout",
        details: "Stripe payout: #{payout.stripe_payout_id}"
      }

      Map.put(payment, :payment_type_info, payment_type_info)
    else
      # Get the revenue entry for this payment to determine the type
      revenue_entry = get_revenue_entry_for_payment(payment.id)

      payment_type_info =
        case revenue_entry do
          nil ->
            %{type: "Unknown", details: "No revenue entry found"}

          entry ->
            case entry.related_entity_type do
              :membership ->
                %{
                  type: "Membership",
                  details: get_membership_details(entry.related_entity_id)
                }

              :event ->
                %{
                  type: "Event",
                  details: get_event_details(entry.related_entity_id)
                }

              :booking ->
                %{
                  type: "Booking",
                  details:
                    get_booking_details(
                      entry.related_entity_id,
                      entry.account.name
                    )
                }

              :donation ->
                %{type: "Donation", details: "General donation"}

              :administration ->
                %{type: "Administration", details: "System transaction"}

              _ ->
                %{type: "Unknown", details: "Unknown entity type"}
            end
        end

      Map.put(payment, :payment_type_info, payment_type_info)
    end
  end

  @doc """
  Adds payment type information to a list of payments in batch (optimized).
  This function preloads all necessary associations in batch to avoid N+1 queries.
  """
  def add_payment_type_info_batch(payments) when is_list(payments) do
    if Enum.empty?(payments) do
      []
    else
      payment_ids = Enum.map(payments, & &1.id)

      # Batch fetch all payouts
      payouts =
        from(p in Payout,
          where: p.payment_id in ^payment_ids
        )
        |> Repo.all()
        |> Map.new(&{&1.payment_id, &1})

      # Batch fetch all revenue entries with accounts preloaded
      revenue_entries =
        from(e in LedgerEntry,
          join: a in LedgerAccount,
          on: e.account_id == a.id,
          where: e.payment_id in ^payment_ids,
          where: a.account_type == ^"revenue",
          where: e.debit_credit == ^"credit",
          preload: [:account]
        )
        |> Repo.all()
        |> Map.new(&{&1.payment_id, &1})

      # Extract unique entity IDs for batch fetching
      event_ids =
        revenue_entries
        |> Enum.filter(fn {_payment_id, entry} ->
          entry.related_entity_type == :event
        end)
        |> Enum.map(fn {_payment_id, entry} -> entry.related_entity_id end)
        |> Enum.uniq()
        |> Enum.filter(& &1)

      subscription_ids =
        revenue_entries
        |> Enum.filter(fn {_payment_id, entry} ->
          entry.related_entity_type == :membership
        end)
        |> Enum.map(fn {_payment_id, entry} -> entry.related_entity_id end)
        |> Enum.uniq()
        |> Enum.filter(& &1)

      # Batch fetch events
      events =
        if Enum.empty?(event_ids) do
          %{}
        else
          from(e in Ysc.Events.Event,
            where: e.id in ^event_ids
          )
          |> Repo.all()
          |> Map.new(&{&1.id, &1})
        end

      # Batch fetch subscriptions
      subscriptions =
        if Enum.empty?(subscription_ids) do
          %{}
        else
          from(s in Ysc.Subscriptions.Subscription,
            where: s.id in ^subscription_ids
          )
          |> Repo.all()
          |> Map.new(&{&1.id, &1})
        end

      # Batch fetch subscription items for all subscriptions
      subscription_items_map =
        if Enum.empty?(subscription_ids) do
          %{}
        else
          from(si in Ysc.Subscriptions.SubscriptionItem,
            where: si.subscription_id in ^subscription_ids
          )
          |> Repo.all()
          |> Enum.group_by(& &1.subscription_id)
        end

      # Attach subscription items to subscriptions using struct update
      subscriptions =
        Enum.map(subscriptions, fn {id, subscription} ->
          items = Map.get(subscription_items_map, id, [])
          {id, %{subscription | subscription_items: items}}
        end)
        |> Map.new()

      # Process each payment with preloaded data
      Enum.map(payments, fn payment ->
        payout = Map.get(payouts, payment.id)

        if payout do
          payment_type_info = %{
            type: "Payout",
            details: "Stripe payout: #{payout.stripe_payout_id}"
          }

          Map.put(payment, :payment_type_info, payment_type_info)
        else
          revenue_entry = Map.get(revenue_entries, payment.id)

          payment_type_info =
            case revenue_entry do
              nil ->
                %{type: "Unknown", details: "No revenue entry found"}

              entry ->
                case entry.related_entity_type do
                  :membership ->
                    subscription =
                      Map.get(subscriptions, entry.related_entity_id)

                    details =
                      get_membership_details_from_subscription(subscription)

                    %{type: "Membership", details: details}

                  :event ->
                    event = Map.get(events, entry.related_entity_id)
                    details = if event, do: event.title, else: "Unknown Event"
                    %{type: "Event", details: details}

                  :booking ->
                    details =
                      get_booking_details(
                        entry.related_entity_id,
                        entry.account.name
                      )

                    %{type: "Booking", details: details}

                  :donation ->
                    %{type: "Donation", details: "General donation"}

                  :administration ->
                    %{type: "Administration", details: "System transaction"}

                  _ ->
                    %{type: "Unknown", details: "Unknown entity type"}
                end
            end

          Map.put(payment, :payment_type_info, payment_type_info)
        end
      end)
    end
  end

  # Helper to get membership details from a preloaded subscription
  defp get_membership_details_from_subscription(nil), do: "Unknown membership"

  defp get_membership_details_from_subscription(subscription) do
    subscription_items =
      case subscription.subscription_items do
        %Ecto.Association.NotLoaded{} ->
          # Preload subscription items if not loaded
          subscription = Repo.preload(subscription, :subscription_items)
          subscription.subscription_items

        items when is_list(items) ->
          items

        _ ->
          []
      end

    case subscription_items do
      [] ->
        "Membership"

      [item | _] ->
        get_membership_plan_by_price_id(item.stripe_price_id)
    end
  end

  # Helper function to get payout by payment ID
  defp get_payout_by_payment_id(payment_id) do
    from(p in Payout,
      where: p.payment_id == ^payment_id,
      limit: 1
    )
    |> Repo.one()
  end

  # Helper function to get the revenue entry for a payment
  defp get_revenue_entry_for_payment(payment_id) do
    from(e in LedgerEntry,
      join: a in LedgerAccount,
      on: e.account_id == a.id,
      where: e.payment_id == ^payment_id,
      where: a.account_type == ^"revenue",
      preload: [:account],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      entry ->
        # Filter for credit entries (revenue entries are credits)
        # Convert to string to handle EctoEnum atoms
        if to_string(entry.debit_credit) == "credit", do: entry, else: nil
    end
  end

  # Helper function to get membership details
  defp get_membership_details(subscription_id)
       when is_binary(subscription_id) do
    case Ysc.Subscriptions.get_subscription(subscription_id) do
      nil ->
        "Unknown membership"

      subscription ->
        # Get subscription items to find the price ID
        # Preload subscription items and get the first one
        subscription_with_items =
          Ysc.Repo.preload(subscription, :subscription_items)

        case subscription_with_items.subscription_items do
          [] ->
            "Membership"

          [item | _] ->
            # Map price ID to membership plan
            get_membership_plan_by_price_id(item.stripe_price_id)
        end
    end
  end

  defp get_membership_details(_), do: "Membership"

  # Helper function to get membership plan by price ID
  defp get_membership_plan_by_price_id(price_id) when is_binary(price_id) do
    membership_plans = Application.get_env(:ysc, :membership_plans, [])

    case Enum.find(membership_plans, fn plan ->
           plan.stripe_price_id == price_id
         end) do
      nil ->
        "Membership"

      plan ->
        "#{plan.name} Membership"
    end
  end

  defp get_membership_plan_by_price_id(_), do: "Membership"

  # Helper function to get event details
  defp get_event_details(event_id) when is_binary(event_id) do
    try do
      event = Ysc.Events.get_event!(event_id)
      event.title
    rescue
      Ecto.NoResultsError -> "Unknown Event"
    end
  end

  defp get_event_details(_), do: "Event"

  # Helper function to get booking details
  defp get_booking_details(booking_id, account_name)
       when is_binary(booking_id) do
    property =
      case account_name do
        "tahoe_booking_revenue" -> "Tahoe"
        "clear_lake_booking_revenue" -> "Clear Lake"
        _ -> "Unknown Property"
      end

    # Try to get booking details if we have a booking system
    # For now, just return the property
    "#{property} Booking"
  end

  defp get_booking_details(_, account_name) do
    property =
      case account_name do
        "tahoe_booking_revenue" -> "Tahoe"
        "clear_lake_booking_revenue" -> "Clear Lake"
        _ -> "Unknown Property"
      end

    "#{property} Booking"
  end

  ## Ledger Integrity

  @doc """
  Verifies that the ledger is balanced (debits = credits).

  In double-entry accounting, the sum of all debits should equal the sum of all credits.
  This function checks that invariant and returns the balance status.

  Returns:
  - `{:ok, :balanced}` if the ledger is balanced
  - `{:error, {:imbalanced, difference}}` if there's an imbalance

  ## Examples

      iex> verify_ledger_balance()
      {:ok, :balanced}

      iex> verify_ledger_balance()
      {:error, {:imbalanced, %Money{amount: 100, currency: :USD}}}

  """
  def verify_ledger_balance do
    require Logger

    # Get total debits (all amounts with debit_credit = 'debit')
    total_debits_query =
      from(e in LedgerEntry,
        where: e.debit_credit == "debit",
        select: sum(fragment("(?.amount).amount", e))
      )

    total_debits_cents = Repo.one(total_debits_query) || Decimal.new(0)

    # Get total credits (all amounts with debit_credit = 'credit')
    total_credits_query =
      from(e in LedgerEntry,
        where: e.debit_credit == "credit",
        select: sum(fragment("(?.amount).amount", e))
      )

    total_credits_cents = Repo.one(total_credits_query) || Decimal.new(0)

    # Convert to Money for proper subtraction
    total_debits = Money.new(total_debits_cents, :USD)
    total_credits = Money.new(total_credits_cents, :USD)

    # In double-entry accounting, total debits should equal total credits
    # Since both are now positive, we subtract credits from debits
    {:ok, balance} = Money.sub(total_debits, total_credits)

    if Money.equal?(balance, Money.new(0, :USD)) do
      Logger.info("Ledger balance verified",
        total_debits: Money.to_string!(total_debits),
        total_credits: Money.to_string!(total_credits),
        balance: "balanced"
      )

      {:ok, :balanced}
    else
      # Critical condition: report to Sentry instead of emitting error-level logs.
      Logger.warning("LEDGER IMBALANCE DETECTED!",
        total_debits: Money.to_string!(total_debits),
        total_credits: Money.to_string!(total_credits),
        difference: Money.to_string!(balance)
      )

      Sentry.capture_message("Ledger imbalance detected",
        level: :error,
        extra: %{
          total_debits: Money.to_string!(total_debits),
          total_credits: Money.to_string!(total_credits),
          difference: Money.to_string!(balance)
        },
        tags: %{
          ledger: "balance_check"
        }
      )

      {:error, {:imbalanced, balance}}
    end
  end

  @doc """
  Verifies ledger balance and raises if imbalanced.
  Useful for periodic checks and alerts.
  """
  def verify_ledger_balance! do
    case verify_ledger_balance() do
      {:ok, :balanced} ->
        :ok

      {:error, {:imbalanced, difference}} ->
        raise "Ledger imbalance detected! Difference: #{Money.to_string!(difference)}"
    end
  end

  @doc """
  Identifies which accounts are imbalanced by checking the balance of each account.

  In a balanced ledger, each account's total should follow double-entry rules.
  This function helps identify which specific accounts have issues.

  Returns a list of tuples: `{account, balance}` for accounts that have unexpected balances.

  ## Examples

      iex> get_account_balances()
      [
        {%LedgerAccount{name: "stripe_account"}, %Money{amount: 1000, currency: :USD}},
        {%LedgerAccount{name: "cash"}, %Money{amount: 500, currency: :USD}}
      ]

  """
  def get_account_balances do
    # Get all accounts
    accounts = Repo.all(LedgerAccount)

    # Calculate balance for each account
    Enum.map(accounts, fn account ->
      balance = calculate_account_balance(account.id)
      {account, balance}
    end)
    |> Enum.filter(fn {_account, balance} ->
      # Only include accounts with non-zero balances
      not Money.equal?(balance, Money.new(0, :USD))
    end)
    |> Enum.sort_by(
      fn {_account, balance} -> Money.to_decimal(balance) end,
      :desc
    )
  end

  @doc """
  Calculates the balance for a specific account.

  Returns the balance calculated using explicit debit/credit fields.
  """
  def calculate_account_balance(account_id) do
    get_account_balance(account_id)
  end

  # Note: normalize_balance_for_account is no longer needed since we use explicit debit/credit fields
  # All amounts are positive and balances are calculated directly based on debit/credit

  @doc """
  Gets detailed imbalance information including which accounts are off.

  Returns:
  - `{:ok, :balanced}` if balanced
  - `{:error, {:imbalanced, difference, imbalanced_accounts}}` if imbalanced

  The `imbalanced_accounts` will include accounts that have unusual balances
  and could be the source of the imbalance.

  ## Examples

      iex> get_ledger_imbalance_details()
      {:ok, :balanced}

      iex> get_ledger_imbalance_details()
      {:error, {:imbalanced, difference, [
        {%LedgerAccount{name: "stripe_account", account_type: "asset"}, %Money{...}},
        {%LedgerAccount{name: "membership_revenue", account_type: "revenue"}, %Money{...}}
      ]}}

  """
  def get_ledger_imbalance_details do
    require Logger

    case verify_ledger_balance() do
      {:ok, :balanced} = result ->
        result

      {:error, {:imbalanced, difference}} ->
        # Get all account balances to identify problematic accounts
        account_balances = get_account_balances()

        # Group by account type for analysis
        balances_by_type =
          Enum.group_by(account_balances, fn {account, _balance} ->
            account.account_type
          end)

        Logger.warning("Ledger imbalance details",
          total_difference: Money.to_string!(difference),
          account_count: length(account_balances),
          asset_accounts: length(Map.get(balances_by_type, "asset", [])),
          liability_accounts:
            length(Map.get(balances_by_type, "liability", [])),
          revenue_accounts: length(Map.get(balances_by_type, "revenue", [])),
          expense_accounts: length(Map.get(balances_by_type, "expense", []))
        )

        # Log each account with significant balance
        Enum.each(account_balances, fn {account, balance} ->
          Logger.warning("Account balance",
            account_name: account.name,
            account_type: account.account_type,
            balance: Money.to_string!(balance)
          )
        end)

        {:error, {:imbalanced, difference, account_balances}}
    end
  end
end
