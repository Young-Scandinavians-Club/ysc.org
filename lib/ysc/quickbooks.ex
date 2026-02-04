defmodule Ysc.Quickbooks do
  @moduledoc """
  QuickBooks Online integration context.

  This module provides high-level functions for common QuickBooks operations,
  wrapping the lower-level `Ysc.Quickbooks.Client` module.

  ## Examples

      # Create a sales receipt for a purchase
      alias Ysc.Quickbooks

      Quickbooks.create_purchase_sales_receipt(%{
        customer_id: "123",
        item_id: "456",
        quantity: 1,
        unit_price: 100.00,
        payment_method_id: "789",
        txn_date: ~D[2024-01-15]
      })

      # Create a sales receipt for a refund
      Quickbooks.create_refund_sales_receipt(%{
        customer_id: "123",
        item_id: "456",
        quantity: 1,
        unit_price: 50.00,
        payment_method_id: "789",
        txn_date: ~D[2024-01-15]
      })

      # Create a deposit for a Stripe payout
      Quickbooks.create_stripe_payout_deposit(%{
        bank_account_id: "789",
        stripe_account_id: "101112",
        amount: 500.00,
        txn_date: ~D[2024-01-15],
        memo: "Stripe payout for period ending 2024-01-15"
      })
  """

  require Logger
  alias Ysc.Accounts.User

  defp client_module do
    if Ysc.Env.test?() do
      Ysc.Quickbooks.ClientMock
    else
      Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)
    end
  end

  @doc """
  Creates a sales receipt for a purchase.

  ## Parameters

    - `params` - Map containing:
      - `customer_id` (required) - QuickBooks customer ID
      - `item_id` (required) - QuickBooks item ID
      - `quantity` (required) - Quantity purchased
      - `unit_price` (required) - Unit price
      - `payment_method_id` (optional) - Payment method ID
      - `deposit_to_account_id` (optional) - Account to deposit to
      - `txn_date` (optional) - Transaction date (Date struct or ISO 8601 string)
      - `description` (optional) - Line item description
      - `memo` (optional) - Public memo
      - `private_note` (optional) - Private note
      - `class_ref` (optional) - Class reference for categorization
      - `tax_code_ref` (optional) - Tax code reference

  """
  @spec create_purchase_sales_receipt(map()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def create_purchase_sales_receipt(params) do
    # Validate required parameters early to provide better error messages
    cond do
      is_nil(params[:customer_id]) or params[:customer_id] == "" ->
        Logger.error(
          "[QB] create_purchase_sales_receipt: CRITICAL - customer_id is nil or empty! Cannot create sales receipt without a customer.",
          params: inspect(params, limit: :infinity)
        )

        {:error, :missing_customer_id}

      is_nil(params[:item_id]) or params[:item_id] == "" ->
        Logger.error(
          "[QB] create_purchase_sales_receipt: CRITICAL - item_id is nil or empty! Cannot create sales receipt without an item.",
          params: inspect(params, limit: :infinity)
        )

        {:error, :missing_item_id}

      true ->
        do_create_purchase_sales_receipt(params)
    end
  end

  defp do_create_purchase_sales_receipt(params) do
    total_amt = Decimal.mult(Decimal.new(params.quantity), params.unit_price)

    # Convert quantity to Decimal if it's not already
    quantity =
      case params.quantity do
        %Decimal{} = qty -> qty
        qty when is_integer(qty) -> Decimal.new(qty)
        qty when is_float(qty) -> Decimal.from_float(qty)
        _ -> Decimal.new(1)
      end

    sales_item_detail = %{
      item_ref: %{value: params.item_id},
      quantity: quantity,
      unit_price: params.unit_price
    }

    # CRITICAL: ALL QuickBooks exports MUST include a class reference
    # If not provided, default to Administration
    sales_item_detail =
      if params[:class_ref] do
        # class_ref should already be in the format %{value: "id", name: "name"}
        # Use it directly, don't wrap it in another value
        Map.put(sales_item_detail, :class_ref, params.class_ref)
      else
        # Default to Administration if not provided
        # Query for Administration class ID
        default_class_ref =
          case client_module().query_class_by_name("Administration") do
            {:ok, class_id} ->
              %{value: class_id, name: "Administration"}

            _ ->
              # Last resort fallback - this may fail, but we must provide a class
              Logger.error(
                "[QB] create_purchase_sales_receipt: CRITICAL - Administration class not found! Using hardcoded fallback (this may fail)"
              )

              %{value: "Administration", name: "Administration"}
          end

        Map.put(sales_item_detail, :class_ref, default_class_ref)
      end

    sales_item_detail =
      if params[:tax_code_ref],
        do:
          Map.put(sales_item_detail, :tax_code_ref, %{
            value: params.tax_code_ref
          }),
        else: sales_item_detail

    line_item = %{
      amount: total_amt,
      detail_type: "SalesItemLineDetail",
      sales_item_line_detail: sales_item_detail
    }

    line_item =
      if params[:description],
        do: Map.put(line_item, :description, params.description),
        else: line_item

    sales_receipt_params = %{
      customer_ref: %{value: params.customer_id},
      line: [line_item],
      total_amt: total_amt
    }

    sales_receipt_params =
      if params[:payment_method_id],
        do:
          Map.put(sales_receipt_params, :payment_method_ref, %{
            value: params.payment_method_id
          }),
        else: sales_receipt_params

    sales_receipt_params =
      if params[:deposit_to_account_id] do
        # Include name if provided, otherwise just value
        deposit_ref =
          if params[:deposit_to_account_name] do
            %{
              value: params.deposit_to_account_id,
              name: params.deposit_to_account_name
            }
          else
            %{value: params.deposit_to_account_id}
          end

        Map.put(sales_receipt_params, :deposit_to_account_ref, deposit_ref)
      else
        sales_receipt_params
      end

    sales_receipt_params =
      if params[:txn_date],
        do:
          Map.put(sales_receipt_params, :txn_date, format_date(params.txn_date)),
        else: sales_receipt_params

    sales_receipt_params =
      if params[:memo],
        do: Map.put(sales_receipt_params, :memo, params.memo),
        else: sales_receipt_params

    sales_receipt_params =
      if params[:private_note],
        do: Map.put(sales_receipt_params, :private_note, params.private_note),
        else: sales_receipt_params

    client_module().create_sales_receipt(sales_receipt_params)
  end

  @doc """
  Creates a sales receipt for a refund.

  This is similar to a purchase but with negative amounts.

  ## Parameters

    - `params` - Map containing:
      - `customer_id` (required) - QuickBooks customer ID
      - `item_id` (required) - QuickBooks item ID
      - `quantity` (required) - Quantity refunded
      - `unit_price` (required) - Unit price (positive value, will be negated)
      - `payment_method_id` (optional) - Payment method ID
      - `deposit_to_account_id` (optional) - Account to deposit to
      - `txn_date` (optional) - Transaction date (Date struct or ISO 8601 string)
      - `description` (optional) - Line item description
      - `memo` (optional) - Public memo
      - `private_note` (optional) - Private note
      - `class_ref` (optional) - Class reference for categorization
      - `tax_code_ref` (optional) - Tax code reference

  """
  @spec create_refund_sales_receipt(map()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def create_refund_sales_receipt(params) do
    # Refund Receipts use positive amounts - the transaction type determines direction
    unit_price = Decimal.abs(params.unit_price)
    total_amt = Decimal.mult(Decimal.new(params.quantity), unit_price)

    sales_item_detail = %{
      item_ref: %{value: params.item_id},
      quantity: params.quantity,
      unit_price: unit_price
    }

    sales_item_detail =
      if params[:class_ref] do
        # class_ref should already be in the format %{value: "id", name: "name"}
        # Use it directly, don't wrap it in another value
        Map.put(sales_item_detail, :class_ref, params.class_ref)
      else
        sales_item_detail
      end

    sales_item_detail =
      if params[:tax_code_ref],
        do:
          Map.put(sales_item_detail, :tax_code_ref, %{
            value: params.tax_code_ref
          }),
        else: sales_item_detail

    line_item = %{
      amount: total_amt,
      detail_type: "SalesItemLineDetail",
      sales_item_line_detail: sales_item_detail,
      description: params[:description] || "Refund"
    }

    sales_receipt_params = %{
      customer_ref: %{value: params.customer_id},
      line: [line_item],
      total_amt: total_amt
    }

    sales_receipt_params =
      if params[:payment_method_id],
        do:
          Map.put(sales_receipt_params, :payment_method_ref, %{
            value: params.payment_method_id
          }),
        else: sales_receipt_params

    sales_receipt_params =
      if params[:deposit_to_account_id],
        do:
          Map.put(sales_receipt_params, :deposit_to_account_ref, %{
            value: params.deposit_to_account_id
          }),
        else: sales_receipt_params

    sales_receipt_params =
      if params[:txn_date],
        do:
          Map.put(sales_receipt_params, :txn_date, format_date(params.txn_date)),
        else: sales_receipt_params

    sales_receipt_params =
      if params[:memo],
        do: Map.put(sales_receipt_params, :memo, params.memo),
        else: sales_receipt_params

    sales_receipt_params =
      if params[:private_note],
        do: Map.put(sales_receipt_params, :private_note, params.private_note),
        else: sales_receipt_params

    client_module().create_sales_receipt(sales_receipt_params)
  end

  @doc """
  Creates a refund receipt in QuickBooks.

  RefundReceipt is the proper transaction type for refunds, as it properly
  reverses revenue and records money going back to the customer.

  ## Parameters

    - `params` - Map containing:
      - `customer_id` (required) - QuickBooks customer ID
      - `item_id` (required) - QuickBooks item ID
      - `quantity` (required) - Quantity refunded
      - `unit_price` (required) - Unit price (positive value)
      - `refund_from_account_id` (required) - Account money is leaving from (e.g., "Undeposited Funds")
      - `payment_method_id` (optional) - Payment method ID
      - `txn_date` (optional) - Transaction date (Date struct or ISO 8601 string)
      - `description` (optional) - Line item description
      - `memo` (optional) - Public memo
      - `private_note` (optional) - Private note
      - `class_ref` (optional) - Class reference for categorization
      - `tax_code_ref` (optional) - Tax code reference

  """
  @spec create_refund_receipt(map()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def create_refund_receipt(params) do
    # RefundReceipts use positive amounts - the transaction type determines direction
    unit_price = Decimal.abs(params.unit_price)
    total_amt = Decimal.mult(Decimal.new(params.quantity), unit_price)

    # Convert quantity to Decimal if it's not already
    quantity =
      case params.quantity do
        %Decimal{} = qty -> qty
        qty when is_integer(qty) -> Decimal.new(qty)
        qty when is_float(qty) -> Decimal.from_float(qty)
        _ -> Decimal.new(1)
      end

    sales_item_detail = %{
      item_ref: %{value: params.item_id},
      quantity: quantity,
      unit_price: unit_price
    }

    sales_item_detail =
      if params[:class_ref] do
        # class_ref should already be in the format %{value: "id", name: "name"}
        # Use it directly, don't wrap it in another value
        Map.put(sales_item_detail, :class_ref, params.class_ref)
      else
        sales_item_detail
      end

    sales_item_detail =
      if params[:tax_code_ref],
        do:
          Map.put(sales_item_detail, :tax_code_ref, %{
            value: params.tax_code_ref
          }),
        else: sales_item_detail

    line_item = %{
      amount: total_amt,
      detail_type: "SalesItemLineDetail",
      sales_item_line_detail: sales_item_detail
    }

    line_item =
      if params[:description],
        do: Map.put(line_item, :description, params.description),
        else: line_item

    # Build refund_from_account_ref with name if provided
    refund_from_account_ref =
      if params[:refund_from_account_name] do
        %{
          value: params.refund_from_account_id,
          name: params.refund_from_account_name
        }
      else
        %{value: params.refund_from_account_id}
      end

    refund_receipt_params = %{
      customer_ref: %{value: params.customer_id},
      line: [line_item],
      total_amt: total_amt,
      refund_from_account_ref: refund_from_account_ref
    }

    refund_receipt_params =
      if params[:payment_method_id],
        do:
          Map.put(refund_receipt_params, :payment_method_ref, %{
            value: params.payment_method_id
          }),
        else: refund_receipt_params

    refund_receipt_params =
      if params[:txn_date],
        do:
          Map.put(
            refund_receipt_params,
            :txn_date,
            format_date(params.txn_date)
          ),
        else: refund_receipt_params

    refund_receipt_params =
      if params[:memo],
        do: Map.put(refund_receipt_params, :memo, params.memo),
        else: refund_receipt_params

    refund_receipt_params =
      if params[:private_note],
        do: Map.put(refund_receipt_params, :private_note, params.private_note),
        else: refund_receipt_params

    client_module().create_refund_receipt(refund_receipt_params)
  end

  @doc """
  Creates a deposit for a Stripe payout.

  ## Parameters

    - `params` - Map containing:
      - `bank_account_id` (required) - QuickBooks bank account ID to deposit to
      - `stripe_account_id` (required) - QuickBooks account ID representing Stripe
      - `amount` (required) - Deposit amount
      - `txn_date` (optional) - Transaction date (Date struct or ISO 8601 string)
      - `memo` (optional) - Public memo
      - `private_note` (optional) - Private note
      - `class_ref` (optional) - Class reference for categorization
      - `payment_method_ref` (optional) - Payment method reference

  """
  @spec create_stripe_payout_deposit(map()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def create_stripe_payout_deposit(params) do
    deposit_line_detail = %{
      account_ref: %{value: params.stripe_account_id}
    }

    deposit_line_detail =
      if params[:class_ref],
        do:
          Map.put(deposit_line_detail, :class_ref, %{value: params.class_ref}),
        else: deposit_line_detail

    deposit_line_detail =
      if params[:payment_method_ref],
        do:
          Map.put(deposit_line_detail, :payment_method_ref, %{
            value: params.payment_method_ref
          }),
        else: deposit_line_detail

    line_item = %{
      amount: params.amount,
      detail_type: "DepositLineDetail",
      deposit_line_detail: deposit_line_detail,
      description: params[:description] || "Stripe payout"
    }

    deposit_params = %{
      deposit_to_account_ref: %{value: params.bank_account_id},
      line: [line_item],
      total_amt: params.amount
    }

    deposit_params =
      if params[:txn_date],
        do: Map.put(deposit_params, :txn_date, format_date(params.txn_date)),
        else: deposit_params

    deposit_params =
      if params[:memo],
        do: Map.put(deposit_params, :memo, params.memo),
        else: deposit_params

    deposit_params =
      if params[:private_note],
        do: Map.put(deposit_params, :private_note, params.private_note),
        else: deposit_params

    client_module().create_deposit(deposit_params)
  end

  @doc """
  Gets or creates a QuickBooks customer for a user.

  If the user already has a `quickbooks_customer_id`, returns it.
  Otherwise, creates a new customer in QuickBooks and updates the user.

  ## Parameters

    - `user` - The user to get or create a QuickBooks customer for

  ## Examples

      alias Ysc.Quickbooks
      alias Ysc.Accounts

      user = Accounts.get_user!(123)
      case Quickbooks.get_or_create_customer(user) do
        {:ok, customer_id} ->
          # Use customer_id for creating sales receipts
        {:error, reason} ->
          # Handle error
      end

  """
  @spec get_or_create_customer(User.t()) ::
          {:ok, String.t()} | {:error, atom() | String.t()}
  def get_or_create_customer(%User{} = user) do
    alias Ysc.Repo

    # If user already has a QuickBooks customer ID, return it
    if user.quickbooks_customer_id do
      {:ok, user.quickbooks_customer_id}
    else
      # Create customer in QuickBooks
      display_name = build_display_name(user)

      if is_nil(display_name) do
        {:error, :missing_name}
      else
        customer_params = %{
          display_name: display_name,
          given_name: user.first_name,
          family_name: user.last_name,
          email: user.email,
          phone: user.phone_number
        }

        case client_module().create_customer(customer_params) do
          {:ok, customer} ->
            customer_id = Map.get(customer, "Id")

            if customer_id do
              # Update user with QuickBooks customer ID
              changeset =
                User.update_user_changeset(user, %{
                  quickbooks_customer_id: customer_id
                })

              case Repo.update(changeset) do
                {:ok, _updated_user} ->
                  {:ok, customer_id}

                {:error, changeset} ->
                  require Logger

                  Logger.error(
                    "Failed to update user with quickbooks_customer_id",
                    user_id: user.id,
                    quickbooks_customer_id: customer_id,
                    changeset_errors: inspect(changeset.errors)
                  )

                  # Still return success for the customer creation
                  # The quickbooks_customer_id can be set manually later
                  {:ok, customer_id}
              end
            else
              {:error, :invalid_customer_response}
            end

          {:error, error} when is_binary(error) ->
            # Check if it's a duplicate name error
            if String.contains?(error, "Duplicate Name Exists Error") or
                 String.contains?(error, "6240") do
              # Append a few characters from user.id to make the name unique
              user_id = to_string(user.id)

              user_id_suffix =
                if String.length(user_id) >= 6 do
                  start_pos = max(0, String.length(user_id) - 6)
                  String.slice(user_id, start_pos, 6)
                else
                  user_id
                end

              modified_display_name = "#{display_name} (#{user_id_suffix})"

              require Logger

              Logger.info(
                "[QB] Duplicate name detected, retrying with modified display name",
                user_id: user.id,
                original_display_name: display_name,
                modified_display_name: modified_display_name
              )

              # Retry with modified display name
              retry_params = %{
                customer_params
                | display_name: modified_display_name
              }

              case client_module().create_customer(retry_params) do
                {:ok, customer} ->
                  customer_id = Map.get(customer, "Id")

                  if customer_id do
                    # Update user with QuickBooks customer ID
                    changeset =
                      User.update_user_changeset(user, %{
                        quickbooks_customer_id: customer_id
                      })

                    case Repo.update(changeset) do
                      {:ok, _updated_user} ->
                        {:ok, customer_id}

                      {:error, changeset} ->
                        Logger.error(
                          "Failed to update user with quickbooks_customer_id",
                          user_id: user.id,
                          quickbooks_customer_id: customer_id,
                          changeset_errors: inspect(changeset.errors)
                        )

                        # Still return success for the customer creation
                        {:ok, customer_id}
                    end
                  else
                    {:error, :invalid_customer_response}
                  end

                {:error, retry_error} ->
                  {:error, retry_error}
              end
            else
              {:error, error}
            end

          {:error, error} ->
            {:error, error}
        end
      end
    end
  end

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(date) when is_binary(date), do: date
  defp format_date(_), do: nil

  defp build_display_name(%User{first_name: first_name, last_name: last_name}) do
    first = String.trim(first_name || "")
    last = String.trim(last_name || "")

    case {first, last} do
      {"", ""} -> nil
      {first, ""} -> first
      {"", last} -> last
      {first, last} -> "#{first} #{last}"
    end
  end
end
