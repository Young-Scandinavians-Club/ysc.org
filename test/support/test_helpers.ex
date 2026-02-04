defmodule Ysc.TestHelpers do
  @moduledoc """
  Common test helpers for creating test data and making assertions.

  Import this module in your test files to use the helper functions.
  """

  alias Ysc.Ledgers
  alias Ysc.Repo

  @doc """
  Asserts that the ledger is balanced.
  Use this in test files that import ExUnit.Case.
  """
  def assert_ledger_balanced do
    import ExUnit.Assertions

    case Ledgers.verify_ledger_balance() do
      {:ok, :balanced} ->
        :ok

      {:error, details} ->
        flunk("Ledger is not balanced: #{inspect(details)}")
    end
  end

  @doc """
  Gets the balance for a specific account by name.
  """
  def get_account_balance(account_name) do
    account = Ledgers.get_account_by_name(account_name)
    Ledgers.get_account_balance(account.id)
  end

  @doc """
  Asserts that an account has a specific balance.
  Use this in test files that import ExUnit.Case.
  """
  def assert_account_balance(account_name, expected_amount) do
    import ExUnit.Assertions

    balance = get_account_balance(account_name)

    assert Money.equal?(balance, expected_amount),
           "Expected #{account_name} balance to be #{Money.to_string!(expected_amount)}, got #{Money.to_string!(balance)}"
  end

  @doc """
  Creates a user with lifetime membership for testing.
  """
  def user_with_membership(attrs \\ %{}) do
    import Ysc.AccountsFixtures

    user =
      attrs
      |> Map.put_new(
        :lifetime_membership_awarded_at,
        DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> user_fixture()

    user
  end

  @doc """
  Waits for async operations to complete.
  """
  def wait_for_async(timeout_ms \\ 1000) do
    Process.sleep(timeout_ms)
  end

  @doc """
  Reloads a struct from the database.
  """
  def reload!(struct) do
    Repo.reload!(struct)
  end

  @doc """
  Reloads a struct with preloaded associations.
  """
  def reload_with!(struct, preloads) do
    struct
    |> reload!()
    |> Repo.preload(preloads)
  end

  @doc """
  Sets up QuickBooks mocks for tests.
  """
  def setup_quickbooks_mocks do
    import Mox

    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      event_item_id: "event_item_123",
      donation_item_id: "donation_item_123",
      clear_lake_booking_item_id: "clear_lake_item_123",
      tahoe_booking_item_id: "tahoe_item_123",
      bank_account_id: "bank_account_123",
      stripe_account_id: "stripe_account_123"
    )

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
      {:ok, %{"Id" => "qb_customer_default"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params ->
      {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_refund_receipt, fn _params ->
      {:ok, %{"Id" => "qb_refund_receipt_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
      {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn
      "Undeposited Funds" -> {:ok, "undeposited_funds_account_default"}
      _ -> {:error, :not_found}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn
      "Events" -> {:ok, "events_class_default"}
      "Administration" -> {:ok, "admin_class_default"}
      _ -> {:error, :not_found}
    end)

    :ok
  end
end
