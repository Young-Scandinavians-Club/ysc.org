defmodule Ysc.Quickbooks.ClientBehaviour do
  @moduledoc """
  Behaviour for QuickBooks API client to enable testing with mocks.
  """

  @doc """
  Creates a SalesReceipt in QuickBooks.
  """
  @callback create_sales_receipt(map()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @callback create_sales_receipt(map(), keyword()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Creates a Deposit in QuickBooks.
  """
  @callback create_deposit(map()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @callback create_deposit(map(), keyword()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Creates a Customer in QuickBooks.
  """
  @callback create_customer(map()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @callback create_customer(map(), keyword()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Creates a RefundReceipt in QuickBooks.
  """
  @callback create_refund_receipt(map()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @callback create_refund_receipt(map(), keyword()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Gets or creates an item in QuickBooks.
  """
  @callback get_or_create_item(String.t()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @callback get_or_create_item(String.t(), keyword()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @doc """
  Queries for an account by name in QuickBooks.
  """
  @callback query_account_by_name(String.t()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @doc """
  Queries for a class by name in QuickBooks.
  """
  @callback query_class_by_name(String.t()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @doc """
  Queries for a vendor by display name in QuickBooks.
  """
  @callback query_vendor_by_display_name(String.t()) ::
              {:ok, String.t()} | {:error, atom()}

  @callback query_vendor_by_display_name(String.t(), keyword()) ::
              {:ok, String.t()} | {:error, atom()}

  @doc """
  Creates a vendor in QuickBooks.
  """
  @callback create_vendor(map()) :: {:ok, map()} | {:error, atom() | String.t()}

  @callback create_vendor(map(), keyword()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Gets or creates a vendor in QuickBooks.
  """
  @callback get_or_create_vendor(String.t(), map()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @doc """
  Creates a bill in QuickBooks.
  """
  @callback create_bill(map()) :: {:ok, map()} | {:error, atom() | String.t()}

  @callback create_bill(map(), keyword()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Uploads an attachment to QuickBooks.
  """
  @callback upload_attachment(String.t(), String.t(), String.t()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @callback upload_attachment(String.t(), String.t(), String.t(), keyword()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @doc """
  Links an attachment to a bill in QuickBooks.
  """
  @callback link_attachment_to_bill(String.t(), String.t()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Gets a BillPayment by ID from QuickBooks.
  """
  @callback get_bill_payment(String.t()) ::
              {:ok, map()} | {:error, atom() | String.t()}
end
