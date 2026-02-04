defmodule Ysc.Ledgers.LedgerAccount do
  @moduledoc """
  Ledger account schema and changesets.

  Defines the LedgerAccount database schema, validations, and changeset functions
  for ledger account data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ledger_accounts" do
    field :account_type, LedgerAccountType
    field :normal_balance, LedgerNormalBalance
    field :name, :string
    field :description, :string

    timestamps()
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:account_type, :normal_balance, :name, :description])
    |> validate_required([:account_type, :normal_balance, :name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> unique_constraint(:name)
  end
end
