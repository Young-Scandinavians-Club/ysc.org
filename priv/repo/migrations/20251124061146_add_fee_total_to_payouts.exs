defmodule Ysc.Repo.Migrations.AddFeeTotalToPayouts do
  use Ecto.Migration

  def change do
    alter table(:payouts) do
      add :fee_total, :money_with_currency
    end
  end
end
