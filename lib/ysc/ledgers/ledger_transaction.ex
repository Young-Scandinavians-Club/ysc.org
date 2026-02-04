defmodule Ysc.Ledgers.LedgerTransaction do
  @moduledoc """
  Ledger transaction schema and changesets.

  Defines the LedgerTransaction database schema, validations, and changeset functions
  for ledger transaction data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ledger_transactions" do
    field :type, LedgerTransactionType

    belongs_to :payment, Ysc.Ledgers.Payment,
      foreign_key: :payment_id,
      references: :id

    belongs_to :refund, Ysc.Ledgers.Refund,
      foreign_key: :refund_id,
      references: :id

    field :total_amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :status, LedgerTransactionStatus

    timestamps()
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:type, :payment_id, :refund_id, :total_amount, :status])
    |> validate_required([:type, :total_amount, :status])
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:refund_id)
  end
end
