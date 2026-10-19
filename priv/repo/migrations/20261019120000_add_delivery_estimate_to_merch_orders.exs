defmodule Ysc.Repo.Migrations.AddDeliveryEstimateToMerchOrders do
  use Ecto.Migration

  def change do
    alter table(:merch_orders) do
      # Printful's estimated delivery window for the shipping option chosen,
      # as quoted at checkout.
      add :delivery_estimate_min, :date
      add :delivery_estimate_max, :date
    end
  end
end
