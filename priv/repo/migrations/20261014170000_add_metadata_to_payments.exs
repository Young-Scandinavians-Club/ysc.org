defmodule Ysc.Repo.Migrations.AddMetadataToPayments do
  @moduledoc """
  Stripe donation Payment Links store their QuickBooks income account on the
  payment (`metadata["quickbooks_income_account"]`) instead of encoding it in
  the ledger description.
  """
  use Ecto.Migration

  def change do
    alter table(:payments) do
      add :metadata, :map, default: %{}, null: false
    end
  end
end
