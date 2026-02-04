defmodule Ysc.Ledgers.Payout do
  @moduledoc """
  Payout schema and changesets.

  Defines the Payout database schema for tracking Stripe payouts
  and linking them to payments and refunds.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "payouts" do
    field :stripe_payout_id, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :fee_total, Money.Ecto.Composite.Type, default_currency: :USD
    field :currency, :string
    field :status, :string
    field :arrival_date, :utc_datetime
    field :description, :string
    field :metadata, :map

    # QuickBooks sync fields
    field :quickbooks_deposit_id, :string
    field :quickbooks_sync_status, :string
    field :quickbooks_sync_error, :map
    field :quickbooks_response, :map
    field :quickbooks_synced_at, :utc_datetime
    field :quickbooks_last_sync_attempt_at, :utc_datetime

    # Link to the payment record created for this payout in the ledger
    belongs_to :payment, Ysc.Ledgers.Payment,
      foreign_key: :payment_id,
      references: :id

    # Many-to-many relationships with payments and refunds
    many_to_many :payments, Ysc.Ledgers.Payment,
      join_through: "payout_payments",
      join_keys: [payout_id: :id, payment_id: :id]

    many_to_many :refunds, Ysc.Ledgers.Refund,
      join_through: "payout_refunds",
      join_keys: [payout_id: :id, refund_id: :id]

    timestamps()
  end

  def changeset(payout, attrs \\ %{}) do
    payout
    |> cast(attrs, [
      :stripe_payout_id,
      :amount,
      :fee_total,
      :currency,
      :status,
      :arrival_date,
      :description,
      :metadata,
      :payment_id,
      :quickbooks_deposit_id,
      :quickbooks_sync_status,
      :quickbooks_sync_error,
      :quickbooks_response,
      :quickbooks_synced_at,
      :quickbooks_last_sync_attempt_at
    ])
    |> validate_required([:stripe_payout_id, :amount, :currency, :status])
    |> validate_length(:stripe_payout_id, max: 255)
    |> validate_length(:description, max: 1000)
    |> unique_constraint(:stripe_payout_id)
  end
end
