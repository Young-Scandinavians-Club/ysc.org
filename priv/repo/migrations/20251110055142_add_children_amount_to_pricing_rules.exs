defmodule Ysc.Repo.Migrations.AddChildrenAmountToPricingRules do
  use Ecto.Migration

  def change do
    alter table(:pricing_rules) do
      add :children_amount, :money_with_currency, null: true
    end
  end
end
