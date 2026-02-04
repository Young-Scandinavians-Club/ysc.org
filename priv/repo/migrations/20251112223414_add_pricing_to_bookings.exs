defmodule Ysc.Repo.Migrations.AddPricingToBookings do
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      add :total_price, :money_with_currency, null: true
      add :pricing_items, :jsonb, null: true
    end

    create index(:bookings, [:total_price], where: "total_price IS NOT NULL")
  end
end
