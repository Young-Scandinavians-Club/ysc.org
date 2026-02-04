defmodule Ysc.Ledgers.Refund do
  @moduledoc """
  Refund schema and changesets.

  Defines the Refund database schema, validations, and changeset functions
  for refund data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @reference_prefix "RFD"

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "refunds" do
    field :reference_id, :string

    field :external_provider, LedgerPaymentProvider
    field :external_refund_id, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD

    field :reason, :string
    field :status, LedgerPaymentStatus

    # QuickBooks sync fields
    field :quickbooks_sales_receipt_id, :string
    field :quickbooks_sync_status, :string
    field :quickbooks_sync_error, :map
    field :quickbooks_response, :map
    field :quickbooks_synced_at, :utc_datetime
    field :quickbooks_last_sync_attempt_at, :utc_datetime

    # Reference to the original payment being refunded
    belongs_to :payment, Ysc.Ledgers.Payment,
      foreign_key: :payment_id,
      references: :id

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    timestamps()
  end

  def changeset(refund, attrs \\ %{}) do
    refund
    |> cast(attrs, [
      :reference_id,
      :external_provider,
      :external_refund_id,
      :amount,
      :reason,
      :status,
      :payment_id,
      :user_id,
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
      :status,
      :payment_id
    ])
    |> validate_length(:external_refund_id, max: 255)
    |> validate_length(:reference_id, max: 255)
    |> validate_length(:reason, max: 1000)
    |> put_reference_id()
    |> unique_constraint(:reference_id)
    |> unique_constraint(:external_refund_id)
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:user_id)
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
