defmodule Ysc.Ledgers.LedgerEntry do
  @moduledoc """
  Ledger entry schema and changesets.

  Defines the LedgerEntry database schema, validations, and changeset functions
  for ledger entry data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ledger_entries" do
    belongs_to :account, Ysc.Ledgers.LedgerAccount,
      foreign_key: :account_id,
      references: :id

    field :related_entity_type, LedgerEntryEntityType
    field :related_entity_id, Ecto.ULID

    belongs_to :payment, Ysc.Ledgers.Payment,
      foreign_key: :payment_id,
      references: :id

    belongs_to :refund, Ysc.Ledgers.Refund,
      foreign_key: :refund_id,
      references: :id

    field :description, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :debit_credit, LedgerEntryDebitCredit

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :account_id,
      :related_entity_type,
      :related_entity_id,
      :payment_id,
      :refund_id,
      :description,
      :amount,
      :debit_credit
    ])
    |> validate_required([:account_id, :amount, :debit_credit])
    |> validate_length(:description, max: 1000)
    |> validate_amount()
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:payment_id)
    |> foreign_key_constraint(:refund_id)
  end

  # Validates that the amount is positive and in USD
  defp validate_amount(changeset) do
    amount = get_field(changeset, :amount)

    cond do
      is_nil(amount) ->
        # Already validated as required
        changeset

      not is_struct(amount, Money) ->
        add_error(changeset, :amount, "must be a Money value")

      Money.negative?(amount) ->
        add_error(changeset, :amount, "must be positive")

      amount.currency != :USD ->
        add_error(changeset, :amount, "must be in USD currency")

      true ->
        changeset
    end
  end
end
