defmodule Ysc.Quickbooks.Client do
  @moduledoc """
  QuickBooks Online API client for accounting operations.

  This client handles OAuth2 authentication and provides functions to create
  SalesReceipts (for purchases and refunds) and Deposits (for Stripe payouts).

  Implements `Ysc.Quickbooks.ClientBehaviour` for testability.
  """
  @behaviour Ysc.Quickbooks.ClientBehaviour

  require Logger

  # Default base URL (production)
  @default_api_base_url "https://quickbooks.api.intuit.com/v3"
  @token_url "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
  # Latest minor version as of 2024
  @minor_version "65"

  @doc """
  Creates a SalesReceipt in QuickBooks.

  SalesReceipts are used to record sales transactions where payment is received immediately.

  ## Configuration

  The following environment variables are required:
  - `QUICKBOOKS_CLIENT_ID` - Your QuickBooks app client ID
  - `QUICKBOOKS_CLIENT_SECRET` - Your QuickBooks app client secret
  - `QUICKBOOKS_COMPANY_ID` - Your QuickBooks company ID
  - `QUICKBOOKS_ACCESS_TOKEN` - OAuth2 access token (can be refreshed)
  - `QUICKBOOKS_REFRESH_TOKEN` - OAuth2 refresh token

  ## Usage

      alias Ysc.Quickbooks.Client

      # Create a sales receipt for a purchase
      Client.create_sales_receipt(%{
        customer_ref: %{value: "123"},
        line: [
          %{
            amount: 100.00,
            detail_type: "SalesItemLineDetail",
            sales_item_line_detail: %{
              item_ref: %{value: "456"},
              quantity: 1,
              unit_price: 100.00
            }
          }
        ],
        total_amt: 100.00
      })

      # Create a deposit for a Stripe payout
      Client.create_deposit(%{
        deposit_to_account_ref: %{value: "789"},
        line: [
          %{
            amount: 500.00,
            detail_type: "DepositLineDetail",
            deposit_line_detail: %{
              entity_ref: %{value: "101112", type: "Account"}
            }
          }
        ],
        total_amt: 500.00
      })

  ## Parameters

    - `params` - Map containing SalesReceipt data:
      - `customer_ref` (required) - Map with `value` key containing customer ID
      - `line` (required) - List of line items
      - `total_amt` (required) - Total amount
      - `payment_method_ref` (optional) - Payment method reference
      - `deposit_to_account_ref` (optional) - Account to deposit to
      - `doc_number` (optional) - Document number
      - `txn_date` (optional) - Transaction date (ISO 8601 format)
      - `private_note` (optional) - Private note
      - `memo` (optional) - Public memo

  ## Examples

      # Purchase
      Client.create_sales_receipt(%{
        customer_ref: %{value: "123"},
        line: [
          %{
            amount: 100.00,
            detail_type: "SalesItemLineDetail",
            sales_item_line_detail: %{
              item_ref: %{value: "456"},
              quantity: 1,
              unit_price: 100.00
            }
          }
        ],
        total_amt: 100.00,
        payment_method_ref: %{value: "789"},
        txn_date: "2024-01-15"
      })

      # Refund (negative amount)
      Client.create_sales_receipt(%{
        customer_ref: %{value: "123"},
        line: [
          %{
            amount: -50.00,
            detail_type: "SalesItemLineDetail",
            sales_item_line_detail: %{
              item_ref: %{value: "456"},
              quantity: 1,
              unit_price: -50.00
            }
          }
        ],
        total_amt: -50.00,
        payment_method_ref: %{value: "789"},
        txn_date: "2024-01-15"
      })

  """
  @spec create_sales_receipt(map(), keyword()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def create_sales_receipt(params, opts \\ []) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Support idempotency via requestid parameter
      idempotency_key =
        case Keyword.get(opts, :idempotency_key) do
          nil -> Keyword.get(opts, :requestid)
          key -> key
        end

      url_opts = if idempotency_key, do: [requestid: idempotency_key], else: []
      url = build_url(company_id, "salesreceipt", url_opts)
      headers = build_headers(access_token)
      body = build_sales_receipt_body(params)

      Logger.info("Creating QuickBooks SalesReceipt",
        company_id: company_id,
        total_amt: Map.get(params, :total_amt),
        idempotency_key: idempotency_key
      )

      # Print the full request body in a readable JSON format for debugging
      body_json = Jason.encode!(body, pretty: true)

      Logger.info(
        "[QB Client] create_sales_receipt: Full request body being sent to QuickBooks:\n#{body_json}"
      )

      Logger.debug(
        "[QB Client] create_sales_receipt: Request body (structured)",
        body: inspect(body, limit: :infinity, pretty: true)
      )

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              sales_receipt = get_response_entity(data, "SalesReceipt")

              Logger.info("Successfully created QuickBooks SalesReceipt",
                sales_receipt_id: Map.get(sales_receipt, "Id"),
                total_amt: Map.get(sales_receipt, "TotalAmt")
              )

              {:ok, sales_receipt}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error),
                response: response_body
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "QuickBooks authentication failed, attempting token refresh"
          )

          # Try to refresh token and retry once
          case refresh_access_token() do
            {:ok, new_access_token} ->
              # Retry with new token (URL already includes idempotency key)
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      sales_receipt = get_response_entity(data, "SalesReceipt")
                      {:ok, sales_receipt}

                    {:error, error} ->
                      Logger.error(
                        "Failed to parse QuickBooks response after retry",
                        error: inspect(error)
                      )

                      {:error, :invalid_response}
                  end

                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error("QuickBooks API error after token refresh",
                    status: status,
                    error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh",
                    error: inspect(error)
                  )

                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token",
                error: inspect(error)
              )

              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("QuickBooks API error",
            status: status,
            error: error,
            endpoint: "salesreceipt"
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to create QuickBooks SalesReceipt",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  @doc """
  Creates a Refund Receipt in QuickBooks.

  Refund Receipts are used to record refunds. Unlike SalesReceipts,
  Refund Receipts use positive amounts - the transaction type determines the direction.
  """
  @spec create_refund_receipt(map(), keyword()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def create_refund_receipt(params, opts \\ []) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Support idempotency via requestid parameter
      idempotency_key =
        case Keyword.get(opts, :idempotency_key) do
          nil -> Keyword.get(opts, :requestid)
          key -> key
        end

      url_opts = if idempotency_key, do: [requestid: idempotency_key], else: []
      url = build_url(company_id, "refundreceipt", url_opts)
      headers = build_headers(access_token)
      body = build_refund_receipt_body(params)

      Logger.info("Creating QuickBooks Refund Receipt",
        company_id: company_id,
        customer_id: params.customer_ref[:value],
        idempotency_key: idempotency_key
      )

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              refund_receipt = get_response_entity(data, "RefundReceipt")

              Logger.info("Successfully created QuickBooks Refund Receipt",
                refund_receipt_id: Map.get(refund_receipt, "Id")
              )

              {:ok, refund_receipt}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error),
                response: response_body
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "QuickBooks authentication failed, attempting token refresh"
          )

          # Try to refresh token and retry once
          case refresh_access_token() do
            {:ok, new_access_token} ->
              # Retry with new token (URL already includes idempotency key)
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      refund_receipt =
                        get_response_entity(data, "RefundReceipt")

                      {:ok, refund_receipt}

                    {:error, error} ->
                      Logger.error(
                        "Failed to parse QuickBooks response after retry",
                        error: inspect(error)
                      )

                      {:error, :invalid_response}
                  end

                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error("QuickBooks API error after token refresh",
                    status: status,
                    error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh",
                    error: inspect(error)
                  )

                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token",
                error: inspect(error)
              )

              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("QuickBooks API error",
            status: status,
            error: error,
            endpoint: "refundreceipt"
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to create QuickBooks Refund Receipt",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  @doc """
  Creates a Deposit in QuickBooks.

  Deposits are used to record money deposited into a bank account.
  This is typically used for Stripe payouts.

  ## Parameters

    - `params` - Map containing Deposit data:
      - `deposit_to_account_ref` (required) - Map with `value` key containing bank account ID
      - `line` (required) - List of deposit line items
      - `total_amt` (required) - Total deposit amount
      - `txn_date` (optional) - Transaction date (ISO 8601 format)
      - `private_note` (optional) - Private note
      - `memo` (optional) - Public memo

  ## Examples

      # Stripe payout deposit
      Client.create_deposit(%{
        deposit_to_account_ref: %{value: "789"},
        line: [
          %{
            amount: 500.00,
            detail_type: "DepositLineDetail",
            deposit_line_detail: %{
              entity_ref: %{value: "101112", type: "Account"}
            }
          }
        ],
        total_amt: 500.00,
        txn_date: "2024-01-15",
        memo: "Stripe payout for period ending 2024-01-15"
      })

  """
  @spec create_deposit(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def create_deposit(params, opts \\ []) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Support idempotency via requestid parameter
      idempotency_key =
        case Keyword.get(opts, :idempotency_key) do
          nil -> Keyword.get(opts, :requestid)
          key -> key
        end

      url_opts = if idempotency_key, do: [requestid: idempotency_key], else: []
      url = build_url(company_id, "deposit", url_opts)
      headers = build_headers(access_token)
      body = build_deposit_body(params)

      Logger.info("Creating QuickBooks Deposit",
        company_id: company_id,
        total_amt: Map.get(params, :total_amt),
        idempotency_key: idempotency_key
      )

      # Print the full request body in a readable JSON format for debugging
      body_json = Jason.encode!(body, pretty: true)

      Logger.info(
        "[QB Client] create_deposit: Full request body being sent to QuickBooks:\n#{body_json}"
      )

      Logger.debug("[QB Client] create_deposit: Request body (structured)",
        body: inspect(body, limit: :infinity, pretty: true)
      )

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              deposit = get_response_entity(data, "Deposit")

              Logger.info("Successfully created QuickBooks Deposit",
                deposit_id: Map.get(deposit, "Id"),
                total_amt: Map.get(deposit, "TotalAmt")
              )

              {:ok, deposit}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error),
                response: response_body
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "QuickBooks authentication failed, attempting token refresh"
          )

          # Try to refresh token and retry once
          case refresh_access_token() do
            {:ok, new_access_token} ->
              # Retry with new token (URL already includes idempotency key)
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      deposit = get_response_entity(data, "Deposit")
                      {:ok, deposit}

                    {:error, error} ->
                      Logger.error(
                        "Failed to parse QuickBooks response after retry",
                        error: inspect(error)
                      )

                      {:error, :invalid_response}
                  end

                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error("QuickBooks API error after token refresh",
                    status: status,
                    error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh",
                    error: inspect(error)
                  )

                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token",
                error: inspect(error)
              )

              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("QuickBooks API error",
            status: status,
            error: error,
            endpoint: "deposit"
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to create QuickBooks Deposit",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  @doc """
  Creates a Customer in QuickBooks.

  ## Parameters

    - `params` - Map containing Customer data:
      - `display_name` (required) - Customer display name
      - `email` (optional) - Primary email address
      - `phone` (optional) - Primary phone number
      - `company_name` (optional) - Company name
      - `given_name` (optional) - First name
      - `family_name` (optional) - Last name
      - `notes` (optional) - Notes about the customer
      - `bill_address` (optional) - Billing address map with keys: line1, city, country_sub_division_code, postal_code, country

  ## Examples

      Client.create_customer(%{
        display_name: "John Doe",
        email: "john@example.com",
        phone: "555-1234",
        given_name: "John",
        family_name: "Doe"
      })

  """
  @spec create_customer(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def create_customer(params, opts \\ []) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Support idempotency via requestid parameter
      idempotency_key =
        case Keyword.get(opts, :idempotency_key) do
          nil -> Keyword.get(opts, :requestid)
          key -> key
        end

      url_opts = if idempotency_key, do: [requestid: idempotency_key], else: []
      url = build_url(company_id, "customer", url_opts)
      headers = build_headers(access_token)
      body = build_customer_body(params)

      Logger.info("Creating QuickBooks Customer",
        company_id: company_id,
        display_name: params.display_name,
        idempotency_key: idempotency_key
      )

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              customer = get_response_entity(data, "Customer")

              Logger.info("Successfully created QuickBooks Customer",
                customer_id: Map.get(customer, "Id"),
                display_name: Map.get(customer, "DisplayName")
              )

              {:ok, customer}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error),
                response: response_body
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "QuickBooks authentication failed, attempting token refresh"
          )

          # Try to refresh token and retry once
          case refresh_access_token() do
            {:ok, new_access_token} ->
              # Retry with new token (URL already includes idempotency key)
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      customer = get_response_entity(data, "Customer")
                      {:ok, customer}

                    {:error, error} ->
                      Logger.error(
                        "Failed to parse QuickBooks response after retry",
                        error: inspect(error)
                      )

                      {:error, :invalid_response}
                  end

                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error("QuickBooks API error after token refresh",
                    status: status,
                    error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh",
                    error: inspect(error)
                  )

                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token",
                error: inspect(error)
              )

              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("QuickBooks API error",
            status: status,
            error: error,
            endpoint: "customer"
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to create QuickBooks Customer",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  @doc """
  Gets or creates a QuickBooks Item by name.

  First tries to find an existing item by name, and if not found, creates a new one.
  Returns the item ID.

  ## Parameters

    - `name` - The name of the item to find or create
    - `opts` - Optional parameters:
      - `:type` - Item type (default: "Service"). Can be "Service", "Inventory", "NonInventory"
      - `:income_account_ref` - Income account reference (optional)
      - `:expense_account_ref` - Expense account reference (optional)

  ## Examples

      Client.get_or_create_item("Event Tickets")
      Client.get_or_create_item("Donations", type: "Service")
  """
  @spec get_or_create_item(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, atom() | String.t()}
  def get_or_create_item(name, opts \\ []) do
    Logger.debug("[QB Client] get_or_create_item: Getting or creating item",
      name: name,
      opts: opts
    )

    # First check cache
    cache_key = "qb_item_#{name}"
    cached_id = get_cached_item_id(cache_key)

    if cached_id do
      Logger.debug("[QB Client] get_or_create_item: Found in cache",
        name: name,
        item_id: cached_id
      )

      {:ok, cached_id}
    else
      # Try to find existing item
      case query_item_by_name(name) do
        {:ok, item_id} ->
          cache_item_id(cache_key, item_id)
          {:ok, item_id}

        {:error, :not_found} ->
          # Create new item
          Logger.info(
            "[QB Client] get_or_create_item: Item not found, creating new item",
            name: name
          )

          case create_item(name, opts) do
            {:ok, item_id} ->
              cache_item_id(cache_key, item_id)
              {:ok, item_id}

            error ->
              error
          end

        error ->
          error
      end
    end
  end

  defp query_item_by_name(name) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Query for item by name
      query =
        "SELECT Id, Name FROM Item WHERE Name = '#{escape_query_string(name)}' AND Active = true"

      url = build_query_url(company_id, query)
      headers = build_headers(access_token)

      Logger.debug("[QB Client] query_item_by_name: Querying for item",
        name: name,
        query: query
      )

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"QueryResponse" => %{"Item" => items}}}
            when is_list(items) and items != [] ->
              item = List.first(items)
              item_id = Map.get(item, "Id")

              Logger.debug("[QB Client] query_item_by_name: Found item",
                name: name,
                item_id: item_id
              )

              {:ok, item_id}

            {:ok, %{"QueryResponse" => %{"Item" => item}}} when is_map(item) ->
              item_id = Map.get(item, "Id")

              Logger.debug("[QB Client] query_item_by_name: Found item",
                name: name,
                item_id: item_id
              )

              {:ok, item_id}

            {:ok, %{"QueryResponse" => _}} ->
              Logger.debug("[QB Client] query_item_by_name: Item not found",
                name: name
              )

              {:error, :not_found}

            {:ok, data} ->
              Logger.error(
                "[QB Client] query_item_by_name: Unexpected response format",
                name: name,
                data: inspect(data)
              )

              {:error, :invalid_response}

            {:error, error} ->
              Logger.error(
                "[QB Client] query_item_by_name: Failed to parse response",
                name: name,
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "[QB Client] query_item_by_name: Authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:get, url, headers)

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, %{"QueryResponse" => %{"Item" => items}}}
                    when is_list(items) and items != [] ->
                      item_id = List.first(items) |> Map.get("Id")
                      {:ok, item_id}

                    {:ok, %{"QueryResponse" => %{"Item" => item}}}
                    when is_map(item) ->
                      item_id = Map.get(item, "Id")
                      {:ok, item_id}

                    _ ->
                      {:error, :not_found}
                  end

                _ ->
                  {:error, :query_failed}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          Logger.error("[QB Client] query_item_by_name: Query failed",
            name: name,
            status: status,
            response: response_body
          )

          {:error, :query_failed}

        {:error, error} ->
          Logger.error("[QB Client] query_item_by_name: Request failed",
            name: name,
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  defp create_item(name, opts) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      item_type = Keyword.get(opts, :type, "Service")

      # Support idempotency via requestid parameter
      idempotency_key =
        case Keyword.get(opts, :idempotency_key) do
          nil -> Keyword.get(opts, :requestid)
          key -> key
        end

      url_opts = if idempotency_key, do: [requestid: idempotency_key], else: []
      url = build_url(company_id, "item", url_opts)
      headers = build_headers(access_token)

      body = build_item_body(name, item_type, opts)

      Logger.debug("[QB Client] create_item: Creating item",
        name: name,
        type: item_type,
        idempotency_key: idempotency_key
      )

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              item = get_response_entity(data, "Item")
              item_id = Map.get(item, "Id")

              Logger.info("[QB Client] create_item: Successfully created item",
                name: name,
                item_id: item_id
              )

              {:ok, item_id}

            {:error, error} ->
              Logger.error("[QB Client] create_item: Failed to parse response",
                name: name,
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "[QB Client] create_item: Authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              # URL already includes idempotency key for retry
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      item = get_response_entity(data, "Item")
                      item_id = Map.get(item, "Id")
                      {:ok, item_id}

                    _error ->
                      {:error, :invalid_response}
                  end

                _ ->
                  {:error, :create_failed}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("[QB Client] create_item: Failed to create item",
            name: name,
            status: status,
            error: error
          )

          {:error, error}

        {:error, error} ->
          Logger.error("[QB Client] create_item: Request failed",
            name: name,
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  defp build_item_body(name, type, opts) do
    base = %{
      "Name" => name,
      "Type" => type,
      "Active" => true
    }

    base
    |> maybe_put("IncomeAccountRef", opts[:income_account_ref])
    |> maybe_put("ExpenseAccountRef", opts[:expense_account_ref])
  end

  defp build_query_url(company_id, query) do
    base_url = get_api_base_url()
    base_url = String.trim_trailing(base_url, "/")

    base_url =
      if String.ends_with?(base_url, "/company"),
        do: String.replace_suffix(base_url, "/company", ""),
        else: base_url

    encoded_query = URI.encode(query)

    "#{base_url}/company/#{company_id}/query?query=#{encoded_query}&minorversion=#{@minor_version}"
  end

  defp escape_query_string(str) do
    str
    |> String.replace("'", "''")
    |> String.replace("\\", "\\\\")
  end

  defp get_cached_item_id(cache_key) do
    # Use application environment as a simple cache
    Application.get_env(:ysc, :quickbooks_item_cache, %{})[cache_key]
  end

  defp cache_item_id(cache_key, item_id) do
    current_cache = Application.get_env(:ysc, :quickbooks_item_cache, %{})
    updated_cache = Map.put(current_cache, cache_key, item_id)
    Application.put_env(:ysc, :quickbooks_item_cache, updated_cache)
  end

  # Private functions

  defp build_url(company_id, endpoint, opts \\ []) do
    base_url = get_api_base_url()

    # Ensure base_url doesn't have trailing slash and doesn't already include /company
    base_url = String.trim_trailing(base_url, "/")

    base_url =
      if String.ends_with?(base_url, "/company"),
        do: String.replace_suffix(base_url, "/company", ""),
        else: base_url

    # Build query parameters
    query_params = ["minorversion=#{@minor_version}"]

    # Add requestid for idempotency if provided
    query_params =
      if idempotency_key = Keyword.get(opts, :requestid) do
        ["requestid=#{URI.encode(idempotency_key)}" | query_params]
      else
        query_params
      end

    query_string = Enum.join(query_params, "&")
    "#{base_url}/company/#{company_id}/#{endpoint}?#{query_string}"
  end

  defp get_api_base_url do
    case Application.get_env(:ysc, :quickbooks)[:url] do
      nil -> @default_api_base_url
      url when is_binary(url) -> url
      _ -> @default_api_base_url
    end
  end

  defp build_headers(access_token) do
    [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  defp build_sales_receipt_body(params) do
    Logger.info(
      "[QB Client] build_sales_receipt_body: Input params:\n#{inspect(params, limit: :infinity, pretty: true)}"
    )

    # Convert TotalAmt to number if it's a Decimal
    total_amt_value =
      case params.total_amt do
        %Decimal{} = amt -> Decimal.to_float(amt)
        amt when is_number(amt) -> amt
        _ -> 0
      end

    # Ensure CustomerRef has both value and name if available
    # CRITICAL: Log a warning if customer_ref is nil or invalid
    customer_ref =
      case params.customer_ref do
        %{value: value, name: name} when not is_nil(value) and value != "" ->
          %{"value" => to_string(value), "name" => name}

        %{value: value} when not is_nil(value) and value != "" ->
          %{"value" => to_string(value)}

        nil ->
          Logger.error(
            "[QB Client] build_sales_receipt_body: CRITICAL - customer_ref is nil! This will cause a 2020 error."
          )

          nil

        invalid ->
          Logger.error(
            "[QB Client] build_sales_receipt_body: CRITICAL - customer_ref has invalid format: #{inspect(invalid)}"
          )

          invalid
      end

    # Ensure DepositToAccountRef has both value and name if available
    deposit_to_account_ref =
      if params[:deposit_to_account_ref] do
        case params[:deposit_to_account_ref] do
          %{value: value, name: name} -> %{value: value, name: name}
          %{value: value} -> %{value: value}
          _ -> params[:deposit_to_account_ref]
        end
      else
        nil
      end

    # Do not include Id field for create operations (QuickBooks will assign it)
    body =
      %{
        "CustomerRef" => customer_ref,
        "Line" => Enum.map(params.line, &normalize_line_item/1),
        "TotalAmt" => total_amt_value
      }
      |> maybe_put("DepositToAccountRef", deposit_to_account_ref)
      |> maybe_put("PaymentMethodRef", params[:payment_method_ref])
      |> maybe_put("DocNumber", params[:doc_number])
      |> maybe_put("TxnDate", params[:txn_date])
      |> maybe_put(
        "CustomerMemo",
        if(params[:memo], do: %{value: params[:memo]}, else: nil)
      )
      |> maybe_put("PrivateNote", params[:private_note])

    Logger.info(
      "[QB Client] build_sales_receipt_body: Final body structure:\n#{inspect(body, limit: :infinity, pretty: true)}"
    )

    body
  end

  defp build_refund_receipt_body(params) do
    Logger.info(
      "[QB Client] build_refund_receipt_body: Input params:\n#{inspect(params, limit: :infinity, pretty: true)}"
    )

    # Convert TotalAmt to number if it's a Decimal
    # Refund Receipts use POSITIVE amounts - the transaction type determines direction
    total_amt_value =
      case params.total_amt do
        %Decimal{} = amt -> Decimal.to_float(Decimal.abs(amt))
        amt when is_number(amt) -> abs(amt)
        _ -> 0
      end

    # Ensure CustomerRef has both value and name if available
    # CRITICAL: Log a warning if customer_ref is nil or invalid
    customer_ref =
      case params.customer_ref do
        %{value: value, name: name} when not is_nil(value) and value != "" ->
          %{"value" => to_string(value), "name" => name}

        %{value: value} when not is_nil(value) and value != "" ->
          %{"value" => to_string(value)}

        nil ->
          Logger.error(
            "[QB Client] build_refund_receipt_body: CRITICAL - customer_ref is nil! This will cause a 2020 error."
          )

          nil

        invalid ->
          Logger.error(
            "[QB Client] build_refund_receipt_body: CRITICAL - customer_ref has invalid format: #{inspect(invalid)}"
          )

          invalid
      end

    # Refund Receipts use positive amounts - the transaction type determines the direction
    body =
      %{
        "CustomerRef" => customer_ref,
        "Line" => Enum.map(params.line, &normalize_line_item/1),
        "TotalAmt" => total_amt_value
      }
      |> maybe_put("DocNumber", params[:doc_number])
      |> maybe_put("TxnDate", params[:txn_date])
      |> maybe_put("DepositToAccountRef", params[:refund_from_account_ref])
      |> maybe_put("PaymentMethodRef", params[:payment_method_ref])
      |> maybe_put(
        "CustomerMemo",
        if(params[:memo], do: %{value: params[:memo]}, else: nil)
      )
      |> maybe_put("PrivateNote", params[:private_note])

    Logger.info(
      "[QB Client] build_refund_receipt_body: Final body structure:\n#{inspect(body, limit: :infinity, pretty: true)}"
    )

    body
  end

  defp build_deposit_body(params) do
    %{
      "DepositToAccountRef" => params.deposit_to_account_ref,
      "Line" => Enum.map(params.line, &normalize_deposit_line_item/1),
      "TotalAmt" => params.total_amt
    }
    |> maybe_put("TxnDate", params[:txn_date])
    |> maybe_put("PrivateNote", params[:private_note])
    |> maybe_put("Memo", params[:memo])
  end

  defp build_customer_body(params) do
    %{"DisplayName" => params.display_name}
    |> maybe_put("GivenName", params[:given_name])
    |> maybe_put("FamilyName", params[:family_name])
    |> maybe_put("CompanyName", params[:company_name])
    |> maybe_put(
      "PrimaryEmailAddr",
      params[:email] && %{"Address" => params.email}
    )
    |> maybe_put(
      "PrimaryPhone",
      params[:phone] && %{"FreeFormNumber" => params.phone}
    )
    |> maybe_put("Notes", params[:notes])
    |> maybe_put("BillAddr", build_address(params[:bill_address]))
  end

  defp build_address(nil), do: nil

  defp build_address(addr) when is_map(addr) do
    %{}
    |> maybe_put("Line1", addr[:line1])
    |> maybe_put("City", addr[:city])
    |> maybe_put("CountrySubDivisionCode", addr[:country_sub_division_code])
    |> maybe_put("PostalCode", addr[:postal_code])
    |> maybe_put("Country", addr[:country] || "USA")
  end

  defp normalize_line_item(item) do
    Logger.debug("[QB Client] normalize_line_item: Input item",
      item: inspect(item, limit: :infinity)
    )

    amount_value = normalize_amount_value(item.amount)

    base = %{
      "Amount" => amount_value,
      "DetailType" => item.detail_type
    }

    result =
      case item.detail_type do
        "SalesItemLineDetail" ->
          normalize_sales_item_line_detail(base, item.sales_item_line_detail)

        "DiscountLineDetail" ->
          normalize_discount_line_detail(base, item.discount_line_detail)

        _ ->
          base
      end

    add_description_if_present(result, item)
  end

  defp normalize_amount_value(amount) do
    case amount do
      %Decimal{} = amt -> Decimal.to_float(Decimal.abs(amt))
      amt when is_number(amt) -> abs(amt)
      _ -> 0
    end
  end

  defp normalize_sales_item_line_detail(base, detail) do
    Logger.debug("[QB Client] normalize_line_item: SalesItemLineDetail",
      detail: inspect(detail, limit: :infinity)
    )

    qty_value = normalize_quantity_value(detail.quantity)
    unit_price_value = normalize_unit_price_value(detail.unit_price)

    Logger.debug("[QB Client] normalize_line_item: Converted values",
      qty_value: qty_value,
      unit_price_value: unit_price_value,
      qty_type: inspect(qty_value),
      unit_price_type: inspect(unit_price_value)
    )

    item_ref = normalize_item_ref(detail.item_ref)

    sales_detail = %{
      "ItemRef" => item_ref,
      "Qty" => qty_value,
      "UnitPrice" => unit_price_value
    }

    sales_detail = add_tax_code_ref_if_present(sales_detail, detail)
    sales_detail = add_class_ref_if_present(sales_detail, detail)

    Map.put(base, "SalesItemLineDetail", sales_detail)
  end

  defp normalize_quantity_value(quantity) do
    case quantity do
      %Decimal{} = qty -> Decimal.to_float(qty)
      qty when is_number(qty) -> qty
      _ -> 1
    end
  end

  defp normalize_unit_price_value(unit_price) do
    case unit_price do
      %Decimal{} = price -> Decimal.to_float(Decimal.abs(price))
      price when is_number(price) -> abs(price)
      _ -> 0
    end
  end

  defp normalize_item_ref(item_ref) do
    case item_ref do
      %{value: value, name: name} -> %{value: value, name: name}
      %{value: value} -> %{value: value}
      _ -> item_ref
    end
  end

  defp add_tax_code_ref_if_present(sales_detail, detail) do
    if detail[:tax_code_ref] do
      Map.put(sales_detail, "TaxCodeRef", detail.tax_code_ref)
    else
      sales_detail
    end
  end

  defp add_class_ref_if_present(sales_detail, detail) do
    if detail[:class_ref] do
      class_ref_map = normalize_class_ref_for_sales_detail(detail.class_ref)
      Map.put(sales_detail, "ClassRef", class_ref_map)
    else
      sales_detail
    end
  end

  defp normalize_class_ref_for_sales_detail(class_ref_value) do
    Logger.debug("[QB Client] normalize_line_item: Adding ClassRef",
      class_ref: inspect(class_ref_value)
    )

    case class_ref_value do
      %{value: value, name: name} when is_binary(value) ->
        %{"value" => value, "name" => name}

      %{value: value} when is_binary(value) ->
        %{"value" => value}

      ref when is_binary(ref) ->
        %{"value" => ref}

      other ->
        Logger.warning(
          "[QB Client] normalize_line_item: Unexpected class_ref format",
          class_ref: inspect(other)
        )

        case other do
          %{value: v} when is_binary(v) -> %{"value" => v}
          _ -> %{"value" => to_string(other)}
        end
    end
  end

  defp normalize_discount_line_detail(base, detail) do
    discount_detail = %{}

    discount_detail =
      add_discount_field_if_present(
        discount_detail,
        detail,
        :class_ref,
        "ClassRef"
      )

    discount_detail =
      add_discount_field_if_present(
        discount_detail,
        detail,
        :percent_based,
        "PercentBased"
      )

    discount_detail =
      add_discount_field_if_present(
        discount_detail,
        detail,
        :discount_percent,
        "DiscountPercent"
      )

    discount_detail =
      add_discount_field_if_present(
        discount_detail,
        detail,
        :discount_account_ref,
        "DiscountAccountRef"
      )

    Map.put(base, "DiscountLineDetail", discount_detail)
  end

  defp add_discount_field_if_present(
         discount_detail,
         detail,
         field_key,
         map_key
       ) do
    if detail[field_key] do
      Map.put(discount_detail, map_key, detail[field_key])
    else
      discount_detail
    end
  end

  defp add_description_if_present(result, item) do
    if item[:description] do
      Map.put(result, "Description", item.description)
    else
      result
    end
  end

  defp normalize_deposit_line_item(item) do
    # Convert Amount to float if it's a Decimal
    amount_value =
      case item.amount do
        %Decimal{} = amt -> Decimal.to_float(amt)
        amt when is_number(amt) -> amt
        _ -> 0
      end

    base = %{
      "Amount" => amount_value,
      "DetailType" => item.detail_type
    }

    case item.detail_type do
      "DepositLineDetail" ->
        detail = item.deposit_line_detail
        detail_map = %{}

        detail_map =
          if detail[:account_ref] do
            Map.put(detail_map, "AccountRef", detail.account_ref)
          else
            detail_map
          end

        detail_map =
          if detail[:class_ref] do
            # Normalize class_ref to proper format
            class_ref_map =
              case detail.class_ref do
                %{value: value, name: name} when is_binary(value) ->
                  %{"value" => value, "name" => name}

                %{value: value} when is_binary(value) ->
                  %{"value" => value}

                ref when is_binary(ref) ->
                  %{"value" => ref}

                other ->
                  case other do
                    %{value: v} when is_binary(v) -> %{"value" => v}
                    _ -> nil
                  end
              end

            if class_ref_map do
              Map.put(detail_map, "ClassRef", class_ref_map)
            else
              detail_map
            end
          else
            detail_map
          end

        detail_map =
          if detail[:payment_method_ref] do
            Map.put(detail_map, "PaymentMethodRef", detail.payment_method_ref)
          else
            detail_map
          end

        result = Map.put(base, "DepositLineDetail", detail_map)

        # Add LinkedTxn at the line level (not inside DepositLineDetail)
        # This is the correct way to link deposits to SalesReceipts/RefundReceipts
        result =
          case item[:linked_txn] do
            [_ | _] = linked_txns ->
              linked_txn_list =
                Enum.map(linked_txns, fn txn ->
                  %{
                    "TxnId" => txn.txn_id,
                    "TxnType" => txn.txn_type
                  }
                end)

              Map.put(result, "LinkedTxn", linked_txn_list)

            _ ->
              result
          end

        maybe_put(result, "Description", item[:description])

      _ ->
        base
    end
  end

  @doc """
  Queries for a QuickBooks Class by name.

  Returns {:ok, class_id} if found, {:error, :not_found} otherwise.

  Results are aggressively cached since class references don't change.
  """
  @spec query_class_by_name(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def query_class_by_name(name) do
    # Step 1: Check cache first (aggressive caching - these don't change)
    cache_key = "quickbooks:class:#{name}"

    case get_cached_class_id(cache_key) do
      {:ok, class_id} when not is_nil(class_id) ->
        Logger.debug("[QB Client] query_class_by_name: Found in cache",
          name: name,
          class_id: class_id
        )

        {:ok, class_id}

      _ ->
        # Not in cache, query QuickBooks
        query_class_by_name_from_api(name, cache_key)
    end
  end

  defp query_class_by_name_from_api(name, cache_key) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Query for class by name
      query =
        "SELECT Id, Name FROM Class WHERE Name = '#{escape_query_string(name)}' AND Active = true"

      url = build_query_url(company_id, query)
      headers = build_headers(access_token)

      Logger.debug("[QB Client] query_class_by_name: Querying for class",
        name: name,
        query: query
      )

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"QueryResponse" => %{"Class" => classes}}}
            when is_list(classes) and classes != [] ->
              class = List.first(classes)
              class_id = Map.get(class, "Id")

              Logger.debug("[QB Client] query_class_by_name: Found class",
                name: name,
                class_id: class_id
              )

              # Cache the result (aggressive caching - these don't change)
              cache_class_id(cache_key, class_id)

              {:ok, class_id}

            {:ok, %{"QueryResponse" => %{"Class" => class}}}
            when is_map(class) ->
              class_id = Map.get(class, "Id")

              Logger.debug("[QB Client] query_class_by_name: Found class",
                name: name,
                class_id: class_id
              )

              # Cache the result (aggressive caching - these don't change)
              cache_class_id(cache_key, class_id)

              {:ok, class_id}

            {:ok, %{"QueryResponse" => _}} ->
              Logger.debug("[QB Client] query_class_by_name: Class not found",
                name: name
              )

              {:error, :not_found}

            {:ok, data} ->
              Logger.error(
                "[QB Client] query_class_by_name: Unexpected response format",
                name: name,
                data: inspect(data)
              )

              {:error, :invalid_response}

            {:error, error} ->
              Logger.error(
                "[QB Client] query_class_by_name: Failed to parse response",
                name: name,
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "[QB Client] query_class_by_name: Authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:get, url, headers)

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, %{"QueryResponse" => %{"Class" => classes}}}
                    when is_list(classes) and classes != [] ->
                      class = List.first(classes)
                      class_id = Map.get(class, "Id")

                      # Cache the result (aggressive caching - these don't change)
                      cache_class_id(cache_key, class_id)
                      {:ok, class_id}

                    {:ok, %{"QueryResponse" => %{"Class" => class}}}
                    when is_map(class) ->
                      class_id = Map.get(class, "Id")

                      # Cache the result (aggressive caching - these don't change)
                      cache_class_id(cache_key, class_id)
                      {:ok, class_id}

                    _ ->
                      {:error, :not_found}
                  end

                _ ->
                  {:error, :not_found}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("[QB Client] query_class_by_name: Failed to query class",
            name: name,
            status: status,
            error: error
          )

          {:error, error}

        {:error, error} ->
          Logger.error("[QB Client] query_class_by_name: Request failed",
            name: name,
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  @doc """
  Queries for all QuickBooks Classes and caches them.
  Returns a map of class name -> class ID.
  Useful for populating dropdowns and mapping user selections to Class IDs.
  """
  @spec query_all_classes() ::
          {:ok, %{String.t() => String.t()}} | {:error, atom()}
  def query_all_classes do
    # Check cache first
    cache_key = "quickbooks:classes:all"

    case Cachex.get(:ysc_cache, cache_key) do
      {:ok, classes_map} when is_map(classes_map) ->
        Logger.debug("[QB Client] query_all_classes: Found in cache",
          class_count: map_size(classes_map)
        )

        {:ok, classes_map}

      _ ->
        # Not in cache, query QuickBooks
        query_all_classes_from_api(cache_key)
    end
  end

  defp query_all_classes_from_api(cache_key) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Query for all active classes
      query = "SELECT Id, Name FROM Class WHERE Active = true"

      url = build_query_url(company_id, query)
      headers = build_headers(access_token)

      Logger.debug("[QB Client] query_all_classes: Querying for all classes")

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"QueryResponse" => %{"Class" => classes}}}
            when is_list(classes) ->
              # Build map of name -> id
              classes_map =
                classes
                |> Enum.reduce(%{}, fn class, acc ->
                  name = Map.get(class, "Name")
                  id = Map.get(class, "Id")
                  Map.put(acc, name, id)
                end)

              # Cache individual classes
              Enum.each(classes_map, fn {name, id} ->
                individual_cache_key = "quickbooks:class:#{name}"
                cache_class_id(individual_cache_key, id)
              end)

              # Cache the full map
              Cachex.put(:ysc_cache, cache_key, classes_map, ttl: :infinity)

              Logger.info(
                "[QB Client] query_all_classes: Found and cached classes",
                class_count: map_size(classes_map)
              )

              {:ok, classes_map}

            {:ok, %{"QueryResponse" => %{"Class" => class}}}
            when is_map(class) ->
              # Single class returned
              name = Map.get(class, "Name")
              id = Map.get(class, "Id")
              classes_map = %{name => id}

              # Cache individual class
              individual_cache_key = "quickbooks:class:#{name}"
              cache_class_id(individual_cache_key, id)

              # Cache the full map
              Cachex.put(:ysc_cache, cache_key, classes_map, ttl: :infinity)

              Logger.info(
                "[QB Client] query_all_classes: Found and cached single class",
                class_name: name
              )

              {:ok, classes_map}

            {:ok, %{"QueryResponse" => _}} ->
              # No classes found
              Logger.debug("[QB Client] query_all_classes: No classes found")
              {:ok, %{}}

            {:error, error} ->
              Logger.error(
                "[QB Client] query_all_classes: Failed to parse response",
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:get, url, headers)

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, %{"QueryResponse" => %{"Class" => classes}}}
                    when is_list(classes) ->
                      classes_map =
                        classes
                        |> Enum.reduce(%{}, fn class, acc ->
                          name = Map.get(class, "Name")
                          id = Map.get(class, "Id")
                          Map.put(acc, name, id)
                        end)

                      Enum.each(classes_map, fn {name, id} ->
                        individual_cache_key = "quickbooks:class:#{name}"
                        cache_class_id(individual_cache_key, id)
                      end)

                      Cachex.put(:ysc_cache, cache_key, classes_map,
                        ttl: :infinity
                      )

                      {:ok, classes_map}

                    {:ok, %{"QueryResponse" => %{"Class" => class}}}
                    when is_map(class) ->
                      name = Map.get(class, "Name")
                      id = Map.get(class, "Id")
                      classes_map = %{name => id}

                      individual_cache_key = "quickbooks:class:#{name}"
                      cache_class_id(individual_cache_key, id)

                      Cachex.put(:ysc_cache, cache_key, classes_map,
                        ttl: :infinity
                      )

                      {:ok, classes_map}

                    _ ->
                      {:ok, %{}}
                  end

                _ ->
                  {:error, :query_failed}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("[QB Client] query_all_classes: Query failed",
            status: status,
            error: error
          )

          {:error, error}

        {:error, error} ->
          Logger.error("[QB Client] query_all_classes: Request failed",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  @doc """
  Queries for a QuickBooks Account by name.

  Returns {:ok, account_id} if found, {:error, :not_found} otherwise.

  Results are aggressively cached since account references don't change.
  """
  @spec query_account_by_name(String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def query_account_by_name(name) do
    # Step 1: Check cache first (aggressive caching - these don't change)
    cache_key = "quickbooks:account:#{name}"

    case get_cached_account_id(cache_key) do
      {:ok, account_id} when not is_nil(account_id) ->
        Logger.debug("[QB Client] query_account_by_name: Found in cache",
          name: name,
          account_id: account_id
        )

        {:ok, account_id}

      _ ->
        # Not in cache, query QuickBooks
        query_account_by_name_from_api(name, cache_key)
    end
  end

  defp query_account_by_name_from_api(name, cache_key) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Query for account by name
      query =
        "SELECT Id, Name FROM Account WHERE Name = '#{escape_query_string(name)}' AND Active = true"

      url = build_query_url(company_id, query)
      headers = build_headers(access_token)

      Logger.debug("[QB Client] query_account_by_name: Querying for account",
        name: name,
        query: query
      )

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"QueryResponse" => %{"Account" => accounts}}}
            when is_list(accounts) and accounts != [] ->
              account = List.first(accounts)
              account_id = Map.get(account, "Id")

              Logger.debug("[QB Client] query_account_by_name: Found account",
                name: name,
                account_id: account_id
              )

              # Cache the result (aggressive caching - these don't change)
              cache_account_id(cache_key, account_id)

              {:ok, account_id}

            {:ok, %{"QueryResponse" => %{"Account" => account}}}
            when is_map(account) ->
              account_id = Map.get(account, "Id")

              Logger.debug("[QB Client] query_account_by_name: Found account",
                name: name,
                account_id: account_id
              )

              # Cache the result (aggressive caching - these don't change)
              cache_account_id(cache_key, account_id)

              {:ok, account_id}

            {:ok, %{"QueryResponse" => _}} ->
              Logger.debug(
                "[QB Client] query_account_by_name: Account not found",
                name: name
              )

              {:error, :not_found}

            {:ok, data} ->
              Logger.error(
                "[QB Client] query_account_by_name: Unexpected response format",
                name: name,
                data: inspect(data)
              )

              {:error, :invalid_response}

            {:error, error} ->
              Logger.error(
                "[QB Client] query_account_by_name: Failed to parse response",
                name: name,
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "[QB Client] query_account_by_name: Authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:get, url, headers)

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, %{"QueryResponse" => %{"Account" => accounts}}}
                    when is_list(accounts) and accounts != [] ->
                      account = List.first(accounts)
                      account_id = Map.get(account, "Id")

                      # Cache the result (aggressive caching - these don't change)
                      cache_account_id(cache_key, account_id)
                      {:ok, account_id}

                    {:ok, %{"QueryResponse" => %{"Account" => account}}}
                    when is_map(account) ->
                      account_id = Map.get(account, "Id")

                      # Cache the result (aggressive caching - these don't change)
                      cache_account_id(cache_key, account_id)
                      {:ok, account_id}

                    _ ->
                      {:error, :not_found}
                  end

                _ ->
                  {:error, :not_found}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error(
            "[QB Client] query_account_by_name: Failed to query account",
            name: name,
            status: status,
            error: error
          )

          {:error, error}

        {:error, error} ->
          Logger.error("[QB Client] query_account_by_name: Request failed",
            name: name,
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  defp maybe_put(map, key, value) when is_map(map) do
    if value != nil, do: Map.put(map, key, value), else: map
  end

  defp get_response_entity(data, entity_name) do
    case data do
      %{"QueryResponse" => %{^entity_name => [entity | _]}} -> entity
      %{"QueryResponse" => %{^entity_name => entity}} -> entity
      %{^entity_name => entity} -> entity
      _ -> data
    end
  end

  defp parse_error_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"Fault" => fault}} ->
        error = fault["Error"] || []
        first_error = List.first(error) || %{}

        message =
          first_error["Message"] || first_error["Detail"] || "Unknown error"

        code = first_error["code"] || "UNKNOWN"
        "#{code}: #{message}"

      {:ok, data} ->
        inspect(data)

      {:error, _} ->
        response_body
    end
  end

  # Extract fault from upload response (different structure than regular API responses)
  defp extract_fault_from_response(data) do
    case data do
      %{"AttachableResponse" => [%{"Fault" => fault} | _]} ->
        fault

      %{"Fault" => fault} ->
        fault

      _ ->
        nil
    end
  end

  # Format fault error message
  defp format_fault_error(fault) do
    error = fault["Error"] || []
    first_error = List.first(error) || %{}
    message = first_error["Message"] || first_error["Detail"] || "Unknown error"
    code = first_error["code"] || "UNKNOWN"
    "#{code}: #{message}"
  end

  defp extract_vendor_id_from_error(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"Fault" => fault}} ->
        error = fault["Error"] || []
        first_error = List.first(error) || %{}
        detail = first_error["Detail"] || ""

        # Extract vendor ID from detail like "The name supplied already exists. : Id=58"
        case Regex.run(~r/Id=(\d+)/, detail) do
          [_, id] -> id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_access_token do
    if Ysc.Env.test?() do
      {:ok, "test_access_token"}
    else
      # Step 1: Check cache for access token first
      cached_access_token = get_cached_access_token()

      if cached_access_token do
        Logger.debug("[QB Client] get_access_token: Using cached access token")
        {:ok, cached_access_token}
      else
        # Step 2: Check config for access token
        qb_config = Application.get_env(:ysc, :quickbooks, [])

        Logger.debug("[QB Client] get_access_token: Checking configuration",
          has_access_token: !is_nil(qb_config[:access_token]),
          has_refresh_token: !is_nil(qb_config[:refresh_token]),
          has_client_id: !is_nil(qb_config[:client_id]),
          has_client_secret: !is_nil(qb_config[:client_secret]),
          has_company_id: !is_nil(qb_config[:company_id])
        )

        case qb_config[:access_token] do
          nil ->
            Logger.debug(
              "[QB Client] get_access_token: Access token not configured, attempting to refresh"
            )

            # Try to refresh the token if we have a refresh token
            case refresh_access_token() do
              {:ok, new_token} ->
                Logger.debug(
                  "[QB Client] get_access_token: Successfully refreshed access token"
                )

                {:ok, new_token}

              error ->
                Logger.warning(
                  "[QB Client] get_access_token: Failed to refresh token",
                  error: inspect(error)
                )

                {:error, :quickbooks_access_token_not_configured}
            end

          token ->
            Logger.debug(
              "[QB Client] get_access_token: Using configured access token"
            )

            {:ok, token}
        end
      end
    end
  end

  defp get_company_id do
    case Application.get_env(:ysc, :quickbooks)[:company_id] do
      nil -> {:error, :quickbooks_company_id_not_configured}
      company_id -> {:ok, company_id}
    end
  end

  defp refresh_access_token do
    Logger.debug("[QB Client] refresh_access_token: Starting token refresh")

    # Step 1: Check cache for refresh token
    cached_refresh_token = get_cached_refresh_token()
    # Step 2: Get original refresh token from config (env variable) as fallback
    original_refresh_token = get_original_refresh_token()

    # Use cached token if available, otherwise use original from config
    refresh_token_to_use = cached_refresh_token || original_refresh_token

    if is_nil(refresh_token_to_use) do
      Logger.warning(
        "[QB Client] refresh_access_token: No refresh token available in cache, database, or config (env variables)"
      )

      {:error, :quickbooks_refresh_token_not_configured}
    else
      Logger.debug("[QB Client] refresh_access_token: Using refresh token",
        source: if(cached_refresh_token, do: "cache", else: "config")
      )

      # Attempt refresh with the selected token
      case attempt_token_refresh(refresh_token_to_use) do
        {:ok, access_token, new_refresh_token} ->
          # Step 3: On success, store both new access token and refresh token in cache
          cache_access_token(access_token)
          cache_refresh_token(new_refresh_token)
          update_token_config(access_token, new_refresh_token)

          Logger.warning(
            "[QB Client] ⚠️  IMPORTANT: New refresh token received. Update your .env file with: QUICKBOOKS_REFRESH_TOKEN=\"#{new_refresh_token}\""
          )

          Logger.info(
            "[QB Client] Successfully refreshed QuickBooks access token",
            access_token_length: String.length(access_token),
            refresh_token_length: String.length(new_refresh_token),
            access_token_preview: String.slice(access_token, 0, 20) <> "...",
            refresh_token_preview:
              String.slice(new_refresh_token, 0, 20) <> "..."
          )

          {:ok, access_token}

        {:error, _reason}
        when not is_nil(cached_refresh_token) and
               not is_nil(original_refresh_token) ->
          # Cached token failed, try with original from config
          Logger.warning(
            "[QB Client] refresh_access_token: Cached refresh token failed, attempting with original from config"
          )

          case attempt_token_refresh(original_refresh_token) do
            {:ok, access_token, new_refresh_token} ->
              # Success with original token - cache both new tokens
              cache_access_token(access_token)
              cache_refresh_token(new_refresh_token)
              update_token_config(access_token, new_refresh_token)

              Logger.info(
                "[QB Client] Successfully refreshed QuickBooks access token using original token from config"
              )

              {:ok, access_token}

            error ->
              # Both failed
              Logger.error(
                "[QB Client] refresh_access_token: Both cached and original refresh tokens failed"
              )

              error
          end

        error ->
          error
      end
    end
  end

  defp attempt_token_refresh(refresh_token) do
    with {:ok, client_id} <- get_client_id(),
         {:ok, client_secret} <- get_client_secret() do
      Logger.debug("[QB Client] attempt_token_refresh: Making refresh request",
        url: @token_url,
        has_client_id: !is_nil(client_id),
        has_client_secret: !is_nil(client_secret),
        has_refresh_token: !is_nil(refresh_token)
      )

      url = @token_url

      headers = [
        {"Content-Type", "application/x-www-form-urlencoded"},
        {"Accept", "application/json"}
      ]

      body =
        URI.encode_query(%{
          grant_type: "refresh_token",
          refresh_token: refresh_token
        })

      # Create Basic Auth header: Base64(ClientID:ClientSecret)
      auth_header = Base.encode64("#{client_id}:#{client_secret}")
      headers = [{"Authorization", "Basic #{auth_header}"} | headers]

      request = Finch.build(:post, url, headers, body)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          Logger.debug(
            "[QB Client] attempt_token_refresh: Got successful response",
            status: status
          )

          case Jason.decode(response_body) do
            {:ok,
             %{
               "access_token" => access_token,
               "refresh_token" => new_refresh_token
             } =
                 response_data} ->
              # Extract expiration info if available
              expires_in = Map.get(response_data, "expires_in")
              token_type = Map.get(response_data, "token_type", "Bearer")

              Logger.debug(
                "[QB Client] attempt_token_refresh: Token refresh successful",
                expires_in: expires_in,
                token_type: token_type
              )

              {:ok, access_token, new_refresh_token}

            {:ok, data} ->
              Logger.warning(
                "[QB Client] attempt_token_refresh: Unexpected token refresh response",
                data: inspect(data),
                response_keys:
                  if(is_map(data), do: Map.keys(data), else: :not_a_map)
              )

              {:error, :invalid_token_response}

            {:error, error} ->
              Logger.warning(
                "[QB Client] attempt_token_refresh: Failed to parse token refresh response",
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          Logger.warning(
            "[QB Client] attempt_token_refresh: Token refresh failed",
            status: status,
            response: response_body
          )

          {:error, :token_refresh_failed}

        {:error, error} ->
          Logger.warning(
            "[QB Client] attempt_token_refresh: Request failed during token refresh",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    else
      error ->
        Logger.warning(
          "[QB Client] attempt_token_refresh: Failed to get required credentials",
          error: inspect(error)
        )

        error
    end
  end

  defp get_client_id do
    case Application.get_env(:ysc, :quickbooks)[:client_id] do
      nil ->
        Logger.warning(
          "[QB Client] get_client_id: QUICKBOOKS_CLIENT_ID not configured"
        )

        {:error, :quickbooks_client_id_not_configured}

      client_id ->
        Logger.debug("[QB Client] get_client_id: Client ID found",
          has_client_id: !is_nil(client_id)
        )

        {:ok, client_id}
    end
  end

  defp get_client_secret do
    case Application.get_env(:ysc, :quickbooks)[:client_secret] do
      nil ->
        Logger.warning(
          "[QB Client] get_client_secret: QUICKBOOKS_CLIENT_SECRET not configured"
        )

        {:error, :quickbooks_client_secret_not_configured}

      client_secret ->
        Logger.debug("[QB Client] get_client_secret: Client secret found",
          has_client_secret: !is_nil(client_secret)
        )

        {:ok, client_secret}
    end
  end

  defp update_token_config(access_token, refresh_token) do
    # IMPORTANT: Tokens are now persisted to SiteSettings database automatically
    # via cache_access_token and cache_refresh_token functions.
    # The in-memory config is still updated for backward compatibility.

    current_config = Application.get_env(:ysc, :quickbooks, [])

    updated_config =
      Keyword.merge(current_config,
        access_token: access_token,
        refresh_token: refresh_token
      )

    Application.put_env(:ysc, :quickbooks, updated_config)

    Logger.debug("[QB Client] update_token_config: Updated in-memory config",
      has_access_token: !is_nil(access_token),
      has_refresh_token: !is_nil(refresh_token)
    )

    # Tokens are persisted to DB via cache_access_token and cache_refresh_token
    # which are called from refresh_access_token after successful token refresh
  end

  defp get_original_refresh_token do
    # Get the original refresh token from environment variable (source of truth)
    System.get_env("QUICKBOOKS_REFRESH_TOKEN")
  end

  defp get_cached_access_token do
    case Cachex.get(:ysc_cache, "quickbooks:access_token") do
      {:ok, nil} ->
        # Cache is empty, try loading from SiteSettings DB, then fall back to config
        load_access_token_from_db_or_config()

      {:ok, token} ->
        token

      {:error, _reason} ->
        # Cache error - try loading from SiteSettings DB, then fall back to config
        load_access_token_from_db_or_config()
    end
  end

  defp load_access_token_from_db_or_config do
    # First try loading from DB
    case Ysc.Settings.get_setting_safe("quickbooks_access_token") do
      nil ->
        # Not in DB, fall back to config (env variables)
        fallback_to_config_access_token()

      token when is_binary(token) ->
        # Found token in DB, cache it for future use (without persisting back to DB)
        Logger.debug(
          "[QB Client] load_access_token_from_db_or_config: Loaded token from DB, caching it"
        )

        Cachex.put(:ysc_cache, "quickbooks:access_token", token)
        token

      _ ->
        # Invalid value in DB, fall back to config
        fallback_to_config_access_token()
    end
  end

  defp fallback_to_config_access_token do
    # Fall back to environment variables (Application config)
    qb_config = Application.get_env(:ysc, :quickbooks, [])

    case qb_config[:access_token] do
      nil ->
        Logger.debug(
          "[QB Client] fallback_to_config_access_token: No access token in cache, DB, or config"
        )

        nil

      token when is_binary(token) ->
        Logger.debug(
          "[QB Client] fallback_to_config_access_token: Using access token from config (env variable)"
        )

        # Cache it for future use
        Cachex.put(:ysc_cache, "quickbooks:access_token", token)
        token

      _ ->
        nil
    end
  end

  defp get_cached_refresh_token do
    case Cachex.get(:ysc_cache, "quickbooks:refresh_token") do
      {:ok, nil} ->
        # Cache is empty, try loading from SiteSettings DB, then fall back to config
        load_refresh_token_from_db_or_config()

      {:ok, token} ->
        token

      {:error, _reason} ->
        # Cache error - try loading from SiteSettings DB, then fall back to config
        load_refresh_token_from_db_or_config()
    end
  end

  defp load_refresh_token_from_db_or_config do
    # First try loading from DB
    case Ysc.Settings.get_setting_safe("quickbooks_refresh_token") do
      nil ->
        # Not in DB, fall back to config (env variables)
        fallback_to_config_refresh_token()

      token when is_binary(token) ->
        # Found token in DB, cache it for future use (without persisting back to DB)
        Logger.debug(
          "[QB Client] load_refresh_token_from_db_or_config: Loaded token from DB, caching it"
        )

        Cachex.put(:ysc_cache, "quickbooks:refresh_token", token)
        token

      _ ->
        # Invalid value in DB, fall back to config
        fallback_to_config_refresh_token()
    end
  end

  defp fallback_to_config_refresh_token do
    # Fall back to environment variables (Application config or System.get_env)
    qb_config = Application.get_env(:ysc, :quickbooks, [])
    env_token = System.get_env("QUICKBOOKS_REFRESH_TOKEN")

    refresh_token = qb_config[:refresh_token] || env_token

    case refresh_token do
      nil ->
        Logger.debug(
          "[QB Client] fallback_to_config_refresh_token: No refresh token in cache, DB, or config"
        )

        nil

      token when is_binary(token) ->
        Logger.debug(
          "[QB Client] fallback_to_config_refresh_token: Using refresh token from config (env variable)"
        )

        # Cache it for future use
        Cachex.put(:ysc_cache, "quickbooks:refresh_token", token)
        token

      _ ->
        nil
    end
  end

  defp cache_access_token(access_token) do
    # Always persist to database when token changes
    persist_access_token_to_db(access_token)

    # Also cache for performance
    case Cachex.put(:ysc_cache, "quickbooks:access_token", access_token) do
      {:ok, true} ->
        Logger.debug(
          "[QB Client] cache_access_token: Successfully cached access token"
        )

      {:error, reason} ->
        Logger.warning(
          "[QB Client] cache_access_token: Failed to cache access token",
          error: inspect(reason)
        )
    end
  end

  defp persist_access_token_to_db(access_token) do
    # Get current token from DB (if it exists)
    current_token = Ysc.Settings.get_setting_safe("quickbooks_access_token")

    cond do
      is_nil(current_token) ->
        # Setting doesn't exist, create it
        case Ysc.Settings.get_or_create_setting(
               "quickbooks_access_token",
               "quickbooks",
               access_token
             ) do
          _ ->
            Logger.debug(
              "[QB Client] persist_access_token_to_db: Created new access token setting"
            )
        end

      current_token != access_token ->
        # Token changed, update it
        case Ysc.Settings.update_setting(
               "quickbooks_access_token",
               access_token
             ) do
          {:ok, _} ->
            Logger.debug(
              "[QB Client] persist_access_token_to_db: Updated access token in DB"
            )

          {:error, reason} ->
            Logger.error(
              "[QB Client] persist_access_token_to_db: Failed to update access token in DB",
              error: inspect(reason)
            )
        end

      true ->
        # Token is the same, no update needed
        Logger.debug(
          "[QB Client] persist_access_token_to_db: Access token unchanged, skipping DB update"
        )
    end
  rescue
    error ->
      Logger.error(
        "[QB Client] persist_access_token_to_db: Error persisting access token",
        error: inspect(error)
      )
  end

  defp cache_refresh_token(refresh_token) do
    # Always persist to database when token changes
    persist_refresh_token_to_db(refresh_token)

    # Also cache for performance
    case Cachex.put(:ysc_cache, "quickbooks:refresh_token", refresh_token) do
      {:ok, true} ->
        Logger.debug(
          "[QB Client] cache_refresh_token: Successfully cached refresh token"
        )

      {:error, reason} ->
        Logger.warning(
          "[QB Client] cache_refresh_token: Failed to cache refresh token",
          error: inspect(reason)
        )
    end
  end

  defp persist_refresh_token_to_db(refresh_token) do
    # Get current token from DB (if it exists)
    current_token = Ysc.Settings.get_setting_safe("quickbooks_refresh_token")

    cond do
      is_nil(current_token) ->
        # Setting doesn't exist, create it
        case Ysc.Settings.get_or_create_setting(
               "quickbooks_refresh_token",
               "quickbooks",
               refresh_token
             ) do
          _ ->
            Logger.debug(
              "[QB Client] persist_refresh_token_to_db: Created new refresh token setting"
            )
        end

      current_token != refresh_token ->
        # Token changed, update it
        case Ysc.Settings.update_setting(
               "quickbooks_refresh_token",
               refresh_token
             ) do
          {:ok, _} ->
            Logger.info(
              "[QB Client] persist_refresh_token_to_db: Updated refresh token in DB"
            )

          {:error, reason} ->
            Logger.error(
              "[QB Client] persist_refresh_token_to_db: Failed to update refresh token in DB",
              error: inspect(reason)
            )
        end

      true ->
        # Token is the same, no update needed
        Logger.debug(
          "[QB Client] persist_refresh_token_to_db: Refresh token unchanged, skipping DB update"
        )
    end
  rescue
    error ->
      Logger.error(
        "[QB Client] persist_refresh_token_to_db: Error persisting refresh token",
        error: inspect(error)
      )
  end

  # Cache helper functions for account and class references
  # These are aggressively cached since they don't change

  defp get_cached_class_id(cache_key) do
    case Cachex.get(:ysc_cache, cache_key) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, class_id} ->
        {:ok, class_id}

      {:error, _reason} ->
        # Cache error - return nil to fall back to API query
        {:ok, nil}
    end
  end

  defp cache_class_id(cache_key, class_id) do
    # Cache with no expiration (these don't change)
    case Cachex.put(:ysc_cache, cache_key, class_id, ttl: :infinity) do
      {:ok, true} ->
        Logger.debug("[QB Client] cache_class_id: Successfully cached class",
          cache_key: cache_key,
          class_id: class_id
        )

      {:error, reason} ->
        Logger.warning(
          "[QB Client] cache_class_id: Failed to cache class",
          cache_key: cache_key,
          error: inspect(reason)
        )
    end
  end

  defp get_cached_account_id(cache_key) do
    case Cachex.get(:ysc_cache, cache_key) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, account_id} ->
        {:ok, account_id}

      {:error, _reason} ->
        # Cache error - return nil to fall back to API query
        {:ok, nil}
    end
  end

  defp cache_account_id(cache_key, account_id) do
    # Cache with no expiration (these don't change)
    case Cachex.put(:ysc_cache, cache_key, account_id, ttl: :infinity) do
      {:ok, true} ->
        Logger.debug(
          "[QB Client] cache_account_id: Successfully cached account",
          cache_key: cache_key,
          account_id: account_id
        )

      {:error, reason} ->
        Logger.warning(
          "[QB Client] cache_account_id: Failed to cache account",
          cache_key: cache_key,
          error: inspect(reason)
        )
    end
  end

  @doc """
  Queries for a QuickBooks Vendor by email address.
  Note: QuickBooks API doesn't support querying nested fields like PrimaryEmailAddr.Address
  in WHERE clauses. This function queries all vendors and filters by email in memory.
  Returns {:ok, vendor_id} if found, {:error, :not_found} otherwise.
  """
  @spec query_vendor_by_email(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, atom()}
  def query_vendor_by_email(email, opts \\ [])

  def query_vendor_by_email(email, opts)
      when is_binary(email) and email != "" do
    include_inactive = Keyword.get(opts, :include_inactive, false)

    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      active_filter = if include_inactive, do: "", else: " WHERE Active = true"

      # Query all vendors (QuickBooks doesn't support nested field queries)
      # We'll filter by email in memory
      query =
        "SELECT Id, DisplayName, PrimaryEmailAddr FROM Vendor#{active_filter}"

      url = build_query_url(company_id, query)
      headers = build_headers(access_token)

      Logger.debug("[QB Client] query_vendor_by_email: Querying for vendor",
        email: email,
        query: query
      )

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"QueryResponse" => %{"Vendor" => vendors}}}
            when is_list(vendors) and vendors != [] ->
              vendor = List.first(vendors)
              vendor_id = Map.get(vendor, "Id")
              found_display_name = Map.get(vendor, "DisplayName")

              Logger.debug("[QB Client] query_vendor_by_email: Found vendor",
                vendor_id: vendor_id,
                searched_for: email,
                found_display_name: found_display_name
              )

              {:ok, vendor_id}

            {:ok, %{"QueryResponse" => %{"Vendor" => vendor}}}
            when is_map(vendor) ->
              vendor_id = Map.get(vendor, "Id")
              found_display_name = Map.get(vendor, "DisplayName")

              Logger.debug("[QB Client] query_vendor_by_email: Found vendor",
                vendor_id: vendor_id,
                searched_for: email,
                found_display_name: found_display_name
              )

              {:ok, vendor_id}

            {:ok, %{"QueryResponse" => _}} ->
              Logger.debug("[QB Client] query_vendor_by_email: No vendor found",
                email: email
              )

              {:error, :not_found}

            {:error, error} ->
              Logger.error(
                "[QB Client] query_vendor_by_email: Failed to parse response",
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:get, url, headers)

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, %{"QueryResponse" => %{"Vendor" => vendors}}}
                    when is_list(vendors) ->
                      # Filter vendors by email in memory
                      matching_vendor =
                        Enum.find(vendors, fn vendor ->
                          primary_email =
                            Map.get(vendor, "PrimaryEmailAddr", %{})

                          vendor_email = Map.get(primary_email, "Address", "")

                          String.downcase(vendor_email) ==
                            String.downcase(email)
                        end)

                      case matching_vendor do
                        nil ->
                          {:error, :not_found}

                        vendor ->
                          vendor_id = Map.get(vendor, "Id")
                          {:ok, vendor_id}
                      end

                    {:ok, %{"QueryResponse" => %{"Vendor" => vendor}}}
                    when is_map(vendor) ->
                      # Single vendor returned, check if email matches
                      primary_email = Map.get(vendor, "PrimaryEmailAddr", %{})
                      vendor_email = Map.get(primary_email, "Address", "")

                      if String.downcase(vendor_email) == String.downcase(email) do
                        vendor_id = Map.get(vendor, "Id")
                        {:ok, vendor_id}
                      else
                        {:error, :not_found}
                      end

                    _ ->
                      {:error, :not_found}
                  end

                _ ->
                  {:error, :query_failed}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error(
            "[QB Client] query_vendor_by_email: Query failed - Full response body:\n#{response_body}",
            status: status,
            parsed_error: error,
            query: query
          )

          {:error, error}

        {:error, error} ->
          Logger.error("[QB Client] query_vendor_by_email: Request failed",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  def query_vendor_by_email(_email, _opts), do: {:error, :not_found}

  @doc """
  Queries for a QuickBooks Vendor by display name.
  Returns {:ok, vendor_id} if found, {:error, :not_found} otherwise.
  """
  @spec query_vendor_by_display_name(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, atom()}
  def query_vendor_by_display_name(display_name, opts \\ []) do
    include_inactive = Keyword.get(opts, :include_inactive, false)

    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      active_filter = if include_inactive, do: "", else: " AND Active = true"

      query =
        "SELECT Id, DisplayName FROM Vendor WHERE DisplayName = '#{escape_query_string(display_name)}'#{active_filter}"

      url = build_query_url(company_id, query)
      headers = build_headers(access_token)

      Logger.debug(
        "[QB Client] query_vendor_by_display_name: Querying for vendor",
        display_name: display_name,
        query: query
      )

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"QueryResponse" => %{"Vendor" => vendors}}}
            when is_list(vendors) and vendors != [] ->
              vendor = List.first(vendors)
              vendor_id = Map.get(vendor, "Id")
              found_display_name = Map.get(vendor, "DisplayName")

              Logger.debug(
                "[QB Client] query_vendor_by_display_name: Found vendor",
                vendor_id: vendor_id,
                searched_for: display_name,
                found_display_name: found_display_name
              )

              {:ok, vendor_id}

            {:ok, %{"QueryResponse" => %{"Vendor" => vendor}}}
            when is_map(vendor) ->
              vendor_id = Map.get(vendor, "Id")
              found_display_name = Map.get(vendor, "DisplayName")

              Logger.debug(
                "[QB Client] query_vendor_by_display_name: Found vendor",
                vendor_id: vendor_id,
                searched_for: display_name,
                found_display_name: found_display_name
              )

              {:ok, vendor_id}

            {:ok, %{"QueryResponse" => _}} ->
              Logger.debug(
                "[QB Client] query_vendor_by_display_name: No vendor found",
                display_name: display_name
              )

              {:error, :not_found}

            {:error, error} ->
              Logger.error(
                "[QB Client] query_vendor_by_display_name: Failed to parse response",
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:get, url, headers)

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, %{"QueryResponse" => %{"Vendor" => vendors}}}
                    when is_list(vendors) and vendors != [] ->
                      vendor_id = List.first(vendors) |> Map.get("Id")
                      {:ok, vendor_id}

                    {:ok, %{"QueryResponse" => %{"Vendor" => vendor}}}
                    when is_map(vendor) ->
                      vendor_id = Map.get(vendor, "Id")
                      {:ok, vendor_id}

                    _ ->
                      {:error, :not_found}
                  end

                _ ->
                  {:error, :query_failed}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error(
            "[QB Client] query_vendor_by_display_name: Query failed - Full response body:\n#{response_body}",
            status: status,
            parsed_error: error,
            query: query
          )

          {:error, error}

        {:error, error} ->
          Logger.error(
            "[QB Client] query_vendor_by_display_name: Request failed",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  @doc """
  Creates a Vendor in QuickBooks.
  """
  @spec create_vendor(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def create_vendor(params, opts \\ []) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Support idempotency via requestid parameter
      idempotency_key =
        case Keyword.get(opts, :idempotency_key) do
          nil -> Keyword.get(opts, :requestid)
          key -> key
        end

      url_opts = if idempotency_key, do: [requestid: idempotency_key], else: []
      url = build_url(company_id, "vendor", url_opts)
      headers = build_headers(access_token)
      body = build_vendor_body(params)

      Logger.info("Creating QuickBooks Vendor",
        display_name: params.display_name,
        idempotency_key: idempotency_key
      )

      body_json = Jason.encode!(body, pretty: true)
      Logger.info("[QB Client] create_vendor: Full request body:\n#{body_json}")

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              vendor = get_response_entity(data, "Vendor")
              vendor_id = Map.get(vendor, "Id")
              actual_display_name = Map.get(vendor, "DisplayName")

              Logger.info("Successfully created QuickBooks Vendor",
                vendor_id: vendor_id,
                requested_display_name: params.display_name,
                actual_display_name: actual_display_name
              )

              {:ok, vendor}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "QuickBooks authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              # URL already includes idempotency key for retry
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      vendor = get_response_entity(data, "Vendor")
                      {:ok, vendor}

                    _error ->
                      {:error, :invalid_response}
                  end

                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error(
                    "[QB Client] create_vendor: QuickBooks API error after token refresh - Full response body:\n#{retry_response_body}",
                    status: status,
                    parsed_error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh",
                    error: inspect(error)
                  )

                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token",
                error: inspect(error)
              )

              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          # Try to extract vendor ID from duplicate error response
          vendor_id_from_error = extract_vendor_id_from_error(response_body)

          Logger.error(
            "[QB Client] create_vendor: QuickBooks API error - Full response body:\n#{response_body}",
            status: status,
            parsed_error: error,
            endpoint: "vendor",
            extracted_vendor_id: vendor_id_from_error
          )

          # If we found a vendor ID in the error, return it in a special format
          if vendor_id_from_error do
            {:error, "DUPLICATE_VENDOR_ID:#{vendor_id_from_error}"}
          else
            {:error, error}
          end

        {:error, error} ->
          Logger.error("Failed to create QuickBooks Vendor",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  # Helper function to create vendor with retry logic for duplicate names
  defp create_vendor_with_retry(params, original_display_name, attempt)
       when attempt < 3 do
    case create_vendor(params) do
      {:ok, vendor} ->
        vendor_id = Map.get(vendor, "Id")
        {:ok, vendor_id}

      {:error, error_message} when is_binary(error_message) ->
        # Check if this is a duplicate name error
        if String.starts_with?(error_message, "DUPLICATE_VENDOR_ID:") do
          # Extract vendor ID from error and verify it's actually a Vendor
          extracted_id =
            String.replace_prefix(error_message, "DUPLICATE_VENDOR_ID:", "")

          case verify_vendor_id(extracted_id) do
            {:ok, vendor_id} ->
              Logger.info(
                "[QB Client] create_vendor_with_retry: Duplicate name error, extracted and verified vendor ID",
                vendor_id: vendor_id,
                display_name: params.display_name
              )

              {:ok, vendor_id}

            {:error, :not_a_vendor} ->
              # The ID is not a Vendor (might be a Customer), so create a new Vendor with modified name
              Logger.warning(
                "[QB Client] create_vendor_with_retry: Extracted ID is not a Vendor, creating new Vendor with modified name",
                extracted_id: extracted_id,
                display_name: params.display_name
              )

              suffix =
                if attempt == 0,
                  do: " (#{System.system_time(:second)})",
                  else: " (#{System.system_time(:second)}-#{attempt})"

              new_display_name = original_display_name <> suffix
              new_params = Map.put(params, :display_name, new_display_name)

              create_vendor_with_retry(
                new_params,
                original_display_name,
                attempt + 1
              )

            error ->
              Logger.error(
                "[QB Client] create_vendor_with_retry: Failed to verify extracted vendor ID",
                extracted_id: extracted_id,
                error: inspect(error)
              )

              {:error, error_message}
          end
        else
          if String.contains?(error_message, "Duplicate Name") or
               String.contains?(error_message, "6240") do
            # Duplicate name error - append characters to make it unique
            suffix =
              if attempt == 0,
                do: " (#{System.system_time(:second)})",
                else: " (#{System.system_time(:second)}-#{attempt})"

            new_display_name = original_display_name <> suffix

            Logger.info(
              "[QB Client] create_vendor_with_retry: Duplicate name error, retrying with modified display name",
              original_display_name: original_display_name,
              new_display_name: new_display_name,
              attempt: attempt + 1
            )

            # Retry with modified display name
            new_params = Map.put(params, :display_name, new_display_name)

            create_vendor_with_retry(
              new_params,
              original_display_name,
              attempt + 1
            )
          else
            {:error, error_message}
          end
        end

      error ->
        error
    end
  end

  defp create_vendor_with_retry(_params, original_display_name, attempt) do
    Logger.error(
      "[QB Client] create_vendor_with_retry: Max retries reached for duplicate name",
      original_display_name: original_display_name,
      attempts: attempt
    )

    {:error,
     "Failed to create vendor after #{attempt} attempts due to duplicate name conflicts"}
  end

  # Verify that an ID is actually a Vendor (not a Customer or other entity type)
  defp verify_vendor_id(vendor_id) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      query =
        "SELECT Id FROM Vendor WHERE Id = '#{escape_query_string(vendor_id)}'"

      url = build_query_url(company_id, query)
      headers = build_headers(access_token)

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"QueryResponse" => %{"Vendor" => vendors}}}
            when is_list(vendors) and vendors != [] ->
              {:ok, vendor_id}

            {:ok, %{"QueryResponse" => %{"Vendor" => vendor}}}
            when is_map(vendor) ->
              {:ok, vendor_id}

            {:ok, %{"QueryResponse" => _}} ->
              # ID exists but is not a Vendor (likely a Customer)
              {:error, :not_a_vendor}

            {:error, error} ->
              Logger.error(
                "[QB Client] verify_vendor_id: Failed to parse response",
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("[QB Client] verify_vendor_id: Query failed",
            status: status,
            error: error
          )

          {:error, error}

        {:error, error} ->
          Logger.error("[QB Client] verify_vendor_id: Request failed",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  defp build_vendor_body(params) do
    %{"DisplayName" => params.display_name}
    |> maybe_put("GivenName", params[:given_name])
    |> maybe_put("FamilyName", params[:family_name])
    |> maybe_put("CompanyName", params[:company_name])
    |> maybe_put(
      "PrimaryEmailAddr",
      params[:email] && %{"Address" => params.email}
    )
    |> maybe_put(
      "PrimaryPhone",
      params[:phone] && %{"FreeFormNumber" => params.phone}
    )
    |> maybe_put("AcctNum", params[:acct_num])
    |> maybe_put("BillAddr", build_address(params[:bill_address]))
    |> maybe_put("Notes", params[:notes])
  end

  @doc """
  Gets or creates a QuickBooks Vendor by display name.
  First searches by email if provided, then by display name.
  """
  @spec get_or_create_vendor(String.t(), map()) ::
          {:ok, String.t()} | {:error, atom() | String.t()}
  def get_or_create_vendor(display_name, vendor_params \\ %{}) do
    # First try to find vendor by email if email is provided
    vendor_id =
      if vendor_params[:email] && vendor_params[:email] != "" do
        case query_vendor_by_email(vendor_params[:email]) do
          {:ok, id} ->
            Logger.debug(
              "[QB Client] get_or_create_vendor: Found vendor by email",
              email: vendor_params[:email],
              vendor_id: id
            )

            id

          _ ->
            nil
        end
      else
        nil
      end

    # If found by email, return it
    if vendor_id do
      {:ok, vendor_id}
    else
      # Otherwise, search by display name
      case query_vendor_by_display_name(display_name) do
        {:ok, vendor_id} ->
          Logger.debug(
            "[QB Client] get_or_create_vendor: Found existing vendor",
            display_name: display_name,
            vendor_id: vendor_id
          )

          {:ok, vendor_id}

        {:error, :not_found} ->
          Logger.info(
            "[QB Client] get_or_create_vendor: Vendor not found, creating",
            display_name: display_name,
            email: vendor_params[:email]
          )

          params = Map.merge(%{display_name: display_name}, vendor_params)

          # Try to create vendor, and if we get a duplicate name error, append characters to make it unique
          create_vendor_with_retry(params, display_name, 0)
      end
    end
  end

  @doc """
  Creates a Bill in QuickBooks.
  """
  @spec create_bill(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def create_bill(params, opts \\ []) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Generate idempotency key from expense report ID if provided
      # This ensures retries don't create duplicate bills
      idempotency_key =
        case Keyword.get(opts, :idempotency_key) do
          nil -> Keyword.get(opts, :requestid)
          key -> key
        end

      url_opts = if idempotency_key, do: [requestid: idempotency_key], else: []
      url = build_url(company_id, "bill", url_opts)
      headers = build_headers(access_token)
      body = build_bill_body(params)

      Logger.info("Creating QuickBooks Bill",
        vendor_id: params.vendor_ref[:value],
        idempotency_key: idempotency_key
      )

      body_json = Jason.encode!(body, pretty: true)
      Logger.info("[QB Client] create_bill: Full request body:\n#{body_json}")

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              bill = get_response_entity(data, "Bill")

              Logger.info("Successfully created QuickBooks Bill",
                bill_id: Map.get(bill, "Id")
              )

              {:ok, bill}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "QuickBooks authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              # URL already includes idempotency key for retry
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      bill = get_response_entity(data, "Bill")
                      {:ok, bill}

                    _error ->
                      {:error, :invalid_response}
                  end

                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error(
                    "[QB Client] create_bill: QuickBooks API error after token refresh - Full response body:\n#{retry_response_body}",
                    status: status,
                    parsed_error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh",
                    error: inspect(error)
                  )

                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token",
                error: inspect(error)
              )

              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error(
            "[QB Client] create_bill: QuickBooks API error - Full response body:\n#{response_body}",
            status: status,
            parsed_error: error,
            endpoint: "bill"
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to create QuickBooks Bill",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  defp build_bill_body(params) do
    %{
      "VendorRef" => params.vendor_ref,
      "TxnDate" => params.txn_date,
      "Line" => Enum.map(params.line, &build_bill_line/1)
    }
    |> maybe_put("APAccountRef", params[:ap_account_ref])
    |> maybe_put("PrivateNote", params[:private_note])
    |> maybe_put("DocNumber", params[:doc_number])
  end

  defp build_bill_line(line) do
    base = %{
      "Description" => line.description,
      "Amount" => line.amount,
      "DetailType" => "AccountBasedExpenseLineDetail"
    }

    detail =
      %{
        "AccountRef" => line.account_ref
      }
      |> maybe_put("ClassRef", line[:class_ref])

    Map.put(base, "AccountBasedExpenseLineDetail", detail)
  end

  @doc """
  Uploads an attachment to QuickBooks.
  Returns {:ok, attachable_id} on success.
  """
  @spec upload_attachment(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom() | String.t()}
  def upload_attachment(file_path, file_name, content_type, opts \\ []) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      {request, content_type_header, url, body} =
        build_upload_request(
          file_path,
          file_name,
          content_type,
          company_id,
          access_token,
          opts
        )

      Logger.info("Uploading attachment to QuickBooks", file_name: file_name)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          handle_upload_success_response(response_body, file_name)

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          retry_upload_with_refresh(url, body, content_type_header, file_name)

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error(
            "[QB Client] upload_attachment: QuickBooks API error - Full response body:\n#{response_body}",
            status: status,
            parsed_error: error,
            endpoint: "upload"
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to upload attachment to QuickBooks",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp build_upload_request(
         file_path,
         file_name,
         content_type,
         company_id,
         access_token,
         opts
       ) do
    # Support idempotency via requestid parameter
    idempotency_key =
      case Keyword.get(opts, :idempotency_key) do
        nil -> Keyword.get(opts, :requestid)
        key -> key
      end

    url_opts = if idempotency_key, do: [requestid: idempotency_key], else: []
    url = build_url(company_id, "upload", url_opts)

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Accept", "application/json"}
    ]

    # Read file content
    file_content = File.read!(file_path)

    # Create multipart form data
    boundary = "----WebKitFormBoundary#{:rand.uniform(1_000_000_000)}"
    content_type_header = "multipart/form-data; boundary=#{boundary}"

    body =
      "--#{boundary}\r\n" <>
        "Content-Disposition: form-data; name=\"file_content_0\"; filename=\"#{file_name}\"\r\n" <>
        "Content-Type: #{content_type}\r\n\r\n" <>
        file_content <>
        "\r\n--#{boundary}--\r\n"

    headers = [{"Content-Type", content_type_header} | headers]

    # Log multipart body structure (without file content for size)
    Logger.info(
      "[QB Client] upload_attachment: Request details",
      file_name: file_name,
      content_type: content_type,
      file_size: byte_size(file_content),
      boundary: boundary
    )

    request = Finch.build(:post, url, headers, body)
    {request, content_type_header, url, body}
  end

  defp handle_upload_success_response(response_body, _file_name) do
    case Jason.decode(response_body) do
      {:ok, data} ->
        # Log response data directly in message for visibility
        Logger.info(
          "[QB Client] upload_attachment: Response data - Keys: #{inspect(Map.keys(data))}, Structure: #{inspect(data, limit: 1000)}"
        )

        Logger.info(
          "[QB Client] upload_attachment: Full response body: #{inspect(response_body, limit: 1000)}"
        )

        # Check for Fault errors first
        fault = extract_fault_from_response(data)

        if fault do
          error_message = format_fault_error(fault)

          Logger.error(
            "[QB Client] upload_attachment: QuickBooks returned a fault error: #{error_message}"
          )

          {:error, error_message}
        else
          attachable_id = extract_attachable_id_from_response(data)

          Logger.info(
            "[QB Client] upload_attachment: Extracted attachable ID: #{inspect(attachable_id)}, Response keys: #{inspect(Map.keys(data))}"
          )

          if is_nil(attachable_id) do
            Logger.error(
              "[QB Client] upload_attachment: Attachable ID is nil. Response data: #{inspect(data, limit: 2000)}, Response body: #{inspect(response_body, limit: 2000)}, Keys: #{inspect(Map.keys(data))}"
            )

            {:error, "Attachable ID not found in upload response"}
          else
            Logger.info("Successfully uploaded attachment to QuickBooks",
              attachable_id: attachable_id
            )

            {:ok, attachable_id}
          end
        end

      {:error, error} ->
        Logger.error("Failed to parse QuickBooks response",
          error: inspect(error)
        )

        {:error, :invalid_response}
    end
  end

  defp extract_attachable_id_from_response(data) do
    cond do
      # Try direct Id field first
      Map.has_key?(data, "Id") ->
        Map.get(data, "Id")

      Map.has_key?(data, :Id) ->
        Map.get(data, :Id)

      # Check for AttachableResponse structure FIRST (before get_response_entity)
      Map.has_key?(data, "AttachableResponse") ->
        extract_id_from_attachable_response(data["AttachableResponse"])

      # Try get_response_entity (standard structure)
      true ->
        attachable = get_response_entity(data, "Attachable")
        extract_id_from_attachable(attachable, data)
    end
  end

  defp extract_id_from_attachable_response(attachable_response) do
    Logger.debug(
      "[QB Client] upload_attachment: Checking AttachableResponse structure",
      is_list: is_list(attachable_response),
      length:
        if(is_list(attachable_response),
          do: length(attachable_response),
          else: :not_list
        ),
      first_element:
        if(is_list(attachable_response) and attachable_response != [],
          do: inspect(List.first(attachable_response), limit: 200),
          else: :empty
        )
    )

    case attachable_response do
      # Pattern: [%{"Attachable" => %{"Id" => id}} | _]
      [%{"Attachable" => %{"Id" => id}} | _] ->
        Logger.debug(
          "[QB Client] upload_attachment: Matched pattern with direct Id extraction",
          id: id
        )

        id

      # Pattern: [%{"Attachable" => attachable_map} | _] where attachable_map is a map
      [%{"Attachable" => attachable_map} | _] when is_map(attachable_map) ->
        id = Map.get(attachable_map, "Id") || Map.get(attachable_map, :Id)

        Logger.debug(
          "[QB Client] upload_attachment: Matched pattern with map extraction",
          id: id,
          attachable_map_keys: Map.keys(attachable_map)
        )

        id

      # Fallback: try to extract from first element directly
      [first_element | _] when is_map(first_element) ->
        Logger.debug(
          "[QB Client] upload_attachment: Trying to extract from first element",
          first_element_keys: Map.keys(first_element)
        )

        # Try nested Attachable key
        case Map.get(first_element, "Attachable") do
          %{"Id" => id} when is_binary(id) ->
            Logger.debug(
              "[QB Client] upload_attachment: Found Id in nested Attachable",
              id: id
            )

            id

          attachable_map when is_map(attachable_map) ->
            id = Map.get(attachable_map, "Id") || Map.get(attachable_map, :Id)

            Logger.debug(
              "[QB Client] upload_attachment: Extracted Id from attachable_map",
              id: id
            )

            id

          _ ->
            nil
        end

      _ ->
        Logger.warning(
          "[QB Client] upload_attachment: AttachableResponse structure not recognized",
          attachable_response_type: inspect(attachable_response, limit: 200)
        )

        nil
    end
  end

  defp extract_id_from_attachable(attachable, data) do
    cond do
      # Check if attachable is a map with Id
      is_map(attachable) ->
        Map.get(attachable, "Id") || Map.get(attachable, :Id)

      # Check if attachable is a list
      is_list(attachable) ->
        case attachable do
          [%{"Id" => id} | _] -> id
          [%{Id: id} | _] -> id
          _ -> nil
        end

      # Try other nested structures
      true ->
        extract_id_from_nested_structures(data)
    end
  end

  defp extract_id_from_nested_structures(data) do
    case data do
      # AttachableResponse is a map (not a list)
      %{"AttachableResponse" => %{"Attachable" => %{"Id" => id}}} ->
        id

      %{"AttachableResponse" => %{"Attachable" => [%{"Id" => id} | _]}} ->
        id

      %{"AttachableResponse" => %{"Attachable" => attachable_map}}
      when is_map(attachable_map) ->
        Map.get(attachable_map, "Id") || Map.get(attachable_map, :Id)

      # Direct Attachable (no AttachableResponse wrapper)
      %{"Attachable" => %{"Id" => id}} ->
        id

      %{"Attachable" => [%{"Id" => id} | _]} ->
        id

      %{"Attachable" => attachable_map} when is_map(attachable_map) ->
        Map.get(attachable_map, "Id") || Map.get(attachable_map, :Id)

      # Check for case-insensitive keys
      _ ->
        # Try to find any key that contains "id" (case-insensitive)
        data
        |> Map.to_list()
        |> Enum.find_value(fn
          {key, value} when is_binary(key) ->
            if String.downcase(key) == "id" do
              value
            else
              nil
            end

          {key, value} when is_atom(key) ->
            if Atom.to_string(key) |> String.downcase() == "id" do
              value
            else
              nil
            end

          _ ->
            nil
        end)
    end
  end

  defp retry_upload_with_refresh(url, body, content_type_header, file_name) do
    Logger.warning("QuickBooks authentication failed, attempting token refresh")

    case refresh_access_token() do
      {:ok, new_access_token} ->
        # Rebuild request with new token
        headers = [
          {"Authorization", "Bearer #{new_access_token}"},
          {"Accept", "application/json"},
          {"Content-Type", content_type_header}
        ]

        request = Finch.build(:post, url, headers, body)

        case Finch.request(request, Ysc.Finch) do
          {:ok, %Finch.Response{status: status, body: retry_response_body}}
          when status in 200..299 ->
            handle_upload_success_response(retry_response_body, file_name)

          {:ok, %Finch.Response{status: status, body: retry_response_body}} ->
            error = parse_error_response(retry_response_body)

            Logger.error(
              "[QB Client] upload_attachment: QuickBooks API error after token refresh - Full response body:\n#{retry_response_body}",
              status: status,
              parsed_error: error
            )

            {:error, error}

          {:error, error} ->
            Logger.error("Request failed after token refresh",
              error: inspect(error)
            )

            {:error, :request_failed}
        end

      error ->
        Logger.error("Failed to refresh QuickBooks access token",
          error: inspect(error)
        )

        {:error, :authentication_failed}
    end
  end

  @doc """
  Links an attachment to a Bill in QuickBooks.
  """
  @spec link_attachment_to_bill(String.t(), String.t()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def link_attachment_to_bill(attachable_id, bill_id) do
    if is_nil(attachable_id) || attachable_id == "" do
      Logger.error(
        "[QB Client] link_attachment_to_bill: Attachable ID is nil or empty",
        attachable_id: attachable_id,
        bill_id: bill_id
      )

      {:error, "Attachable ID is required"}
    else
      with {:ok, access_token} <- get_access_token(),
           {:ok, company_id} <- get_company_id() do
        url = "#{build_url(company_id, "attachable")}&operation=update"
        headers = build_headers(access_token)

        body = %{
          "Id" => attachable_id,
          "SyncToken" => "0",
          "AttachableRef" => [
            %{
              "EntityRef" => %{
                "type" => "Bill",
                "value" => bill_id
              }
            }
          ]
        }

        Logger.info("Linking attachment to Bill",
          attachable_id: attachable_id,
          bill_id: bill_id
        )

        body_json = Jason.encode!(body, pretty: true)

        Logger.info(
          "[QB Client] link_attachment_to_bill: Full request body:\n#{body_json}"
        )

        request = Finch.build(:post, url, headers, Jason.encode!(body))

        case Finch.request(request, Ysc.Finch) do
          {:ok, %Finch.Response{status: status, body: response_body}}
          when status in 200..299 ->
            Logger.info(
              "[QB Client] link_attachment_to_bill: Success response received",
              status: status,
              response_length: byte_size(response_body)
            )

            case Jason.decode(response_body) do
              {:ok, data} ->
                Logger.info(
                  "[QB Client] link_attachment_to_bill: Response data structure",
                  keys: Map.keys(data),
                  full_response: inspect(data, limit: 1000)
                )

                attachable = get_response_entity(data, "Attachable")

                Logger.info(
                  "[QB Client] link_attachment_to_bill: Extracted attachable",
                  attachable_keys:
                    if(is_map(attachable),
                      do: Map.keys(attachable),
                      else: :not_map
                    ),
                  attachable_id:
                    if(is_map(attachable),
                      do: Map.get(attachable, "Id"),
                      else: :not_map
                    ),
                  attachable_ref:
                    if(is_map(attachable),
                      do: Map.get(attachable, "AttachableRef"),
                      else: :not_map
                    )
                )

                # Verify the attachment was linked correctly by checking AttachableRef
                if is_map(attachable) do
                  attachable_refs = Map.get(attachable, "AttachableRef", [])

                  Logger.info(
                    "[QB Client] link_attachment_to_bill: Verifying attachment link",
                    attachable_refs: inspect(attachable_refs, limit: 500),
                    expected_bill_id: bill_id
                  )

                  # Check if the bill is in the AttachableRef list
                  linked_to_bill =
                    Enum.any?(attachable_refs, fn ref ->
                      case ref do
                        %{
                          "EntityRef" => %{
                            "type" => "Bill",
                            "value" => ref_bill_id
                          }
                        } ->
                          ref_bill_id == bill_id

                        _ ->
                          false
                      end
                    end)

                  if linked_to_bill do
                    Logger.info(
                      "[QB Client] link_attachment_to_bill: ✅ Verified - Attachment is linked to bill",
                      attachable_id: Map.get(attachable, "Id"),
                      bill_id: bill_id
                    )
                  else
                    Logger.warning(
                      "[QB Client] link_attachment_to_bill: ⚠️ Warning - Attachment may not be linked to bill",
                      attachable_id: Map.get(attachable, "Id"),
                      expected_bill_id: bill_id,
                      actual_refs: inspect(attachable_refs, limit: 500)
                    )
                  end
                end

                Logger.info("Successfully linked attachment to Bill")
                {:ok, attachable}

              {:error, error} ->
                Logger.error("Failed to parse QuickBooks response",
                  error: inspect(error)
                )

                {:error, :invalid_response}
            end

          {:ok, %Finch.Response{status: 401, body: _response_body}} ->
            Logger.warning(
              "QuickBooks authentication failed, attempting token refresh"
            )

            case refresh_access_token() do
              {:ok, new_access_token} ->
                headers = build_headers(new_access_token)
                request = Finch.build(:post, url, headers, Jason.encode!(body))

                case Finch.request(request, Ysc.Finch) do
                  {:ok,
                   %Finch.Response{status: status, body: retry_response_body}}
                  when status in 200..299 ->
                    case Jason.decode(retry_response_body) do
                      {:ok, data} ->
                        attachable = get_response_entity(data, "Attachable")
                        {:ok, attachable}

                      _error ->
                        {:error, :invalid_response}
                    end

                  {:ok,
                   %Finch.Response{status: status, body: retry_response_body}} ->
                    error = parse_error_response(retry_response_body)

                    Logger.error(
                      "[QB Client] link_attachment_to_bill: QuickBooks API error after token refresh - Full response body:\n#{retry_response_body}",
                      status: status,
                      parsed_error: error
                    )

                    {:error, error}

                  {:error, error} ->
                    Logger.error("Request failed after token refresh",
                      error: inspect(error)
                    )

                    {:error, :request_failed}
                end

              error ->
                Logger.error("Failed to refresh QuickBooks access token",
                  error: inspect(error)
                )

                {:error, :authentication_failed}
            end

          {:ok, %Finch.Response{status: status, body: response_body}} ->
            error = parse_error_response(response_body)

            Logger.error(
              "[QB Client] link_attachment_to_bill: QuickBooks API error - Full response body:\n#{response_body}",
              status: status,
              parsed_error: error,
              endpoint: "attachable"
            )

            {:error, error}

          {:error, error} ->
            Logger.error("Failed to link attachment to Bill",
              error: inspect(error)
            )

            {:error, :request_failed}
        end
      end
    end
  end

  @doc """
  Gets a BillPayment by ID from QuickBooks.
  """
  @spec get_bill_payment(String.t()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def get_bill_payment(bill_payment_id) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      url = build_url(company_id, "billpayment/#{bill_payment_id}", [])
      headers = build_headers(access_token)

      Logger.info("Getting QuickBooks BillPayment",
        company_id: company_id,
        bill_payment_id: bill_payment_id
      )

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}}
        when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              bill_payment = get_response_entity(data, "BillPayment")

              Logger.info("Successfully retrieved QuickBooks BillPayment",
                bill_payment_id: Map.get(bill_payment, "Id")
              )

              {:ok, bill_payment}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error),
                response: response_body
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "QuickBooks authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:get, url, headers)

              case Finch.request(request, Ysc.Finch) do
                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      bill_payment = get_response_entity(data, "BillPayment")
                      {:ok, bill_payment}

                    _error ->
                      {:error, :invalid_response}
                  end

                {:ok,
                 %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error(
                    "[QB Client] get_bill_payment: QuickBooks API error after token refresh",
                    status: status,
                    parsed_error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh",
                    error: inspect(error)
                  )

                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token",
                error: inspect(error)
              )

              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("Failed to get QuickBooks BillPayment",
            status: status,
            error: error,
            bill_payment_id: bill_payment_id
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to get BillPayment from QuickBooks",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end
end
