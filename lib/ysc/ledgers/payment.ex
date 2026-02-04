defmodule Ysc.Ledgers.Payment do
  @moduledoc """
  Payment schema and changesets.

  Defines the Payment database schema, validations, and changeset functions
  for payment data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @reference_prefix "PMT"

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "payments" do
    field :reference_id, :string

    field :external_provider, LedgerPaymentProvider
    field :external_payment_id, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD

    field :status, LedgerPaymentStatus
    field :payment_date, :utc_datetime

    # QuickBooks sync fields
    field :quickbooks_sales_receipt_id, :string
    field :quickbooks_sync_status, :string
    field :quickbooks_sync_error, :map
    field :quickbooks_response, :map
    field :quickbooks_synced_at, :utc_datetime
    field :quickbooks_last_sync_attempt_at, :utc_datetime

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    belongs_to :payment_method, Ysc.Payments.PaymentMethod,
      foreign_key: :payment_method_id,
      references: :id

    timestamps()
  end

  def changeset(payment, attrs \\ %{}) do
    payment
    |> cast(attrs, [
      :reference_id,
      :external_provider,
      :external_payment_id,
      :amount,
      :status,
      :payment_date,
      :user_id,
      :payment_method_id,
      :quickbooks_sales_receipt_id,
      :quickbooks_sync_status,
      :quickbooks_sync_error,
      :quickbooks_response,
      :quickbooks_synced_at,
      :quickbooks_last_sync_attempt_at
    ])
    |> validate_required([
      :external_provider,
      :amount,
      :status
    ])
    |> validate_length(:external_payment_id, max: 255)
    |> validate_length(:reference_id, max: 255)
    |> put_reference_id()
    |> unique_constraint(:reference_id)
    |> unique_constraint(:external_payment_id)
  end

  defp put_reference_id(changeset) do
    case get_field(changeset, :reference_id) do
      nil ->
        put_change(
          changeset,
          :reference_id,
          Ysc.ReferenceGenerator.generate_reference_id(@reference_prefix)
        )

      _ ->
        changeset
    end
  end
end
